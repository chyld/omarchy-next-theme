#!/usr/bin/bash

# Step the Omarchy theme through `omarchy theme list`.
#
#   next-theme.sh             apply the next theme, wrapping at the end
#   next-theme.sh --prev      apply the previous theme
#   next-theme.sh --current   print the active theme, change nothing
#
# Every mode prints the resulting theme name on stdout and nothing else, so the
# bar widget never needs a second round trip to learn what is active.
#
# Theme names are directory names, and `omarchy theme install <git-url>` lets a
# third party choose one. They are treated as untrusted throughout: capped in
# length, refused if they contain non-printable bytes, and refused if they are
# option-shaped.

set -uo pipefail

# A fixed, minimal environment. The bar widget already clears the environment
# before exec, but this script is also runnable by hand, where BASH_ENV and
# friends would otherwise ride in from the invoking shell.
export PATH=/usr/bin:/bin
export LC_ALL=C
unset BASH_ENV ENV CDPATH GLOBIGNORE LD_PRELOAD LD_LIBRARY_PATH PYTHONPATH PERL5OPT GIT_DIR
: "${OMARCHY_PATH:=/usr/share/omarchy}"
export OMARCHY_PATH

readonly OMARCHY=/usr/bin/omarchy
readonly SETSID=/usr/bin/setsid
readonly TIMEOUT=/usr/bin/timeout
readonly HEAD=/usr/bin/head

# Byte ceilings. A theme name is one directory name; the list is ~40 of them.
readonly MAX_NAME=128
readonly MAX_LIST=16384

# Deadlines. Reading is quick; `theme set` regenerates terminal, editor and
# compositor config and restarts the shell, so it gets a far longer leash.
readonly READ_DEADLINE=20
readonly SET_DEADLINE=90

# Run a child in its own session under an absolute deadline, capping output at
# the producer so an oversized reply is never collected into memory. The length
# check afterwards distinguishes overflow from a legitimately short answer,
# rather than silently consuming a truncated one.
run_bounded() {
  local max=$1 deadline=$2
  shift 2
  local out
  out=$("$SETSID" -w "$TIMEOUT" -k 2 -- "$deadline" "$@" | "$HEAD" -c $((max + 1))) || return 1
  [ ${#out} -le "$max" ] || return 1
  printf '%s' "$out"
}

# Refuse anything that could act as an option, carry a control character, or
# blow the length cap, instead of trying to repair it.
validate_name() {
  local name=$1
  case $name in
    '' | -*) return 1 ;;
    *[![:print:]]*) return 1 ;;
  esac
  [ "${#name}" -le "$MAX_NAME" ] || return 1
  printf '%s' "$name"
}

mode=${1:---next}
case $mode in
  --next | --prev | --current) ;;
  *) printf 'unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  printf 'unexpected arguments\n' >&2
  exit 2
fi

current=$(run_bounded "$MAX_NAME" "$READ_DEADLINE" "$OMARCHY" theme current) || current=""

if [[ $mode == --current ]]; then
  validate_name "$current" || exit 1
  printf '\n'
  exit 0
fi

step=1
[[ $mode == --prev ]] && step=-1

list=$(run_bounded "$MAX_LIST" "$READ_DEADLINE" "$OMARCHY" theme list) || exit 1
[[ -n $list ]] || exit 1
mapfile -t themes <<<"$list"
count=${#themes[@]}
((count)) || exit 1

# Default to the first theme so an unrecognised current theme — one just
# removed, say — still lands somewhere valid instead of doing nothing.
# Only internally generated integers ever reach the arithmetic below.
next=${themes[0]}
for i in "${!themes[@]}"; do
  if [[ ${themes[i]} == "$current" ]]; then
    next=${themes[(i + step + count) % count]}
    break
  fi
done

next=$(validate_name "$next") || exit 1

"$SETSID" -w "$TIMEOUT" -k 5 -- "$SET_DEADLINE" "$OMARCHY" theme set "$next" >/dev/null 2>&1 || exit 1
printf '%s\n' "$next"
