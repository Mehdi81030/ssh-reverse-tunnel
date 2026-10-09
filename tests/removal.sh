#!/usr/bin/env bash
# Partial profiles and deletion failures must not leave a false success result.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-remove.XXXXXX)
trap '[[ $scratch == /tmp/svt-remove.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles DROP=$scratch/dropins UNIT_DIR=$scratch/units HOME_ROOT=$scratch/homes
SSHD_CONFIG=$scratch/sshd_config
mkdir -p "$BASE/other" "$DROP" "$UNIT_DIR" "$HOME_ROOT"
printf '# retained\n' > "$DROP/other.conf"
printf 'retained\n' > "$UNIT_DIR/other.service"
touch "$SSHD_CONFIG"
need_runtime() { :; }
tunnel_connected() { return 1; }
SSHD_VALID=1 STOP_FAIL=0 PROCESSES=0
faux_sshd() { [[ $1 == -t && $2 == -f && $3 == "$SSHD_CONFIG" && $SSHD_VALID == 1 ]]; }
find_sshd() { SSHD=faux_sshd; }
reload_sshd() { printf 'reload\n' >> "$scratch/calls"; }
systemctl() {
  case $1 in
    show) if [[ -f $UNIT_DIR/$UNIT ]]; then echo loaded; else echo not-found; fi;;
    disable)
      [[ $STOP_FAIL == 0 ]] || return 1
      rm -f "$scratch/active"
      printf '%s\n' "$*" >> "$scratch/calls";;
    is-active) [[ -f $scratch/active ]];;
    is-enabled) return 1;;
    daemon-reload|reset-failed) :;;
    *) return 1;;
  esac
}
id() { [[ $1 == "$ACCOUNT" && -f $scratch/account ]]; }
getent() {
  [[ $1 == passwd && $2 == "$ACCOUNT" ]]
  printf '%s:x:999:999::%s/%s:/bin/sh\n' "$ACCOUNT" "$HOME_ROOT" "$ACCOUNT"
}
pkill() {
  [[ $2 == -u && $3 == "$ACCOUNT" ]]
  case $1 in
    -TERM) PROCESSES=3;;
    -0) if (( PROCESSES > 0 )); then ((PROCESSES--)); return 0; else return 1; fi;;
    -KILL) PROCESSES=0;;
    *) return 2;;
  esac
}
sleep() { :; }
userdel() {
  [[ $1 == -r && $2 == "$ACCOUNT" && $PROCESSES == 0 ]]
  rm -f "$scratch/account"
  rm -rf -- "$HOME_ROOT/$ACCOUNT"
}
profile() {
  select_profile "$1"
  mkdir -p "$DIR"
}
profile orphan-unit
printf 'unit\n' > "$UNIT_DIR/$UNIT"
mkdir -p "$UNIT_DIR/$UNIT.d"
printf 'override\n' > "$UNIT_DIR/$UNIT.d/ssh-tunnel-auto-restart.conf"
touch "$scratch/active"
remove_profile "$NAME" <<< y > "$scratch/unit.txt"
[[ ! -e $DIR && ! -e $UNIT_DIR/$UNIT && ! -e $UNIT_DIR/$UNIT.d ]]
echo 'PASS missing initiator marker: existing unit and owned override are removed'

profile missing-snippet
printf 'reverse\n' > "$DIR/receiver"
mkdir -p "$HOME_ROOT/$ACCOUNT/.ssh"
printf 'old key\n' > "$HOME_ROOT/$ACCOUNT/.ssh/authorized_keys"
touch "$scratch/account"
remove_profile "$NAME" <<< y > "$scratch/receiver.txt"
[[ ! -e $DIR && ! -e $HOME_ROOT/$ACCOUNT && ! -e $scratch/account ]]
echo 'PASS missing receiver snippet: processes exit before account/home deletion'

profile invalid-ssh
printf 'reverse\n' > "$DIR/receiver"
printf '# managed fixture\n' > "$SNIPPET"
cp "$SNIPPET" "$scratch/expected-snippet"
SSHD_VALID=0
if (remove_profile "$NAME" <<< y) > "$scratch/invalid.txt" 2>&1; then exit 1; fi
cmp "$SNIPPET" "$scratch/expected-snippet"
[[ -d $DIR ]]
SSHD_VALID=1
echo 'PASS failed SSH validation: dedicated snippet restored; profile retained'

profile stop-failure
printf 'direct\n' > "$DIR/initiator"
printf 'unit\n' > "$UNIT_DIR/$UNIT"
STOP_FAIL=1
if (remove_profile "$NAME" <<< y) > "$scratch/stop.txt" 2>&1; then exit 1; fi
[[ -d $DIR && -f $UNIT_DIR/$UNIT ]]
STOP_FAIL=0
echo 'PASS stop failure: service and profile retained; no success reported'

[[ -d $BASE/other && -s $DROP/other.conf && -s $UNIT_DIR/other.service ]]
echo 'PASS scope: other profiles, units and SSH settings retained'
