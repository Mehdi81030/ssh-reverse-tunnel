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
list_profiles <<< $'99\nx\n2\n9\nn\n\n0\n3\n9\ny\n\nr\n0' > "$scratch/output.txt"
[[ -d $BASE/a-live && -d $BASE/b-receiver && ! -e $BASE/c-key ]]
[[ -f $DROP/00-ssh-v2ray-b-receiver.conf ]]
grep -q 'a-live.*active.*reverse' "$scratch/output.txt"
grep -q 'b-receiver.*configured.*direct' "$scratch/output.txt"
grep -q "Delete tunnel 'c-key'" "$scratch/output.txt"
grep -q 'That row does not exist' "$scratch/output.txt"
grep -q 'Enter a row number' "$scratch/output.txt"
grep -q 'Select a service to manage' "$scratch/output.txt"
grep -q 'Details:' "$scratch/output.txt"
echo 'PASS table: service selection opens details; invalid rows rejected; cancel preserved profile; named delete removed only selected profile'
mkdir -p "$scratch/empty"
BASE=$scratch/empty
list_profiles > "$scratch/empty.txt"
grep -q 'No tunnels have been configured' "$scratch/empty.txt"
echo 'PASS empty table: returned without asking for deletion'
