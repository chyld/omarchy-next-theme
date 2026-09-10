#!/usr/bin/bash

# Exercises validate_name() from bin/next-theme.sh against theme names a
# third-party theme could choose. The function is extracted from the shipped
# script rather than copied, so these cases test what actually runs.

set -uo pipefail
export LC_ALL=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
helper="$script_dir/../bin/next-theme.sh"

eval "$(sed -n '/^readonly MAX_NAME=/p;/^validate_name()/,/^}/p' "$helper")"

failures=0

expect_accept() {
  if validate_name "$1" >/dev/null; then
    printf 'ok       accept  %s\n' "$2"
  else
    printf 'NOT OK   accept  %s\n' "$2"
    failures=$((failures + 1))
  fi
}

expect_reject() {
  if validate_name "$1" >/dev/null; then
    printf 'NOT OK   reject  %s\n' "$2"
    failures=$((failures + 1))
  else
    printf 'ok       reject  %s\n' "$2"
  fi
}

expect_accept 'Tokyo Night'          'ordinary name containing a space'
expect_accept 'Biscuit De Mar Dark'  'longest stock name'
expect_reject '--version'            'option-shaped name'
expect_reject '-rf'                  'short option'
expect_reject "$(printf 'a\nb')"     'embedded newline'
expect_reject "$(printf 'a\x07b')"   'C0 control character'
expect_reject "$(printf 'a\xe2\x80\xaeb')" 'bidi override'
expect_reject "$(printf 'x%.0s' {1..200})" 'name past the 128 byte cap'
expect_reject ''                     'empty name'

if ((failures)); then
  printf '\n%d failure(s)\n' "$failures"
  exit 1
fi
printf '\nall validate_name cases passed\n'
