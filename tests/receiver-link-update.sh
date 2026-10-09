#!/usr/bin/env bash
# Applying a link replaces receiver permissions and rolls back failed updates.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-link-update.XXXXXX)
trap '[[ $scratch == /tmp/svt-link-update.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles DROP=$scratch/dropins HOME_ROOT=$scratch/homes
SSHD_CONFIG=$scratch/sshd_config
mkdir -p "$BASE" "$DROP" "$HOME_ROOT"
touch "$SSHD_CONFIG"
test_group=$(id -gn)
id() { if [[ $1 == -gn ]]; then printf '%s\n' "$test_group"; fi; }
chown() { :; }
VALIDATE_FAIL=0 BUSY=0 FAIL_STOP=0 FAIL_SUMMARY=0
ss() { if [[ $BUSY == 1 ]]; then printf 'occupied\n'; fi; return 0; }
faux_sshd() { [[ $1 == -t && $2 == -f && $3 == "$SSHD_CONFIG" && $VALIDATE_FAIL == 0 ]]; }
SSHD=faux_sshd
reload_sshd() {
  if [[ -f $scratch/fail-reload-once ]]; then rm "$scratch/fail-reload-once"; return 1; fi
  printf 'reload\n' >> "$scratch/reloads"
}
stop_receiver_sessions() {
  [[ $FAIL_STOP == 0 ]] || die 'Could not finish account sessions.'
  printf '%s\n' "$ACCOUNT" >> "$scratch/stopped"
}
mv() {
  if [[ $FAIL_SUMMARY == 1 && $3 == *summary.link.* ]]; then return 1; fi
  command mv "$@"
}
ssh-keygen -q -t ed25519 -N '' -f "$scratch/old"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/new"
for MODE in reverse direct; do
  select_profile "$MODE"
  mkdir -p "$DIR" "$HOME_ROOT/$ACCOUNT/.ssh"
  home_dir=$HOME_ROOT/$ACCOUNT
  key_file=$home_dir/.ssh/authorized_keys
  if [[ $MODE == reverse ]]; then TARGET=0.0.0.0:60250; else TARGET=127.0.0.1:8443; fi
  PUBLIC_KEY=$(cat "$scratch/old.pub")
  write_receiver_snippet
  write_authorized_key "$key_file"
  printf 'old-summary\n' > "$DIR/summary"
  cp "$SNIPPET" "$scratch/old-snippet"
  cp "$key_file" "$scratch/old-key"
  cp "$DIR/summary" "$scratch/old-summary"
  PUBLIC_KEY=$(cat "$scratch/new.pub")
  SSH_PORT=2299 LISTEN_PORT=8443 BACKEND=127.0.0.1 V2_PORT=443
  apply_receiver_link "$home_dir" > "$scratch/applied.txt"
  if [[ $MODE == reverse ]]; then
    grep -q '^    PermitListen 0.0.0.0:8443$' "$SNIPPET"
    grep -q 'permitlisten="0.0.0.0:8443"' "$key_file"
  else
    grep -q '^    PermitOpen 127.0.0.1:443$' "$SNIPPET"
    grep -q 'permitopen="127.0.0.1:443"' "$key_file"
  fi
  grep -q '^IranPort=8443$' "$DIR/summary"
  cmp "$DIR/sshd.before-link" "$scratch/old-snippet"
  cmp "$DIR/authorized_keys.before-link" "$scratch/old-key"
  grep -qx "$ACCOUNT" "$scratch/stopped"
  stops=$(wc -l < "$scratch/stopped")
  apply_receiver_link "$home_dir" > "$scratch/identical.txt"
  [[ $(wc -l < "$scratch/stopped") == "$stops" ]]
  echo "PASS $MODE update: new permission, restricted key and summary applied; changed tunnel reconnected; identical link keeps sessions"

  for failure in validation reload sessions summary; do
    cp "$scratch/old-snippet" "$SNIPPET"
    cp "$scratch/old-key" "$key_file"
    cp "$scratch/old-summary" "$DIR/summary"
    case $failure in
      validation) VALIDATE_FAIL=1;; reload) touch "$scratch/fail-reload-once";;
      sessions) FAIL_STOP=1;; summary) FAIL_SUMMARY=1;;
    esac
    if apply_receiver_link "$home_dir" > "$scratch/$failure.txt" 2>&1; then exit 1; fi
    VALIDATE_FAIL=0 FAIL_STOP=0 FAIL_SUMMARY=0
    cmp "$SNIPPET" "$scratch/old-snippet"
    cmp "$key_file" "$scratch/old-key"
    cmp "$DIR/summary" "$scratch/old-summary"
    grep -q 'Previous receiver settings and key were restored' "$scratch/$failure.txt"
    echo "PASS $MODE $failure failure: all three previous files restored"
  done
done
MODE=reverse
select_profile reverse
BUSY=1
cp "$SNIPPET" "$scratch/busy-snippet"
cp "$HOME_ROOT/$ACCOUNT/.ssh/authorized_keys" "$scratch/busy-key"
cp "$DIR/summary" "$scratch/busy-summary"
if apply_receiver_link "$HOME_ROOT/$ACCOUNT" > "$scratch/busy.txt" 2>&1; then exit 1; fi
cmp "$SNIPPET" "$scratch/busy-snippet"
cmp "$HOME_ROOT/$ACCOUNT/.ssh/authorized_keys" "$scratch/busy-key"
cmp "$DIR/summary" "$scratch/busy-summary"
echo 'PASS occupied reverse port: update rejected before touching live files'
