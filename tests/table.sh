#!/usr/bin/env bash
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh"
scratch=$(mktemp -d /tmp/svt-table.XXXXXX)
trap '[[ $scratch == /tmp/svt-table.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles
DROP=$scratch/dropins
mkdir -p "$BASE/a-live" "$BASE/b-receiver" "$BASE/c-key" "$DROP"
need_runtime() { :; }
systemctl() {
  [[ $1 == is-active && $2 == ssh-v2ray-a-live.service ]] || return 1
  printf 'active\n'
}
printf 'reverse\n' > "$BASE/a-live/initiator"
printf 'Mode=reverse\nIranPort=60250\n' > "$BASE/a-live/summary"
printf 'direct\n' > "$BASE/b-receiver/receiver"
printf 'Match User svt-b-receiver\n    PermitListen none\n' > "$DROP/00-ssh-v2ray-b-receiver.conf"
printf 'temporary-key\n' > "$BASE/c-key/id_ed25519"
list_profiles <<< $'99\nx\n2\nn\n3\ny\nr\n0' > "$scratch/output.txt"
[[ -d $BASE/a-live && -d $BASE/b-receiver && ! -e $BASE/c-key ]]
[[ -f $DROP/00-ssh-v2ray-b-receiver.conf ]]
grep -q 'a-live.*reverse.*60250.*active' "$scratch/output.txt"
grep -q 'b-receiver.*direct.*Configured' "$scratch/output.txt"
grep -q "Delete tunnel 'c-key'" "$scratch/output.txt"
grep -q 'That row does not exist' "$scratch/output.txt"
grep -q 'Enter a valid row number' "$scratch/output.txt"
echo 'PASS table: all profiles shown; invalid rows rejected; cancel preserved receiver; selected key-only profile deleted'
mkdir -p "$scratch/empty"
BASE=$scratch/empty
list_profiles > "$scratch/empty.txt"
grep -q 'No tunnels have been configured' "$scratch/empty.txt"
echo 'PASS empty table: returned without asking for deletion'
