#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                              ║
# ║                                                         :::      ::::::::    ║
# ║    42_printf_tester                                   :+:      :+:    :+:    ║
# ║                                                     +:+ +:+         +:+      ║
# ║    By: enviale <enviale@student.42.fr>            +#+  +:+       +#+         ║
# ║                                                 +#+#+#+#+#+   +#+            ║
# ║    Created: 2026/11/12 12:00:00 by enviale           #+#    #+#              ║
# ║    Updated: 2026/11/12 12:25:36 by enviale          ###   ########.fr        ║
# ║                                                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Usage (depuis le dossier du projet) :
#      bash 42_printf_tester.sh
#      bash ../42_printf_tester.sh
#      bash 42_printf_tester.sh -q
#      bash 42_printf_tester.sh /chemin/vers/projet
#
# [ OK ]  vert    : vérification réussie
# [ KO ]  rouge   : vérification ratée (détails affichés en gris)
# [WARN]  jaune   : outil facultatif absent / point à vérifier
# [SKIP]         : test non exécuté (prérequis manquant)
#
# Les parties obligatoire et bonus sont testées séparément.
# Les fichiers .o créés par les tests sont supprimés à la fin.

QUIET=0
DIR=""
for arg in "$@"; do
	case "$arg" in
		-q|--quiet) QUIET=1 ;;
		-h|--help)
			sed -n '/^# Usage/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*) DIR="$arg" ;;
	esac
done
[ -n "$DIR" ] || DIR="$PWD"
DIR=$(cd "$DIR" 2>/dev/null && pwd) || {
	printf 'Dossier introuvable : %s\n' "$DIR"
	exit 1
}
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")

# ───────────────────────────── couleurs ─────────────────────────────────────
GREEN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRAY=$'\033[90m'
CYAN=$'\033[36m'; PURPLE=$'\033[35m'; BOLD=$'\033[1m'; RST=$'\033[0m'

C_OK=0; C_KO=0; C_WARN=0; C_SKIP=0
M_OK=0; M_KO=0; M_WARN=0; M_SKIP=0
B_OK=0; B_KO=0; B_WARN=0; B_SKIP=0
BONUS_PRESENT=0

ok()
{
	C_OK=$((C_OK + 1))
	[ "$QUIET" -eq 1 ] || printf '  %s[ OK ]%s %s\n' "$GREEN" "$RST" "$1"
}

ko()
{
	C_KO=$((C_KO + 1))
	printf '  %s[ KO ]%s %s\n' "$RED" "$RST" "$1"
	if [ -n "${2:-}" ]; then
		printf '%s\n' "$2" | head -n "${3:-10}" | while IFS= read -r line; do
			printf '         %s↳ %s%s\n' "$GRAY" "$line" "$RST"
		done
	fi
}

warn()
{
	C_WARN=$((C_WARN + 1))
	printf '  %s[WARN]%s %s\n' "$YEL" "$RST" "$1"
	if [ -n "${2:-}" ]; then
		printf '%s\n' "$2" | head -n "${3:-10}" | while IFS= read -r line; do
			printf '         %s↳ %s%s\n' "$GRAY" "$line" "$RST"
		done
	fi
}

skip()
{
	C_SKIP=$((C_SKIP + 1))
	[ "$QUIET" -eq 1 ] || printf '  %s[SKIP]%s %s\n' "$PURPLE" "$RST" "$1"
}

title()
{
	printf '\n%s━━━ %s ━━━%s\n' "$CYAN" "$1" "$RST"
}

header()
{
	printf '%s' "$CYAN"
	cat <<'HDR' | sed "s/42_printf_tester/${BOLD}42_printf_tester${RST}${CYAN}/"
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                                                         :::      ::::::::    ║
║    42_printf_tester                                   :+:      :+:    :+:    ║
║                                                     +:+ +:+         +:+      ║
║    By: enviale <enviale@student.42.fr>            +#+  +:+       +#+         ║
║                                                 +#+#+#+#+#+   +#+            ║
║    Created: 2026/11/12 12:00:00 by enviale           #+#    #+#              ║
║    Updated: 2026/11/12 12:25:36 by enviale          ###   ########.fr        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
HDR
	printf '%s' "$RST"
}
header
printf '%s' "$GRAY"
cat <<'TXT'
  ⚠ Un testeur n'est jamais parfait : écris aussi tes propres tests et compare avec tes
    camarades (peer-to-peer). Un « tout OK » ici ne garantit pas la note.
TXT
printf '%s' "$RST"
printf '%sProjet testé : %s%s\n' "$GRAY" "$DIR" "$RST"

command -v cc >/dev/null 2>&1 || {
	printf 'cc introuvable : impossible de compiler.\n'
	exit 1
}
command -v make >/dev/null 2>&1 || {
	printf 'make introuvable : impossible de tester le Makefile.\n'
	exit 1
}

T=$(mktemp -d 2>/dev/null || mktemp -d -t printf-test)
LIB="$DIR/libftprintf.a"
LIB_WAS_PRESENT=0
if [ -f "$LIB" ]; then
	LIB_WAS_PRESENT=1
	cp "$LIB" "$T/libftprintf.a.saved" || {
		rm -rf "$T"
		printf 'Impossible de sauvegarder %s\n' "$LIB"
		exit 1
	}
fi

git_check()
{
	local dirty ahead up f untracked="" top tester_rel="" status_lines git_warn=0

	printf '\n%s━━━ GIT (informatif) ━━━%s\n' "$CYAN" "$RST"
	if ! command -v git >/dev/null 2>&1 \
		|| ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		printf '  %sATTENTION : ce dossier n’est pas un dépôt git → rien n’a été push.%s\n' "$YEL" "$RST"
		M_WARN=$((M_WARN + 1))
		return
	fi
	top=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
	case "$SCRIPT_PATH" in
		"$top"/*) tester_rel=${SCRIPT_PATH#"$top"/} ;;
	esac
	for f in Makefile README.md ft_printf.h ft_printf.c; do
		[ -f "$DIR/$f" ] || continue
		git -C "$DIR" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
			|| untracked="$untracked $f"
	done
	status_lines=$(git -C "$DIR" status --porcelain --untracked-files=all 2>/dev/null |
		awk -v path="$tester_rel" 'substr($0, 4) != path')
	dirty=$(printf '%s\n' "$status_lines" | awk 'NF { n++ } END { print n + 0 }')
	up=$(git -C "$DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
	if [ -z "$(git -C "$DIR" log -1 --format=%h 2>/dev/null)" ]; then
		git_warn=1
		printf '  %sATTENTION : aucun commit → git add / commit / push pas fait.%s\n' "$YEL" "$RST"
	elif [ -n "$untracked" ]; then
		git_warn=1
		printf '  %sATTENTION : fichiers non suivis par git (git add oublié ?) :%s%s\n' "$YEL" "$untracked" "$RST"
	elif [ "$dirty" -gt 0 ]; then
		git_warn=1
		printf '  %sATTENTION : %s fichier(s) modifié(s) non commit → git add / commit / push pas à jour.%s\n' "$YEL" "$dirty" "$RST"
	elif [ -z "$up" ]; then
		git_warn=1
		printf '  %sATTENTION : aucune branche distante configurée → git push pas fait.%s\n' "$YEL" "$RST"
	else
		ahead=$(git -C "$DIR" rev-list --count "$up..HEAD" 2>/dev/null)
		if [ "${ahead:-0}" -gt 0 ]; then
			git_warn=1
			printf '  %sATTENTION : %s commit(s) pas encore push vers %s → git push pas fait.%s\n' "$YEL" "$ahead" "$up" "$RST"
		else
			printf '  %s✔ git : tout est commit et push (%s à jour, d’après la dernière info distante connue).%s\n' "$GREEN" "$up" "$RST"
		fi
	fi
	[ "$git_warn" -eq 1 ] && M_WARN=$((M_WARN + 1))
}

cleanup()
{
	make -s -C "$DIR" clean >/dev/null 2>&1 || true
	find "$DIR" -type f -name '*.o' -not -path "$DIR/.git/*" -delete
	if [ "$LIB_WAS_PRESENT" -eq 1 ]; then
		cp "$T/libftprintf.a.saved" "$LIB"
	else
		rm -f "$LIB"
	fi
	rm -rf "$T"
	git_check
	printf '\n%s══════════════════════ RÉSULTAT ══════════════════════%s\n' "$GRAY" "$RST"
	printf '%sPartie obligatoire : %s%s OK%s, %s%s KO%s, %s%s warning(s)%s, %s%s ignorée(s)%s\n' \
		"$GRAY" "$GREEN" "$M_OK" "$GRAY" "$RED" "$M_KO" "$GRAY" "$YEL" "$M_WARN" "$GRAY" "$PURPLE" "$M_SKIP" "$GRAY"
	if [ "$M_KO" -eq 0 ]; then
		printf '%s✔ Les vérifications obligatoires exécutées sont passées.%s\n' "$GREEN" "$RST"
	else
		printf '%s✘ %s vérification(s) en échec : consulte les KO ci-dessus.%s\n' \
			"$RED" "$M_KO" "$GRAY"
	fi
	if [ "$BONUS_PRESENT" -eq 0 ]; then
		printf '%s⏭ Bonus : aucun fichier *_bonus.c / *_bonus.h détecté, bonus ignorés.%s\n' \
			"$GRAY" "$GRAY"
		printf '%sBonus : %s%s ignorée(s).%s\n' \
			"$GRAY" "$PURPLE" "$B_SKIP" "$GRAY"
	else
		printf '%sBonus : %s%s OK%s, %s%s KO%s, %s%s warning(s)%s, %s%s ignorée(s)%s\n' \
			"$GRAY" "$GREEN" "$B_OK" "$GRAY" "$RED" "$B_KO" "$GRAY" "$YEL" "$B_WARN" "$GRAY" "$PURPLE" "$B_SKIP" "$GRAY"
		if [ "$M_KO" -gt 0 ]; then
			printf '%sRappel : le bonus ne sera évalué que si le mandatory est parfait.%s\n' \
				"$GRAY" "$GRAY"
		elif [ "$B_KO" -eq 0 ]; then
			printf '%s✔ Les tests bonus sont passés.%s\n' "$GREEN" "$RST"
		else
			printf '%s✘ %s test(s) bonus en échec.%s\n' "$RED" "$B_KO" "$GRAY"
		fi
	fi
	if [ "$libft_present" -eq 1 ]; then
		printf '%sRappel : la libft est autorisée, mais ce testeur ne la vérifie pas. Assure-toi qu’elle est correcte.%s\n' \
			"$GRAY" "$GRAY"
	fi
	printf '%sNettoyage : tous les fichiers .o du projet ont été supprimés.%s\n\n' \
		"$GRAY" "$GRAY"
	printf '%sRappel : ce testeur ne remplace pas l’évaluation du sujet.%s\n\n' "$GRAY" "$GRAY"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

has_objects()
{
	find "$DIR" -type f -name '*.o' -not -path "$DIR/.git/*" \
		-print -quit | grep -q .
}

run_make()
{
	local label=$1
	shift

	if make -C "$DIR" "$@" >"$T/make.log" 2>&1; then
		ok "$label"
		return 0
	fi
	ko "$label" "$(cat "$T/make.log")"
	return 1
}

title "1. Fichiers obligatoires"
for file in Makefile ft_printf.h ft_printf.c README.md; do
	if [ -f "$DIR/$file" ]; then
		ok "$file présent"
	else
		ko "$file manquant"
	fi
done
if find "$DIR" -type f -name '*.c' -not -path "$DIR/.git/*" -print -quit | grep -q .; then
	ok "fichiers source C présents"
else
	ko "aucun fichier source C trouvé"
fi
extra_files=""
libft_present=0
while IFS= read -r -d '' path; do
	[[ "$path" == "$SCRIPT_PATH" ]] && continue
	relative=${path#"$DIR"/}
	case "$relative" in
		.git/*|libftprintf.a)
			continue
			;;
		libft/*|libft.a)
			libft_present=1
			continue
			;;
		Makefile|README.md|*.c|*.h)
			if [[ "$relative" == */* ]] \
				&& [[ ! "$relative" =~ ^[^/]+/[^/]+\.(c|h)$ ]]; then
				extra_files+="${relative}"$'\n'
			fi
			;;
		*)
			extra_files+="${relative}"$'\n'
			;;
	esac
done < <(find "$DIR" -type f -not -path "$DIR/.git/*" -print0)
if [ -n "$extra_files" ]; then
	warn "fichiers hors des formats autorisés par le sujet" \
		"Autorisés : Makefile, README.md, *.h, */*.h, *.c et */*.c."$'\n'"Hors périmètre : ${extra_files%$'\n'}"
else
	ok "aucun fichier hors des formats autorisés (testeur courant exclu)"
fi

title "2. Vérification du prototype"
if [ -f "$DIR/ft_printf.h" ] \
	&& grep -qE 'int[[:space:]]+ft_printf[[:space:]]*\([[:space:]]*const[[:space:]]+char[[:space:]]*\*' "$DIR/ft_printf.h"; then
	ok "prototype int ft_printf(const char *, ...) dans ft_printf.h"
else
	ko "prototype ft_printf manquant ou incorrect dans ft_printf.h"
fi

title "3. Makefile : règles et exigences"
if [ ! -f "$DIR/Makefile" ]; then
	ko "Makefile manquant"
	skip "contenu et règles Makefile"
else
missing_rules=""
for rule in all clean fclean re; do
	grep -qE "^${rule}[[:space:]]*:" "$DIR/Makefile" \
		|| missing_rules="$missing_rules $rule"
done
if [ -z "$missing_rules" ]; then
	ok "règles all, clean, fclean et re présentes"
else
	ko "règles Makefile manquantes :$missing_rules"
fi
if grep -qE '^[[:space:]]*NAME[[:space:]]*[:?+]?=[[:space:]]*libftprintf\.a([[:space:]]|$)' "$DIR/Makefile"; then
	ok "NAME produit libftprintf.a"
else
	ko "NAME doit désigner libftprintf.a"
fi
if grep -qw 'ar' "$DIR/Makefile" && ! grep -qw 'libtool' "$DIR/Makefile"; then
	ok "la bibliothèque est créée avec ar (pas libtool)"
else
	ko "utiliser ar pour créer libftprintf.a, pas libtool"
fi
if grep -q -- '-Wall' "$DIR/Makefile" \
	&& grep -q -- '-Wextra' "$DIR/Makefile" \
	&& grep -q -- '-Werror' "$DIR/Makefile"; then
	ok "compilation avec -Wall -Wextra -Werror"
else
	ko "flags de compilation recommandés absents (-Wall -Wextra -Werror)"
fi
fi

title "4. Vérification des cibles Makefile"
if [ ! -f "$DIR/Makefile" ]; then
	skip "cibles Makefile (Makefile absent)"
else
run_make "make fclean s'exécute" fclean
if [ ! -e "$LIB" ] && ! has_objects; then
	ok "fclean supprime la bibliothèque et les objets"
else
	ko "fclean doit supprimer libftprintf.a et les .o"
fi

run_make "la cible par défaut make s'exécute"
if [ -f "$LIB" ] && has_objects; then
	ok "make crée la bibliothèque et les objets"
else
	ko "make doit créer libftprintf.a et les .o"
fi
if [ -f "$LIB" ]; then
	run_make "make est réexécutable"
else
	skip "make réexécutable (construction initiale échouée)"
fi

run_make "make clean s'exécute" clean
if [ -f "$LIB" ] && ! has_objects; then
	ok "clean supprime les .o et conserve la bibliothèque"
else
	ko "clean doit supprimer les .o sans supprimer libftprintf.a"
	exit 1
fi

run_make "make re s'exécute" re
if [ -f "$LIB" ] && has_objects; then
	ok "reconstruit la bibliothèque et les objets"
else
	ko "re doit reconstruire libftprintf.a et les .o"
fi
run_make "make fclean s'exécute à nouveau" fclean
if [ ! -e "$LIB" ] && ! has_objects; then
	ok "fclean final supprime la bibliothèque et les objets"
else
	ko "fclean final doit supprimer libftprintf.a et les .o"
	exit 1
fi
run_make "make reconstruit la bibliothèque pour les tests"
if [ ! -f "$LIB" ]; then
	ko "libftprintf.a est nécessaire pour tester les conversions"
fi
fi

title "5. Analyse statique"
if [ ! -f "$LIB" ]; then
	skip "analyse statique (libftprintf.a indisponible)"
elif command -v nm >/dev/null 2>&1; then
	if nm --defined-only "$LIB" 2>/dev/null \
		| grep -qE '[[:space:]]T[[:space:]]+ft_printf$'; then
		ok "ft_printf défini dans libftprintf.a"
	else
		ko "ft_printf absent de libftprintf.a"
	fi
	undefined=$(nm -u "$LIB" 2>/dev/null \
		| awk 'NF == 2 && $1 == "U" {print $2}' \
		| sed 's/@.*//' | sort -u)
	defined=$(nm --defined-only "$LIB" 2>/dev/null \
		| awk 'NF == 3 {print $3}' | sort -u)
	forbidden=$(comm -23 <(printf '%s\n' "$undefined") <(printf '%s\n' "$defined") \
		| grep -vxE 'malloc|free|write|_GLOBAL_OFFSET_TABLE_|__stack_chk_fail|__stack_chk_guard' \
		| tr '\n' ' ')
	if [ -z "$forbidden" ]; then
		ok "fonctions externes conformes au sujet"
	else
		ko "fonctions externes interdites : $forbidden"
	fi
	globals=$(nm "$LIB" 2>/dev/null \
		| awk '$2 ~ /^[BCDGS]$/ {print $3}' | sort -u | tr '\n' ' ')
	if [ -z "$globals" ]; then
		ok "aucune variable globale"
	else
		ko "variables globales trouvées : $globals"
	fi
else
	warn "nm non installée : symboles externes et globaux non vérifiés"
fi
if ! find "$DIR" -type f -name '*.c' -not -path "$DIR/.git/*" \
	-print -quit | grep -q .; then
	skip "norminette (aucun fichier source C)"
elif command -v norminette >/dev/null 2>&1; then
	norm_errors=$(cd "$DIR" && norminette 2>&1 | grep -E ': Error!' | head -n 8)
	if [ -z "$norm_errors" ]; then
		ok "norminette"
	else
		ko "erreurs norminette" "$norm_errors"
	fi
else
	warn "norminette non installée : conformité de style non vérifiée"
fi

title "6. Compilation du harnais"
cat >"$T/harness.c" <<'EOF'
#include "ft_printf.h"
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int	g_pointer_value;

static int	call_printf(const char *format, ...)
{
	va_list	args;
	int		result;

	va_start(args, format);
	result = vprintf(format, args);
	va_end(args);
	return (result);
}

static int	invoke(int use_ft, int test)
{
	if (test == 0)
		return (use_ft ? ft_printf("texte sans conversion\n")
			: printf("texte sans conversion\n"));
	if (test == 1)
		return (use_ft ? ft_printf("char:[%c]\n", 'Q')
			: printf("char:[%c]\n", 'Q'));
	if (test == 2)
		return (use_ft ? ft_printf("nul:A%cB", '\0')
			: printf("nul:A%cB", '\0'));
	if (test == 3)
		return (use_ft ? ft_printf("str:[%s]\n", "42 printf")
			: printf("str:[%s]\n", "42 printf"));
	if (test == 4)
		return (use_ft ? ft_printf("empty:[%s]\n", "")
			: printf("empty:[%s]\n", ""));
	if (test == 5)
		return (use_ft ? ft_printf("percent:%% end\n")
			: printf("percent:%% end\n"));
	if (test == 6)
		return (use_ft ? ft_printf("d:%d|%d|%d|%d", INT_MIN, INT_MAX,
				-42, 0)
			: printf("d:%d|%d|%d|%d", INT_MIN, INT_MAX, -42, 0));
	if (test == 7)
		return (use_ft ? ft_printf("i:%i|%i|%i", -2147483647 - 1, 42, 0)
			: printf("i:%i|%i|%i", -2147483647 - 1, 42, 0));
	if (test == 8)
		return (use_ft ? ft_printf("u:%u|%u", 0u, UINT_MAX)
			: printf("u:%u|%u", 0u, UINT_MAX));
	if (test == 9)
		return (use_ft ? ft_printf("x:%x|%x|%x", 0u, 42u, UINT_MAX)
			: printf("x:%x|%x|%x", 0u, 42u, UINT_MAX));
	if (test == 10)
		return (use_ft ? ft_printf("X:%X|%X|%X", 0u, 42u, UINT_MAX)
			: printf("X:%X|%X|%X", 0u, 42u, UINT_MAX));
	if (test == 11)
		return (use_ft ? ft_printf("p:%p", (void *)&g_pointer_value)
			: printf("p:%p", (void *)&g_pointer_value));
	if (test == 12)
		return (use_ft ? ft_printf("p:%p", (void *)NULL)
			: printf("p:%p", (void *)NULL));
	if (test == 13)
		return (use_ft
			? ft_printf("mix:%c|%s|%d|%i|%u|%x|%X|%p|%%\n", 'A',
				"ok", -42, 42, UINT_MAX, 42u, 42u, (void *)&g_pointer_value)
			: printf("mix:%c|%s|%d|%i|%u|%x|%X|%p|%%\n", 'A',
				"ok", -42, 42, UINT_MAX, 42u, 42u, (void *)&g_pointer_value));
	if (test == 14)
		return (use_ft ? ft_printf("str:%s|%s|%s", "hello", "", (char *)NULL)
			: printf("str:%s|%s|%s", "hello", "", (char *)NULL));
	if (test == 15)
		return (use_ft ? ft_printf("char:%c|%c|%c|%c", '\0', '\n', '\t', 'A')
			: printf("char:%c|%c|%c|%c", '\0', '\n', '\t', 'A'));
	if (test == 16)
		return (use_ft ? ft_printf("d:%d|%d|%d|%d", INT_MIN, INT_MAX, -1, 0)
			: printf("d:%d|%d|%d|%d", INT_MIN, INT_MAX, -1, 0));
	if (test == 17)
		return (use_ft ? ft_printf("i:%i|%i|%i|%i", INT_MIN, INT_MAX, -1, 0)
			: printf("i:%i|%i|%i|%i", INT_MIN, INT_MAX, -1, 0));
	if (test == 18)
		return (use_ft ? ft_printf("u:%u|%u|%u|%u", 0u, 42u, 2147483648u,
				UINT_MAX)
			: printf("u:%u|%u|%u|%u", 0u, 42u, 2147483648u, UINT_MAX));
	if (test == 19)
		return (use_ft ? ft_printf("x:%x|%x|%x|%x", 0u, 15u, 16u, UINT_MAX)
			: printf("x:%x|%x|%x|%x", 0u, 15u, 16u, UINT_MAX));
	if (test == 20)
		return (use_ft ? ft_printf("X:%X|%X|%X|%X", 0u, 15u, 16u, UINT_MAX)
			: printf("X:%X|%X|%X|%X", 0u, 15u, 16u, UINT_MAX));
	if (test == 21)
		return (use_ft ? ft_printf("p:%p|%p|%p", (void *)NULL,
				(void *)&g_pointer_value, (void *)0x1234)
			: printf("p:%p|%p|%p", (void *)NULL,
				(void *)&g_pointer_value, (void *)0x1234));
	if (test == 22)
		return (use_ft ? ft_printf("")
			: printf(""));
	if (test == 23)
		return (use_ft ? ft_printf("c:[%10c]|[%-10c]|[%-010c]", 'Q', 'Z', 'R')
			: call_printf("c:[%10c]|[%-10c]|[%-010c]", 'Q', 'Z', 'R'));
	if (test == 24)
		return (use_ft ? ft_printf("s:[%10s]|[%-10.3s]|[%010s]|[%-010.3s]",
				"hello", "world", "text", "printf")
			: call_printf("s:[%10s]|[%-10.3s]|[%010s]|[%-010.3s]",
				"hello", "world", "text", "printf"));
	if (test == 25)
		return (use_ft ? ft_printf("p:[%20p]|[%-20p]|[%020p]|[%-020p]",
				(void *)&g_pointer_value, (void *)&g_pointer_value,
				(void *)&g_pointer_value, (void *)&g_pointer_value)
			: call_printf("p:[%20p]|[%-20p]|[%020p]|[%-020p]",
				(void *)&g_pointer_value, (void *)&g_pointer_value,
				(void *)&g_pointer_value, (void *)&g_pointer_value));
	if (test == 26)
		return (use_ft ? ft_printf("d:[%10d]|[%-10d]|[%010d]|[%.5d]|"
				"[%10.5d]|[%-10.5d]|[%-010.5d]|[%+010.5d]|[% 010.5d]",
				-42, 42, 42, 42, 42, 42, -42, 42, 42)
			: call_printf("d:[%10d]|[%-10d]|[%010d]|[%.5d]|"
				"[%10.5d]|[%-10.5d]|[%-010.5d]|[%+010.5d]|[% 010.5d]",
				-42, 42, 42, 42, 42, 42, -42, 42, 42));
	if (test == 27)
		return (use_ft ? ft_printf("i:[%+10i]|[% 10i]|[%+010i]|"
				"[% 010i]|[%-+10i]|[%- 10i]|[%-+010.5i]|[%- 010.5i]",
				42, 42, 42, 42, -42, -42, 42, -42)
			: call_printf("i:[%+10i]|[% 10i]|[%+010i]|"
				"[% 010i]|[%-+10i]|[%- 10i]|[%-+010.5i]|[%- 010.5i]",
				42, 42, 42, 42, -42, -42, 42, -42));
	if (test == 28)
		return (use_ft ? ft_printf("u:[%10u]|[%-10u]|[%010u]|[%.5u]|"
				"[%10.5u]|[%-10.5u]|[%-010.5u]|[%+u]|[% u]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u)
			: call_printf("u:[%10u]|[%-10u]|[%010u]|[%.5u]|"
				"[%10.5u]|[%-10.5u]|[%-010.5u]|[%+u]|[% u]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u));
	if (test == 29)
		return (use_ft ? ft_printf("x:[%10x]|[%-10x]|[%010x]|[%.6x]|"
				"[%10.6x]|[%-10.6x]|[%-010.6x]|[%#x]|[%#08x]|"
				"[%-#10x]|[%#10.6x]|[%-#10.6x]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u)
			: call_printf("x:[%10x]|[%-10x]|[%010x]|[%.6x]|"
				"[%10.6x]|[%-10.6x]|[%-010.6x]|[%#x]|[%#08x]|"
				"[%-#10x]|[%#10.6x]|[%-#10.6x]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u));
	if (test == 30)
		return (use_ft ? ft_printf("X:[%10X]|[%-10X]|[%010X]|[%.6X]|"
				"[%10.6X]|[%-10.6X]|[%-010.6X]|[%#X]|[%#08X]|"
				"[%-#10X]|[%#10.6X]|[%-#10.6X]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u)
			: call_printf("X:[%10X]|[%-10X]|[%010X]|[%.6X]|"
				"[%10.6X]|[%-10.6X]|[%-010.6X]|[%#X]|[%#08X]|"
				"[%-#10X]|[%#10.6X]|[%-#10.6X]",
				42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u, 42u));
	if (test == 31)
		return (use_ft ? ft_printf("percent:[%5%]|[%-5%]|[%05%]")
			: call_printf("percent:[%5%]|[%-5%]|[%05%]"));
	return (use_ft ? ft_printf("plain text without conversions")
		: printf("plain text without conversions"));
}

static int	capture(const char *path, int use_ft, int test)
{
	int	fd;
	int	saved_stdout;
	int	result;

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		return (-1);
	fflush(NULL);
	saved_stdout = dup(STDOUT_FILENO);
	if (saved_stdout < 0 || dup2(fd, STDOUT_FILENO) < 0)
	{
		close(fd);
		return (-1);
	}
	result = invoke(use_ft, test);
	fflush(stdout);
	if (dup2(saved_stdout, STDOUT_FILENO) < 0)
		result = -1;
	close(saved_stdout);
	close(fd);
	return (result);
}

int	main(int argc, char **argv)
{
	int	expected;
	int	actual;
	int	test;

	if (argc != 4)
		return (2);
	test = atoi(argv[3]);
	expected = capture(argv[1], 0, test);
	actual = capture(argv[2], 1, test);
	fprintf(stderr, "printf=%d ft_printf=%d\n", expected, actual);
	if (expected < 0 || actual < 0)
		return (2);
	return (0);
}
EOF

HARNESS_OK=0
if [ -f "$LIB" ] \
	&& cc -Wall -Wextra -Werror -I"$DIR" "$T/harness.c" "$LIB" -o "$T/harness" \
		>"$T/compile.log" 2>&1; then
	ok "le harnais se compile avec -Wall -Wextra -Werror"
	HARNESS_OK=1
elif [ -f "$LIB" ]; then
	ko "échec de compilation du harnais" "$(cat "$T/compile.log")"
else
	skip "compilation du harnais (libftprintf.a indisponible)"
fi

title "7. Partie obligatoire : conversions cspdiuxX%"
labels=(
	"texte ordinaire"
	"%c"
	"%c avec caractère nul"
	"%s"
	"%s avec chaîne vide"
	"%%"
	"%d avec limites et valeurs usuelles"
	"%i avec limites et valeurs usuelles"
	"%u avec zéro et UINT_MAX"
	"%x avec zéro, valeur usuelle et UINT_MAX"
	"%X avec zéro, valeur usuelle et UINT_MAX"
	"%p avec adresse non nulle"
	"%p avec pointeur nul"
	"mélange des conversions obligatoires"
	"%s avec chaîne vide et pointeur nul"
	"%c avec caractères de contrôle"
	"%d avec valeurs limites"
	"%i avec valeurs limites"
	"%u avec UINT_MAX"
	"%x avec frontières de base"
	"%X avec frontières de base"
	"%p avec plusieurs pointeurs"
	"format vide"
)
run_case()
{
	local label=$1
	local test_id=$2
	local expected_return
	local actual_return
	local returns

	if ! "$T/harness" "$T/expected" "$T/actual" "$test_id" 2>"$T/returns"; then
		ko "$label : crash ou erreur du harnais" "$(cat "$T/returns")"
		return
	fi
	returns=$(cat "$T/returns")
	expected_return=$(sed -n 's/^printf=\(-\?[0-9][0-9]*\) ft_printf=.*/\1/p' "$T/returns")
	actual_return=$(sed -n 's/^.*ft_printf=\(-\?[0-9][0-9]*\)$/\1/p' "$T/returns")
	if cmp -s "$T/expected" "$T/actual"; then
		if [ "$expected_return" = "$actual_return" ]; then
			ok "$label"
		else
			ko "$label : valeurs de retour différentes" "$returns"
		fi
	else
		ko "$label : sorties différentes" \
			"attendu (hex) : $(od -An -tx1 "$T/expected" | tr -s ' ')"$'\n'"reçu (hex) : $(od -An -tx1 "$T/actual" | tr -s ' ')"$'\n'"$returns"
	fi
}
if [ "$HARNESS_OK" -eq 1 ]; then
	for i in "${!labels[@]}"; do
		run_case "${labels[$i]}" "$i"
	done
else
	for label in "${labels[@]}"; do
		skip "$label (conversion non exécutée)"
	done
fi

M_OK=$C_OK; M_KO=$C_KO; M_WARN=$C_WARN; M_SKIP=$C_SKIP
C_OK=0; C_KO=0; C_WARN=0; C_SKIP=0

bonus_labels=(
	"%c : largeur et alignement"
	"%s : largeur, alignement, précision et flag 0 ignoré"
	"%p : largeur, alignement et padding zéro"
	"%d : largeur, alignement, zéro et précision combinés"
	"%i : flags +, espace, zéro et alignement combinés"
	"%u : largeur, précision et flags signés ignorés"
	"%x : largeur, précision, # et combinaisons"
	"%X : largeur, précision, # et combinaisons"
	"%% : largeur et flags -/0"
)
if find "$DIR" -type f \( -name '*_bonus.c' -o -name '*_bonus.h' \) \
	-not -path "$DIR/.git/*" -print -quit | grep -q .; then
	BONUS_PRESENT=1
	title "8. BONUS : flags et largeur"
	if [ "$HARNESS_OK" -eq 1 ]; then
		for i in "${!bonus_labels[@]}"; do
			test_id=$((i + 23))
			run_case "${bonus_labels[$i]}" "$test_id"
		done
	else
		for label in "${bonus_labels[@]}"; do
			skip "$label (bonus non exécuté)"
		done
		B_SKIP=${#bonus_labels[@]}
	fi
else
	title "BONUS"
	printf '  %s⏭ Aucun fichier bonus détecté (*_bonus.c / *_bonus.h) : bonus ignorés.%s\n' \
		"$GRAY" "$RST"
	B_SKIP=${#bonus_labels[@]}
fi
B_OK=$C_OK; B_KO=$C_KO; B_WARN=$C_WARN; B_SKIP=$B_SKIP

if [ "$BONUS_PRESENT" -eq 1 ]; then
	exit "$((M_KO + B_KO > 0))"
fi
exit "$((M_KO > 0))"
