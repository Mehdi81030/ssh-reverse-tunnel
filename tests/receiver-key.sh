#!/usr/bin/env bash
# Existing receiver keys can be replaced without changing forwarding rights.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-key.XXXXXX)
trap '[[ $scratch == /tmp/svt-key.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles DROP=$scratch/dropins
mkdir -p "$BASE" "$DROP" "$scratch/home/.ssh"
test_group=$(id -gn)
id() { if [[ ${1:-} == -gn ]]; then printf '%s\n' "$test_group"; fi; }
chown() { :; }
ssh-keygen -q -t ed25519 -N '' -f "$scratch/old"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/new"
for MODE in reverse direct; do
  select_profile "$MODE"
  mkdir -p "$DIR"
  if [[ $MODE == reverse ]]; then TARGET=0.0.0.0:60250; else TARGET=127.0.0.1:443; fi
  write_receiver_snippet
  cp "$SNIPPET" "$scratch/unchanged-snippet"
  PUBLIC_KEY=$(cat "$scratch/old.pub")
  write_authorized_key "$scratch/home/.ssh/authorized_keys"
  cp "$scratch/home/.ssh/authorized_keys" "$scratch/old-authorized"
  PUBLIC_KEY=$(cat "$scratch/new.pub")
  update_receiver_key "$scratch/home" > "$scratch/update-$MODE.txt"
  cmp "$SNIPPET" "$scratch/unchanged-snippet"
  cmp "$DIR/authorized_keys.before-update" "$scratch/old-authorized"
  expected=$(write_authorized_key /dev/stdout)
  [[ $(cat "$scratch/home/.ssh/authorized_keys") == "$expected" ]]
  [[ $(stat -c %a "$scratch/home/.ssh/authorized_keys") == 600 ]]
  [[ $(stat -c %a "$scratch/home/.ssh") == 700 ]]
  cp "$scratch/home/.ssh/authorized_keys" "$scratch/new-authorized"
  if (PUBLIC_KEY='ssh-ed25519 AAAA invalid'; update_receiver_key "$scratch/home") > "$scratch/invalid.txt" 2>&1; then exit 1; fi
  cmp "$scratch/home/.ssh/authorized_keys" "$scratch/new-authorized"
  printf 'Match User %s\n    PermitOpen *:*\n    PermitListen *:*\n' "$ACCOUNT" > "$SNIPPET"
  if (update_receiver_key "$scratch/home") > "$scratch/wide.txt" 2>&1; then exit 1; fi
  cmp "$scratch/home/.ssh/authorized_keys" "$scratch/new-authorized"
  echo "PASS $MODE key update: valid key replaced atomically; old key backed up; rights retained; bad input preserved prior key"
done
# Check the actual existing-profile UI; account creation and SSH reload are forbidden.
need_runtime() { :; }
ensure_tools() { :; }
find_sshd() { :; }
ensure_sshd_service() { :; }
show_host_fingerprints() { :; }
useradd() { die 'Existing receiver recreated its account.'; }
reload_sshd() { die 'Key update reloaded SSH.'; }
update_receiver_key() {
  [[ $1 == /home/svt-main && $PUBLIC_KEY == "$(cat "$scratch/new.pub")" ]]
  printf 'updated\n' > "$scratch/ui-update"
}
mkdir -p "$BASE/main"
printf 'reverse\n' > "$BASE/main/receiver"
QUICK_MODE=reverse
receiver <<< $'main\n' > "$scratch/keep.txt"
[[ ! -f $scratch/ui-update ]]
receiver <<< "main"$'\n'"$(cat "$scratch/new.pub")" > "$scratch/replace.txt"
[[ -f $scratch/ui-update ]]
echo 'PASS existing receiver menu: Enter keeps the key; pasted key updates without recreating account'
