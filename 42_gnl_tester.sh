#!/usr/bin/env bash
# ============================================================================
#  42_gnl_tester  -  Get Next Line (sujet 42 v14.3)
#
#  Usage (depuis le dossier de ton projet) :
#       bash 42_gnl_tester.sh
#       bash ../42_gnl_tester.sh            (si le testeur est dans le dossier parent)
#       bash 42_gnl_tester.sh -q            (n'affiche que les KO / WARN)
#       bash 42_gnl_tester.sh /chemin/vers/projet
#
#  [ OK ]  vert    : test réussi
#  [ KO ]  rouge   : test raté  (ligne grise = explication / attendu vs reçu)
#  [WARN]  jaune   : ça passerait à la moulinette mais c'est problématique
#                    (fuite mémoire, accès invalide, trop lent, norminette absente...)
# ============================================================================

QUIET=0
DIR=""
SCRIPT_NAME=$(basename "$0")

for a in "$@"; do
	case "$a" in
		-q|--quiet) QUIET=1 ;;
		-h|--help)  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*)          DIR="$a" ;;
	esac
done
[ -z "$DIR" ] && DIR="$PWD"
DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "Dossier introuvable : $DIR"; exit 1; }

# ───────────────────────────── couleurs ─────────────────────────────────────
GREEN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRAY=$'\033[90m'
CYAN=$'\033[36m';  BOLD=$'\033[1m';  RST=$'\033[0m'
TESTER_NAME="42_gnl_tester"

C_OK=0; C_KO=0; C_WARN=0
M_OK=0; M_KO=0; M_WARN=0
B_OK=0; B_KO=0; B_WARN=0

gray() { printf '%s\n' "$1" | head -n "${2:-10}" | while IFS= read -r l; do printf '         %s↳ %s%s\n' "$GRAY" "$l" "$RST"; done; }
ok()   { C_OK=$((C_OK+1)); }
ko()   { C_KO=$((C_KO+1));     printf '  %s[ KO ]%s %s\n' "$RED" "$RST" "$1"; [ -n "$2" ] && gray "$2" "${3:-10}"; }
warn() { C_WARN=$((C_WARN+1)); printf '  %s[WARN]%s %s\n' "$YEL" "$RST" "$1"; [ -n "$2" ] && gray "$2" "${3:-10}"; }
title(){ printf '\n%s━━━ %s ━━━%s\n' "$CYAN" "$1" "$RST"; }

# ───────────────────────────── outils ───────────────────────────────────────
command -v cc >/dev/null 2>&1 || { echo "cc introuvable : impossible de compiler."; exit 1; }
TIMEOUT_BIN=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN=timeout
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout
tmo() { local t=$1; shift; if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$t" "$@"; else "$@"; fi; }

MEM_TOOL="none"
if command -v valgrind >/dev/null 2>&1; then
	MEM_TOOL="valgrind"
else
	echo 'int main(void){return 0;}' > /tmp/.gnl_probe_$$.c
	if cc -fsanitize=address /tmp/.gnl_probe_$$.c -o /tmp/.gnl_probe_$$ >/dev/null 2>&1 \
		&& /tmp/.gnl_probe_$$ >/dev/null 2>&1; then MEM_TOOL="asan"; fi
	rm -f /tmp/.gnl_probe_$$.c /tmp/.gnl_probe_$$
fi

T=$(mktemp -d 2>/dev/null || mktemp -d -t gnltest)
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$T/f" "$T/o" "$T/bin"

M_FILES="get_next_line.c get_next_line_utils.c get_next_line.h"
M_SRC="get_next_line.c get_next_line_utils.c"
B_FILES="get_next_line_bonus.c get_next_line_bonus.h get_next_line_utils_bonus.c"
B_SRC="get_next_line_bonus.c get_next_line_utils_bonus.c"
BS_LIST="1 2 7 42 9999 10000000"
BS_BONUS="1 42 9999"

# ───────────────────────────── harnais C ────────────────────────────────────
cat > "$T/harness.c" <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

char	*get_next_line(int fd);

typedef struct s_src
{
	int		fd;
	FILE	*ref;
	char	*exp;
	size_t	cap;
	int		line;
	int		done;
}	t_src;

static void	show(const char *s, size_t len)
{
	size_t			i;
	unsigned char	c;

	putchar('"');
	for (i = 0; i < len && i < 48; i++)
	{
		c = (unsigned char)s[i];
		if (c == '\n') printf("\\n");
		else if (c == '\t') printf("\\t");
		else if (c == '\r') printf("\\r");
		else if (c == '"') printf("\\\"");
		else if (c < 32 || c == 127) printf("\\x%02x", c);
		else putchar(c);
	}
	if (len > 48)
		printf("...");
	putchar('"');
	printf(" [%zu octets]", len);
}

static int	src_init(t_src *s, int fd, const char *path)
{
	memset(s, 0, sizeof(*s));
	s->fd = fd;
	s->ref = fopen(path, "r");
	if (!s->ref)
	{
		printf("(testeur) impossible d'ouvrir %s\n", path);
		return (1);
	}
	return (0);
}

static void	src_end(t_src *s)
{
	free(s->exp);
	if (s->ref)
		fclose(s->ref);
}

static void	mismatch(t_src *s, size_t n, const char *got)
{
	size_t	i;
	size_t	gl;

	gl = strlen(got);
	printf("ligne %d (fd %d) : contenu incorrect\n", s->line, s->fd);
	printf("attendu : "); show(s->exp, n); printf("\n");
	printf("reçu    : "); show(got, gl); printf("\n");
	i = 0;
	while (i < n && i < gl && s->exp[i] == got[i])
		i++;
	if (i < n && i < gl)
		printf("1ère différence à l'index %zu (attendu 0x%02x, reçu 0x%02x)\n",
			i, (unsigned char)s->exp[i], (unsigned char)got[i]);
	else if (i >= gl)
		printf("la ligne retournée est trop courte (il manque la fin)\n");
	else
		printf("la ligne retournée est trop longue (il y a du texte en trop)\n");
	if (n && s->exp[n - 1] == '\n' && (!gl || got[gl - 1] != '\n'))
		printf("le '\\n' final doit faire partie de la ligne retournée\n");
	if (n && s->exp[n - 1] != '\n' && gl && got[gl - 1] == '\n')
		printf("dernière ligne du fichier sans '\\n' : n'en ajoute pas\n");
}

static int	step(t_src *s)
{
	ssize_t	n;
	char	*got;

	n = getline(&s->exp, &s->cap, s->ref);
	got = get_next_line(s->fd);
	s->line++;
	if (n < 0)
	{
		s->done = 1;
		if (got)
		{
			printf("appel %d (fd %d) : fin de fichier, NULL attendu\n", s->line, s->fd);
			printf("reçu    : "); show(got, strlen(got)); printf("\n");
			if (!*got)
				printf("une chaîne vide \"\" est retournée au lieu de NULL en fin de fichier\n");
			free(got);
			return (1);
		}
		return (0);
	}
	if (!got)
	{
		printf("ligne %d (fd %d) : NULL reçu alors qu'il restait du texte\n", s->line, s->fd);
		printf("attendu : "); show(s->exp, (size_t)n); printf("\n");
		if (s->line == 1)
			printf("NULL dès le 1er appel sur un fichier non vide (read/malloc raté ?)\n");
		return (1);
	}
	if (strlen(got) != (size_t)n || memcmp(got, s->exp, (size_t)n))
	{
		mismatch(s, (size_t)n, got);
		free(got);
		return (1);
	}
	free(got);
	return (0);
}

static int	eof_check(t_src *s)
{
	char	*got;
	int		i;

	for (i = 0; i < 2; i++)
	{
		got = get_next_line(s->fd);
		if (got)
		{
			printf("appel supplémentaire après la fin (fd %d) : NULL attendu\n", s->fd);
			printf("reçu    : "); show(got, strlen(got)); printf("\n");
			free(got);
			return (1);
		}
	}
	return (0);
}

static int	run_one(int fd, const char *path)
{
	t_src	s;
	int		r;

	if (src_init(&s, fd, path))
		return (2);
	r = 0;
	while (!s.done && !r)
		r = step(&s);
	if (!r)
		r = eof_check(&s);
	src_end(&s);
	return (r);
}

static int	expect_null(const char *what, int fd)
{
	char	*got;
	int		i;

	for (i = 0; i < 2; i++)
	{
		got = get_next_line(fd);
		if (got)
		{
			printf("%s : NULL attendu (appel %d), reçu ", what, i + 1);
			show(got, strlen(got)); printf("\n");
			free(got);
			return (1);
		}
	}
	return (0);
}

static int	multi(int seed, int n, char **paths)
{
	t_src	s[16];
	int		i;
	int		fd;
	int		left;
	int		r;

	if (n > 16)
		n = 16;
	for (i = 0; i < n; i++)
	{
		fd = open(paths[i], O_RDONLY);
		if (fd < 0 || src_init(&s[i], fd, paths[i]))
			return (2);
	}
	left = n;
	r = 0;
	srand((unsigned)seed);
	while (left && !r)
	{
		if (seed == 0)
		{
			for (i = 0; i < n && !r; i++)
			{
				if (s[i].done)
					continue ;
				r = step(&s[i]);
				if (s[i].done)
					left--;
			}
		}
		else
		{
			i = rand() % n;
			while (s[i].done)
				i = (i + 1) % n;
			r = step(&s[i]);
			if (s[i].done)
				left--;
		}
	}
	for (i = 0; i < n && !r; i++)
		r = eof_check(&s[i]);
	for (i = 0; i < n; i++)
	{
		src_end(&s[i]);
		close(s[i].fd);
	}
	return (r);
}

static int	closed_fd(const char *path)
{
	int	fd;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return (2);
	close(fd);
	return (expect_null("fd déjà fermé", fd));
}

static int	dir_fd(void)
{
	int	fd;
	int	r;

	fd = open(".", O_RDONLY);
	if (fd < 0)
		return (0);
	r = expect_null("fd d'un dossier (read échoue)", fd);
	close(fd);
	return (r);
}

int	main(int ac, char **av)
{
	int		i;
	int		fd;
	int		r;
	char	*got;

	if (ac < 2)
		return (2);
	r = 0;
	if (!strcmp(av[1], "file") && ac >= 3)
	{
		fd = open(av[2], O_RDONLY);
		if (fd < 0)
			return (2);
		r = run_one(fd, av[2]);
		close(fd);
	}
	else if (!strcmp(av[1], "stdin") && ac >= 3)
		r = run_one(0, av[2]);
	else if (!strcmp(av[1], "seq"))
	{
		for (i = 2; i < ac && !r; i++)
		{
			fd = open(av[i], O_RDONLY);
			if (fd < 0)
				return (2);
			r = run_one(fd, av[i]);
			close(fd);
		}
	}
	else if (!strcmp(av[1], "multi") && ac >= 4)
		r = multi(atoi(av[2]), ac - 3, av + 3);
	else if (!strcmp(av[1], "badfd"))
		r = expect_null("fd = -1", -1);
	else if (!strcmp(av[1], "bigfd"))
		r = expect_null("fd = 9999 (non ouvert)", 9999);
	else if (!strcmp(av[1], "closed") && ac >= 3)
		r = closed_fd(av[2]);
	else if (!strcmp(av[1], "dir"))
		r = dir_fd();
	else if (!strcmp(av[1], "invalid") && ac >= 3)
		r = expect_null("fd = -1", -1) || closed_fd(av[2]) || dir_fd();
	else if (!strcmp(av[1], "first"))
	{
		got = get_next_line(0);
		if (!got || strcmp(got, "line1\n"))
		{
			printf("1er appel : \"line1\\n\" attendu, reçu ");
			if (got) show(got, strlen(got)); else printf("NULL");
			printf("\n");
			r = 1;
		}
		free(got);
	}
	else if (!strcmp(av[1], "drain") && ac >= 3)
	{
		fd = open(av[2], O_RDONLY);
		if (fd < 0)
			return (2);
		for (i = 0; i < 300000; i++)
		{
			got = get_next_line(fd);
			if (!got)
				break ;
			free(got);
		}
		close(fd);
		if (i >= 300000)
		{
			printf("get_next_line ne renvoie jamais NULL (boucle sans fin)\n");
			r = 1;
		}
	}
	else if (!strcmp(av[1], "partial") && ac >= 4)
	{
		t_src	s;

		fd = open(av[2], O_RDONLY);
		if (fd < 0 || src_init(&s, fd, av[2]))
			return (2);
		for (i = 0; i < atoi(av[3]) && !s.done && !r; i++)
			r = step(&s);
		src_end(&s);
		close(fd);
	}
	else
		return (2);
	return (r);
}
EOF

if ! cc -g -c "$T/harness.c" -o "$T/harness.o" 2>"$T/harness.log"; then
	echo "Erreur interne : le harnais ne compile pas sur ta machine :"
	cat "$T/harness.log"
	exit 1
fi

# ───────────────────────────── fixtures ─────────────────────────────────────
rep() { head -c "$1" /dev/zero | tr '\0' "$2"; }

mkfixtures() {
	local f="$T/f"
	: > "$f/empty"
	printf '\n' > "$f/nl"
	printf '\n\n\n\n' > "$f/nl4"
	printf 'a' > "$f/one_char"
	printf 'a\n' > "$f/one_char_nl"
	printf 'hello' > "$f/one_line_nonl"
	printf 'hello\n' > "$f/one_line_nl"
	printf 'line1\nline2\nline3\n' > "$f/multi_nl"
	printf 'line1\nline2\nline3' > "$f/multi_nonl"
	printf '\n\nabc\n' > "$f/nl_start"
	printf 'a\n\nb\n\n\nc' > "$f/mix_empty"
	printf 'abc\n\n' > "$f/end_double_nl"
	printf '   \n\t\t\n \n' > "$f/spaces"
	printf 'caf\xc3\xa9 \xe2\x9c\x93\n\xf0\x9f\x98\x80 fin' > "$f/utf8"
	printf 'win\r\ndos\r\nfin' > "$f/crlf"
	rep 10000 a > "$f/long_nonl"
	{ rep 10000 a; printf '\n'; } > "$f/long_nl"
	{ printf 'x\n'; rep 10000 b; printf '\n'; printf 'y\n'; rep 12000 c; printf '\n'; } > "$f/long_mix"
	seq 1 300 > "$f/lines300"
	awk 'BEGIN{for(i=0;i<1000;i++)print "x"}' > "$f/many_short"
	{ rep 2000 m; printf '\n'; rep 1500 n; printf '\n\nfin'; } > "$f/mem_mix"
	head -c 20000 /dev/urandom > "$f/binary"
}

mkboundary() {
	local bs=$1 L
	for L in $((bs-1)) "$bs" $((bs+1)); do
		{ rep "$L" a; printf '\n'; rep "$L" b; printf '\n'; rep "$L" c; } > "$T/f/bd_${bs}_${L}_nonl"
		{ rep "$L" a; printf '\n'; rep "$L" b; printf '\n'; rep "$L" c; printf '\n'; } > "$T/f/bd_${bs}_${L}_nl"
	done
}

desc() {
	case "$1" in
		empty)         printf '%s' "fichier vide (0 octet) → NULL tout de suite" ;;
		nl)            printf '%s' "un seul '\\n'" ;;
		nl4)           printf '%s' "4 lignes vides consécutives ('\\n\\n\\n\\n')" ;;
		one_char)      printf '%s' "1 caractère sans '\\n'" ;;
		one_char_nl)   printf '%s' "1 caractère + '\\n'" ;;
		one_line_nonl) printf '%s' "1 ligne SANS '\\n' final" ;;
		one_line_nl)   printf '%s' "1 ligne avec '\\n' final" ;;
		multi_nl)      printf '%s' "3 lignes, '\\n' final" ;;
		multi_nonl)    printf '%s' "3 lignes, SANS '\\n' final" ;;
		nl_start)      printf '%s' "lignes vides au début ('\\n\\nabc\\n')" ;;
		mix_empty)     printf '%s' "lignes vides au milieu, pas de '\\n' final" ;;
		end_double_nl) printf '%s' "fin sur une ligne vide ('abc\\n\\n')" ;;
		spaces)        printf '%s' "espaces / tabulations seulement" ;;
		utf8)          printf '%s' "caractères UTF-8 (é ✓ 😀)" ;;
		crlf)          printf '%s' "fins de ligne Windows '\\r\\n'" ;;
		long_nl)       printf '%s' "ligne de 10 000 caractères + '\\n'" ;;
		long_nonl)     printf '%s' "ligne de 10 000 caractères sans '\\n'" ;;
		long_mix)      printf '%s' "lignes très courtes et très longues mélangées" ;;
		lines300)      printf '%s' "300 lignes (1..300)" ;;
		many_short)    printf '%s' "1 000 lignes d'1 caractère" ;;
		*)             printf '%s' "$1" ;;
	esac
}

FILES_BASE="empty nl nl4 one_char one_char_nl one_line_nonl one_line_nl multi_nl multi_nonl nl_start mix_empty end_double_nl spaces utf8 crlf long_nl long_nonl long_mix"
FILES_HEAVY="lines300 many_short"

# ───────────────────────────── compilation ──────────────────────────────────
build() {
	local bs=$1 out=$2 kind=$3 src f objs="" dflag="" log="$T/build.log"
	[ -n "$bs" ] && dflag="-D BUFFER_SIZE=$bs"
	if [ "$kind" = m ]; then src="$M_SRC"; else src="$B_SRC"; fi
	: > "$log"
	for f in $src; do
		cc -Wall -Wextra -Werror $dflag -I"$DIR" -c "$DIR/$f" -o "$T/o/$kind.${f%.c}.${bs:-none}.o" >> "$log" 2>&1 || return 1
		objs="$objs $T/o/$kind.${f%.c}.${bs:-none}.o"
	done
	cc $objs "$T/harness.o" -o "$out" >> "$log" 2>&1 || return 1
	return 0
}

build_mem() {
	local bs=$1 out=$2 kind=$3 src s="" f
	if [ "$kind" = m ]; then src="$M_SRC"; else src="$B_SRC"; fi
	for f in $src; do s="$s $DIR/$f"; done
	if [ "$MEM_TOOL" = valgrind ]; then
		cc -g -D BUFFER_SIZE="$bs" -I"$DIR" $s "$T/harness.c" -o "$out" >"$T/build.log" 2>&1
	else
		cc -g -fsanitize=address -fno-omit-frame-pointer -D BUFFER_SIZE="$bs" -I"$DIR" $s "$T/harness.c" -o "$out" >"$T/build.log" 2>&1
	fi
}

# ───────────────────────────── exécution d'un test ──────────────────────────
HINT=""
judge() {
	local label=$1 rc=$2 out=$3 msg=""
	case $rc in
		0)  ok "$label"; return ;;
		1)  msg=$out ;;
		2)  msg="Erreur du testeur (fichier de test illisible ?)${out:+ : $out}" ;;
		124) msg="${MSG124:-Pas terminé en ${TL:-10}s : boucle infinie, read bloquant ou algorithme trop lent (recopies quadratiques ?)}" ;;
		139|138|135) msg="Crash (segmentation fault / bus error) : accès mémoire invalide.$HINT" ;;
		134) msg="Crash (abort) : double free / corruption du tas ?" ;;
		136) msg="Crash (exception arithmétique) : division / modulo par 0 ?" ;;
		*)  msg="Code de sortie inattendu ($rc)${out:+ : $out}" ;;
	esac
	if [ "${AS_WARN:-0}" = 1 ]; then
		warn "$label" "$msg"$'\n'"(comportement indéfini / hors sujet : non bloquant)"
	elif [ "$rc" = 124 ] && [ "${SLOW:-0}" = 1 ]; then
		warn "$label" "$msg"$'\n'"(la moulinette a un timeout : à optimiser)"
	else
		ko "$label" "$msg"
	fi
}

run_case() {
	local label=$1 bin=$2 out rc
	shift 2
	{ out=$(tmo "${TL:-10}" "$bin" "$@" 2>&1 < "${STDIN_FILE:-/dev/null}"); rc=$?; } 2>/dev/null
	judge "$label" "$rc" "$out"
}

run_pipe() {
	local out rc
	{ out=$(cat "$3" | tmo "${TL:-10}" "$2" stdin "$3" 2>&1); rc=$?; } 2>/dev/null
	judge "$1" "$rc" "$out"
}

run_first() {
	[ -z "$TIMEOUT_BIN" ] && return
	local fifo="$T/fifo.$$" out rc wp
	rm -f "$fifo"; mkfifo "$fifo" 2>/dev/null || return
	( exec 3>"$fifo"; printf 'line1\nline2' >&3; exec sleep 8 ) &
	wp=$!
	{ out=$(tmo 3 "$2" first < "$fifo" 2>&1); rc=$?; } 2>/dev/null
	{ kill "$wp"; wait "$wp"; } 2>/dev/null
	rm -f "$fifo"
	MSG124="Bloqué : get_next_line attend la fin du fichier (EOF) alors qu'une ligne complète est déjà arrivée. Il faut s'arrêter de lire dès qu'un '\\n' est dans le buffer." \
		judge "$1" "$rc" "$out"
}

# ───────────────────────────── suite par BUFFER_SIZE ───────────────────────
suite_bs() {
	local kind=$1 bs=$2 bin="$T/bin/h_$1_$2" fx L
	HINT=""
	[ "$bs" -ge 1000000 ] && HINT=" Avec BUFFER_SIZE=$bs, un 'char buf[BUFFER_SIZE + 1]' sur la pile dépasse la limite (~8 Mo) : alloue le buffer avec malloc."
	if ! build "$bs" "$bin" "$kind"; then
		ko "compilation avec -Wall -Wextra -Werror -D BUFFER_SIZE=$bs" "$(cat "$T/build.log")"
		return
	fi
	ok "compile avec -Wall -Wextra -Werror -D BUFFER_SIZE=$bs"
	for fx in $FILES_BASE; do
		case "$fx" in long_*) SLOW=1 TL=20 run_case "$(desc "$fx")" "$bin" file "$T/f/$fx" ;;
			*) run_case "$(desc "$fx")" "$bin" file "$T/f/$fx" ;; esac
	done
	if [ "$bs" -le 10000 ]; then
		mkboundary "$bs"
		for L in $((bs-1)) "$bs" $((bs+1)); do
			run_case "3 lignes de $L car. (BUFFER_SIZE$(printf '%+d' $((L-bs)))), '\\n' final" "$bin" file "$T/f/bd_${bs}_${L}_nl"
			run_case "3 lignes de $L car. (BUFFER_SIZE$(printf '%+d' $((L-bs)))), sans '\\n' final" "$bin" file "$T/f/bd_${bs}_${L}_nonl"
		done
	fi
	for fx in $FILES_HEAVY; do SLOW=1 TL=20 run_case "$(desc "$fx")" "$bin" file "$T/f/$fx"; done
	run_case "2 fichiers lus l'un après l'autre (état réinitialisé en fin de fichier)" "$bin" seq "$T/f/multi_nonl" "$T/f/multi_nl" "$T/f/mix_empty"
	run_case "même fichier relu après avoir atteint EOF" "$bin" seq "$T/f/multi_nl" "$T/f/multi_nl"
	STDIN_FILE="$T/f/multi_nonl" run_case "entrée standard (stdin redirigée depuis un fichier)" "$bin" stdin "$T/f/multi_nonl"
	run_pipe "entrée standard via un pipe (cat fichier | programme)" "$bin" "$T/f/multi_nl"
	run_pipe "pipe avec 300 lignes" "$bin" "$T/f/lines300"
	run_case "/dev/null → NULL (un fd n'est pas forcément un fichier régulier)" "$bin" file /dev/null
	case "$bs" in 1|42|9999) run_first "s'arrête au 1er '\\n' (ne lit pas tout le fichier d'avance)" "$bin" ;; esac
}

suite_multi() {
	local bs bin F="$T/f"
	for bs in $BS_BONUS; do
		bin="$T/bin/h_b_$bs"
		[ -x "$bin" ] || continue
		HINT=""
		run_case "3 fd alternés (fd A,B,C,A,B,C...)" "$bin" multi 0 "$F/multi_nl" "$F/multi_nonl" "$F/mix_empty"
		run_case "3 fd de longueurs très différentes" "$bin" multi 0 "$F/lines300" "$F/long_mix" "$F/one_char"
		run_case "4 fd dont un vide et un avec lignes vides au début" "$bin" multi 0 "$F/empty" "$F/nl_start" "$F/multi_nl" "$F/utf8"
		run_case "ordre d'appel aléatoire (graine 3)" "$bin" multi 3 "$F/lines300" "$F/multi_nonl" "$F/mix_empty"
		run_case "ordre d'appel aléatoire (graine 11, 4 fd)" "$bin" multi 11 "$F/lines300" "$F/long_mix" "$F/crlf" "$F/nl4"
		run_case "ordre d'appel aléatoire (graine 29, 5 fd)" "$bin" multi 29 "$F/multi_nl" "$F/multi_nonl" "$F/lines300" "$F/end_double_nl" "$F/spaces"
		run_case "1 seul fd via multi (comportement mono-fd conservé)" "$bin" multi 0 "$F/lines300"
	done
}

# ───────────────────────────── analyse statique ────────────────────────────
norm_check() {
	if ! command -v norminette >/dev/null 2>&1; then
		warn "norminette introuvable : norme non vérifiée" "Une erreur de norme (même sur les bonus) = 0. Lance norminette à la main."
		return
	fi
	local out bad
	out=$(cd "$DIR" && norminette "$@" 2>&1)
	bad=$(printf '%s\n' "$out" | grep -E 'Error')
	if [ -z "$bad" ]; then ok "norminette : aucune erreur"
	else ko "norminette : erreurs de norme (= 0 à l'évaluation)" "$bad" 12; fi
}

static_checks() {
	local kind=$1 src f o all_forb="" all_glob="" all_fs="" nstat=0 names="" und="" def="" sym
	if [ "$kind" = m ]; then src="$M_SRC"; else src="$B_SRC"; fi
	for f in $src; do
		o="$T/o/$kind.${f%.c}.42.o"
		[ -f "$o" ] || return
		und="$und $(nm -u "$o" 2>/dev/null | awk '{print $NF}')"
		def="$def $(nm "$o" 2>/dev/null | awk 'NF==3 && $2 ~ /^[TtDdBbRrSsCcWwVv]$/ {print $3}')"
		sym=$(nm "$o" 2>/dev/null | awk '$2 ~ /^[BDCGS]$/ {print $3}' | tr '\n' ' ')
		[ -n "$sym" ] && all_glob="$all_glob $f → $sym;"
		sym=$(nm "$o" 2>/dev/null | awk '$2 ~ /^[bd]$/ && $3 !~ /\./ && $3 !~ /^(l_|L_|ltmp|\.L)/ {print $3}' | tr '\n' ' ')
		[ -n "$sym" ] && all_fs="$all_fs $f → $sym;"
		names="$names $(nm "$o" 2>/dev/null | awk '$2 ~ /^[bd]$/ && $3 !~ /^(l_|L_|ltmp|\.L)/ {print $3}' | tr '\n' ' ')"
	done
	if [ "$(uname)" = Darwin ]; then
		und=$(printf '%s\n' $und | sed 's/^_//'); def=$(printf '%s\n' $def | sed 's/^_//')
	fi
	for sym in $(printf '%s\n' $und | grep -v '^_' | sort -u); do
		case "$sym" in read|malloc|free) continue ;; esac
		printf '%s\n' $def | grep -qx "$sym" && continue
		all_forb="$all_forb $sym"
	done
	if [ -z "$all_forb" ]; then ok "seules fonctions externes utilisées : read, malloc, free"
	else ko "fonction(s) externe(s) interdite(s) utilisée(s) :$all_forb" "Autorisées : read, malloc, free."; fi
	if [ -z "$all_glob" ]; then ok "aucune variable globale"
	else ko "variable(s) globale(s) interdite(s)" "$all_glob"; fi
	if [ -n "$all_fs" ]; then
		warn "variable statique au niveau du fichier (c'est une globale déguisée)" "$all_fs"$'\n'"Mets-la DANS la fonction."
	fi
	if [ "$kind" = b ]; then
		nstat=$(printf '%s\n' $names | grep -c .)
		if [ "$nstat" -eq 1 ]; then ok "bonus : exactement 1 variable statique"
		else ko "bonus : $nstat variables statiques détectées (1 seule autorisée)" "Trouvées :$names"; fi
	fi
	if grep -qE '#[[:space:]]*include[[:space:]]*[<"][^>"]*libft' "$DIR"/*.c "$DIR"/*.h 2>/dev/null; then
		ko "libft incluse (interdit)"
	fi
}

header_checks() {
	local h="$DIR/$1"
	[ -f "$h" ] || return
	if tr '\n' ' ' < "$h" | grep -Eq 'char[[:space:]]*\*[[:space:]]*get_next_line[[:space:]]*\([[:space:]]*int'; then
		ok "$1 contient le prototype de get_next_line(int fd)"
	else ko "$1 : prototype 'char *get_next_line(int fd);' introuvable"; fi
	if grep -qE '#[[:space:]]*(ifndef|pragma[[:space:]]+once)' "$h"; then ok "$1 : protection contre la double inclusion"
	else warn "$1 : pas d'include guard"; fi
	if grep -Eq '#[[:space:]]*include[[:space:]]*"?<?libft' "$h"; then ko "$1 inclut libft (interdit)"; fi
}

# ───────────────────────────── README (Présence uniquement) ─────────────────
check_readme() {
	README="$DIR/README.md"
	if [ ! -f "$README" ]; then
		ko "README.md introuvable à la racine" "Le fichier doit s'appeler exactement README.md."
	else
		ok "README.md présent à la racine"
	fi
}

# ───────────────────────────── fichiers ────────────────────────────────────
check_files() {
	local f similar top
	for f in $1; do
		if [ -f "$DIR/$f" ]; then ok "$f présent à la racine"
		else
			similar=$(ls "$DIR" 2>/dev/null | grep -iE 'get.?next|gnl' | tr '\n' ' ')
			ko "$f introuvable à la racine" "Nom exact attendu${similar:+. Fichiers ressemblants : $similar}"
		fi
	done
	if [ "$2" = m ] && git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		top=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
		[ "$top" != "$DIR" ] && warn "le dossier testé n'est pas la racine du dépôt git" "Racine git : $top"
		if git -C "$DIR" ls-files 2>/dev/null | grep -qE '(\.o$|(^|/)a\.out$|\.DS_Store|\.dSYM)'; then
			warn "fichiers inutiles versionnés (.o, a.out, .DS_Store...)" "$(git -C "$DIR" ls-files | grep -E '(\.o$|(^|/)a\.out$|\.DS_Store|\.dSYM)' | head -n 5)"
		fi
	fi
}

# ───────────────────────────── mémoire ─────────────────────────────────────
mem_case() {
	local label=$1 len=$2 bin=$3 out rc lost reach inval where summary
	shift 3
	if [ "$MEM_TOOL" = valgrind ]; then
		{ out=$(tmo 120 valgrind --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$bin" "$@" 2>&1 < "${STDIN_FILE:-/dev/null}"); rc=$?; } 2>/dev/null
		[ "$rc" = 1 ] && { warn "$label" "le test fonctionnel échoue : mémoire non analysée"; return; }
		case "$rc" in 139|134|136|138|135) ko "$label" "Crash pendant l'analyse mémoire (code $rc)"; return ;; 124) warn "$label" "analyse mémoire trop lente (timeout)"; return ;; esac
		lost=$(printf '%s\n' "$out" | grep -E '(definitely|indirectly|possibly) lost: [1-9]' | sed 's/^==[0-9]*== *//')
		reach=$(printf '%s\n' "$out" | grep -E 'still reachable: [1-9]' | sed 's/^==[0-9]*== *//')
		inval=$(printf '%s\n' "$out" | grep -E 'Invalid (read|write|free)|Mismatched free|uninitialised value|Conditional jump' | sed 's/^==[0-9]*== *//' | sort | uniq -c | head -n 3)
		where=$(printf '%s\n' "$out" | grep -E '(at|by) 0x' | grep -E 'get_next_line|utils' | head -n 2 | sed 's/^==[0-9]*== *//')
		if [ -n "$inval" ]; then
			warn "$label : accès mémoire invalide" "$inval"$'\n'"$where"
		elif [ -n "$lost" ]; then
			warn "$label : FUITE MÉMOIRE" "$lost"$'\n'"Allocation : $where"
		elif [ -n "$reach" ] && [ "$len" = 0 ]; then
			warn "$label : mémoire non libérée en fin de fichier (still reachable)" "$reach"$'\n'"Allocation : $where"
		else
			ok "$label : aucune fuite / aucune erreur mémoire"
		fi
	else
		local leak=0; [ "$(uname)" = Linux ] && leak=1
		{ out=$(ASAN_OPTIONS=detect_leaks=$leak tmo 60 "$bin" "$@" 2>&1 < "${STDIN_FILE:-/dev/null}"); rc=$?; } 2>/dev/null
		[ "$rc" = 1 ] && { warn "$label" "le test fonctionnel échoue : mémoire non analysée"; return; }
		if printf '%s\n' "$out" | grep -qE 'ERROR: (Address|Leak)Sanitizer'; then
			summary=$(printf '%s\n' "$out" | grep -E 'SUMMARY|ERROR: (Address|Leak)Sanitizer' | head -n 3)
			where=$(printf '%s\n' "$out" | grep -E '#[0-9]+ .*(get_next_line|utils)' | head -n 3)
			warn "$label : problème mémoire (AddressSanitizer)" "$summary"$'\n'"$where"
		else
			ok "$label : aucune erreur mémoire"
		fi
	fi
}

mem_suite() {
	local kind=$1 bs bin F="$T/f"
	if [ "$MEM_TOOL" = none ]; then
		warn "ni valgrind ni AddressSanitizer disponibles : fuites mémoire non testées" "Installe valgrind pour tester les leaks."
		return
	fi
	for bs in 1 42 9999; do
		bin="$T/bin/mem_${kind}_$bs"
		if ! build_mem "$bs" "$bin" "$kind"; then warn "build mémoire BUFFER_SIZE=$bs échoué" "$(head -n 5 "$T/build.log")"; continue; fi
		mem_case "[BS=$bs] lecture complète de 6 fichiers" 0 "$bin" seq "$F/multi_nl" "$F/mix_empty" "$F/nl_start" "$F/empty" "$F/mem_mix" "$F/one_line_nonl"
		mem_case "[BS=$bs] lecture partielle (arrêt avant EOF)" 1 "$bin" partial "$F/mem_mix" 1
		STDIN_FILE="$F/multi_nonl" mem_case "[BS=$bs] stdin" 0 "$bin" stdin "$F/multi_nonl"
		mem_case "[BS=$bs] fd invalide / fermé / dossier" 0 "$bin" invalid "$F/multi_nl"
		if [ "$kind" = b ]; then
			mem_case "[BS=$bs] 3 fd en alternance" 0 "$bin" multi 0 "$F/multi_nl" "$F/mix_empty" "$F/mem_mix"
			mem_case "[BS=$bs] 3 fd, ordre aléatoire" 0 "$bin" multi 7 "$F/multi_nonl" "$F/mix_empty" "$F/mem_mix"
		fi
	done
}

# ───────────────────────────── git ──────────────────────────────────────────
git_check() {
	local g="git -C $DIR" dirty ahead up f untracked=""
	printf '\n%s━━━ GIT (informatif, non compté dans la note) ━━━%s\n' "$CYAN" "$RST"
	if ! command -v git >/dev/null 2>&1 || ! $g rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		printf '  %sATTENTION : ce dossier n'"'"'est pas un dépôt git → rien n'"'"'a été push.%s\n' "$YEL" "$RST"
		return
	fi
	for f in $M_FILES README.md; do
		$g ls-files --error-unmatch "$f" >/dev/null 2>&1 || { [ -f "$DIR/$f" ] && untracked="$untracked $f"; }
	done
	dirty=$($g status --porcelain 2>/dev/null | grep -v "^?? ${SCRIPT_NAME}$" | wc -l | tr -d ' ')
	up=$($g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
	if [ -z "$($g log -1 --format=%h 2>/dev/null)" ]; then
		printf '  %sATTENTION : aucun commit → git add / commit / push pas fait.%s\n' "$YEL" "$RST"
	elif [ -n "$untracked" ]; then
		printf '  %sATTENTION : fichiers non suivis par git (git add oublié ?) :%s%s\n' "$YEL" "$untracked" "$RST"
	elif [ "$dirty" -gt 0 ]; then
		printf '  %sATTENTION : %s fichier(s) modifié(s) non commit → git add / commit / push pas à jour.%s\n' "$YEL" "$dirty" "$RST"
	elif [ -z "$up" ]; then
		printf '  %sATTENTION : aucune branche distante configurée → git push pas fait.%s\n' "$YEL" "$RST"
	else
		ahead=$($g rev-list --count "$up..HEAD" 2>/dev/null)
		if [ "${ahead:-0}" -gt 0 ]; then
			printf '  %sATTENTION : %s commit(s) pas encore push vers %s → git push pas fait.%s\n' "$YEL" "$ahead" "$up" "$RST"
		else
			printf '  %s✔ git : tout est commit et push (%s à jour).%s\n' "$GREEN" "$up" "$RST"
		fi
	fi
}

# ============================================================================
#                                   MAIN
# ============================================================================
header() {
	printf '%s' "$CYAN"
	cat <<'HDR' | sed "s/42_gnl_tester/${BOLD}42_gnl_tester${RST}${CYAN}/"
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                                                         :::      ::::::::    ║
║    42_gnl_tester                                      :+:      :+:    :+:    ║
║                                                     +:+ +:+         +:+      ║
║    By: enviale <enviale@student.42.fr>            +#+  +:+       +#+         ║
║                                                 +#+#+#+#+#+   +#+            ║
║    Created: 2026/11/10 12:00:00 by enviale           #+#    #+#              ║
║    Updated: 2026/11/10 12:35:27 by enviale          ###   ########.fr        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
HDR
	printf '%s' "$RST"
}
header
disclaimer() {
	printf '%s' "$GRAY"
	cat <<'TXT'
  ⚠ Un testeur n'est jamais parfait : écris aussi tes propres tests et compare avec tes
    camarades (peer-to-peer). Un « tout OK » ici ne garantit pas la note.
TXT
	printf '%s' "$RST"
}
disclaimer
printf '%sProjet testé : %s%s\n' "$GRAY" "$DIR" "$RST"
printf '%sOutils : cc ✔ | mémoire : %s | norminette : %s | timeout : %s%s\n' "$GRAY" "$MEM_TOOL" \
	"$(command -v norminette >/dev/null 2>&1 && echo oui || echo non)" "$([ -n "$TIMEOUT_BIN" ] && echo oui || echo non)" "$RST"
mkfixtures

# ───── 1. Fichiers obligatoires ─────
title "1. PARTIE OBLIGATOIRE : fichiers & noms"
check_files "$M_FILES" m
MISSING=0
for f in $M_SRC; do [ -f "$DIR/$f" ] || MISSING=1; done

title "2. README (obligatoire)"
check_readme

title "3. Analyse statique (header, norme, fonctions autorisées, globales)"
header_checks get_next_line.h
EXISTING=""
for f in $M_FILES; do [ -f "$DIR/$f" ] && EXISTING="$EXISTING $f"; done
[ -n "$EXISTING" ] && norm_check $EXISTING

title "4. Compilation"
if [ "$MISSING" -eq 1 ]; then
	ko "fichiers .c manquants : compilation et tests impossibles"
else
	build "" "$T/bin/h_m_none" m || ko "ne compile pas sans -D BUFFER_SIZE" "$(head -n 8 "$T/build.log")"
	if build 42 "$T/bin/h_m_42" m; then
		static_checks m
	else
		ko "compilation -Wall -Wextra -Werror -D BUFFER_SIZE=42" "$(head -n 10 "$T/build.log")"
	fi

	title "5. Tests fonctionnels (obligatoire)"
	for bs in $BS_LIST; do suite_bs m "$bs"; done
	if [ -x "$T/bin/h_m_none" ]; then
		HINT=""
		run_case "lecture correcte avec la valeur par défaut" "$T/bin/h_m_none" file "$T/f/multi_nonl"
	fi

	title "6. Cas limites (obligatoire)"
	HINT=""
	B42="$T/bin/h_m_42"
	if [ -x "$B42" ]; then
		run_case "fd = -1 → NULL" "$B42" badfd
		run_case "fd fermé → NULL" "$B42" closed "$T/f/multi_nl"
		run_case "fd d'un dossier (read échoue) → NULL" "$B42" dir
		AS_WARN=1 run_case "fd = 9999 non ouvert → NULL (pas de crash, tableau de fd trop petit ?)" "$B42" bigfd
		AS_WARN=1 run_case "fichier binaire BUFFER_SIZE=42 (indéfini, ne doit pas boucler/crasher)" "$B42" drain "$T/f/binary"
		[ -x "$T/bin/h_m_1" ] && AS_WARN=1 run_case "fichier binaire BUFFER_SIZE=1" "$T/bin/h_m_1" drain "$T/f/binary"
	fi
	if build 0 "$T/bin/h_m_0" m; then
		AS_WARN=1 TL=5 run_case "BUFFER_SIZE=0 : ne doit ni boucler ni crasher" "$T/bin/h_m_0" drain "$T/f/multi_nl"
	fi

	title "7. Mémoire (obligatoire)"
	mem_suite m
fi
M_OK=$C_OK; M_KO=$C_KO; M_WARN=$C_WARN
C_OK=0; C_KO=0; C_WARN=0

# ───── Bonus ─────
BONUS_PRESENT=0
for f in $B_FILES; do [ -e "$DIR/$f" ] && BONUS_PRESENT=1; done
if [ "$BONUS_PRESENT" -eq 0 ]; then
	title "BONUS"
	printf '  %s⏭  Aucun fichier bonus détecté (*_bonus.c / *_bonus.h) : bonus ignorés.%s\n' "$GRAY" "$RST"
else
	title "B1. BONUS : fichiers & noms"
	check_files "$B_FILES" b
	BMISSING=0
	for f in $B_SRC; do [ -f "$DIR/$f" ] || BMISSING=1; done
	header_checks get_next_line_bonus.h
	EXISTING=""
	for f in $B_FILES; do [ -f "$DIR/$f" ] && EXISTING="$EXISTING $f"; done
	[ -n "$EXISTING" ] && norm_check $EXISTING
	if [ "$BMISSING" -eq 1 ]; then
		ko "bonus incomplet : tests impossibles"
	else
		title "B2. BONUS : compilation & analyse"
		if build 42 "$T/bin/h_b_42" b; then
			static_checks b
		else
			ko "compilation bonus BUFFER_SIZE=42" "$(head -n 10 "$T/build.log")"
		fi
		build "" "$T/bin/h_b_none" b || ko "bonus : ne compile pas sans -D BUFFER_SIZE" "$(head -n 6 "$T/build.log")"

		title "B3. BONUS : tests fonctionnels (mono-fd)"
		for bs in $BS_BONUS; do suite_bs b "$bs"; done

		title "B4. BONUS : plusieurs fd en même temps"
		suite_multi

		title "B5. BONUS : mémoire"
		mem_suite b
	fi
fi
B_OK=$C_OK; B_KO=$C_KO; B_WARN=$C_WARN

# ───── Git ─────
git_check

# ───── Résumé ─────
printf '\n%s══════════════════════ RÉSULTAT ══════════════════════%s\n' "$CYAN" "$RST"
printf 'Partie obligatoire : %s%s OK%s, %s%s KO%s, %s%s warning(s)%s\n' "$GREEN" "$M_OK" "$RST" "$RED" "$M_KO" "$RST" "$GRAY" "$M_WARN" "$RST"
if [ "$M_KO" -eq 0 ]; then
	printf '%s✔ Les tests de la partie obligatoire sont tous passés.%s\n' "$GREEN" "$RST"
	[ "$M_WARN" -gt 0 ] && printf '%s  (%s warning(s) à regarder avant de rendre)%s\n' "$GRAY" "$M_WARN" "$RST"
else
	printf '%s✘ Partie obligatoire : %s test(s) en échec, corrige les KO ci-dessus.%s\n' "$RED" "$M_KO" "$RST"
fi
if [ "$BONUS_PRESENT" -eq 0 ]; then
	printf '%s⏭ Bonus : non rendus, ignorés.%s\n' "$GRAY" "$RST"
else
	printf 'Bonus : %s%s OK%s, %s%s KO%s, %s%s warning(s)%s\n' "$GREEN" "$B_OK" "$RST" "$RED" "$B_KO" "$RST" "$GRAY" "$B_WARN" "$RST"
	if [ "$B_KO" -eq 0 ]; then
		printf '%s✔ Les tests du/des bonus sont tous passés.%s\n' "$GREEN" "$RST"
		[ "$B_WARN" -gt 0 ] && printf '%s  (%s warning(s) à regarder)%s\n' "$GRAY" "$B_WARN" "$RST"
	else
		printf '%s✘ Bonus : %s test(s) en échec.%s\n' "$RED" "$B_KO" "$RST"
	fi
	[ "$M_KO" -gt 0 ] && printf '%sRappel : le bonus n'"'"'est évalué que si la partie obligatoire est parfaite.%s\n' "$GRAY" "$RST"
fi
printf '\n'
[ "$M_KO" -eq 0 ] && [ "$B_KO" -eq 0 ] && exit 0
exit 1