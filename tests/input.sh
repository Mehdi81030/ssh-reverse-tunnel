#!/usr/bin/env bash
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh"
expect_input() {
  local actual
  read_input actual <<< "$1"
  [[ $actual == "$2" ]]
}
expect_input $'mس\177ain' main
expect_input $'mس\bain' main
expect_input $'بد\177\177main' main
expect_input $'wrong\025main' main
expect_input '  main  ' main
expect_input '۸۴۴۳' 8443
expect_input '٨٤٤٣' 8443
expect_input 'ssh-ed25519 AAAA comment۱۲' 'ssh-ed25519 AAAA comment۱۲'
expect_input 'mainس' 'mainس'
get_port PORT test 8443 <<< $'س\177۸۴۴۳' >/dev/null
[[ $PORT == 8443 ]]
get_name <<< $'س\177' >/dev/null
[[ $NAME == main ]]
confirm test <<< $'wrong\ny' >/dev/null
if confirm test <<< 'n' >/dev/null; then exit 1; fi
echo 'PASS piped input: corrections, defaults, numeric normalization and key preservation'
# Minimal locales still erase the entire UTF-8 character in piped input.
UI_LOCALE=C
export LC_ALL=C
expect_input $'mس\177ain' main
expect_input $'بد\177\177main' main
echo 'PASS byte-locale fallback: complete UTF-8 characters erased'
