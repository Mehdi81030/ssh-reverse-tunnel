#!/usr/bin/env bash
# Service actions use temporary unit/profile files and mocked systemctl.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-menu.XXXXXX)
trap '[[ $scratch == /tmp/svt-menu.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles
DROP=$scratch/dropins
UNIT_DIR=$scratch/units
calls=$scratch/calls
state_file=$scratch/state
mkdir -p "$BASE/main" "$BASE/remote" "$DROP" "$UNIT_DIR"
: > "$calls"
printf 'active\n' > "$state_file"
need_runtime() { :; }
find_sshd() { SSHD=/bin/true; }
systemd-analyze() { [[ $1 == verify && -s $2 ]]; }
FAIL_RESTART=0
systemctl() {
  local policy
  case $1 in
    is-active)
      if [[ $2 != --quiet ]]; then cat "$state_file"; fi
      [[ $(cat "$state_file") == active ]];;
    is-enabled) return 0;;
    show)
      policy=always
      if [[ -f $UNIT_DIR/ssh-v2ray-main.service.d/ssh-tunnel-auto-restart.conf ]]; then
        policy=$(sed -n 's/^Restart=//p' "$UNIT_DIR/ssh-v2ray-main.service.d/ssh-tunnel-auto-restart.conf")
      fi
      printf '%s\n' "$policy";;
    cat) cat "$UNIT_DIR/$2";;
    start|stop|restart)
      printf '%s\n' "$*" >> "$calls"
      [[ $2 == ssh-v2ray-main.service ]] || return 1
      if [[ $1 == restart && $FAIL_RESTART == 1 ]]; then return 1; fi
      if [[ $1 == stop ]]; then printf 'inactive\n' > "$state_file"; else printf 'active\n' > "$state_file"; fi;;
    daemon-reload|disable) printf '%s\n' "$*" >> "$calls";;
    *) return 1;;
  esac
}
select_profile main
MODE=reverse REMOTE=example.org SSH_PORT=22 LISTEN_PORT=8443 BACKEND=127.0.0.1 V2_PORT=443
printf 'reverse\n' > "$DIR/initiator"
printf 'private-key-content-must-stay-private\n' > "$DIR/id_ed25519"
printf 'trusted-mock-host\n' > "$DIR/known_hosts"
save_summary
build_ssh_args
write_unit "$UNIT_DIR/$UNIT"
profile_info main
[[ $P_STATE == active && $P_AUTO == Yes && $P_ENTRY == 8443 ]]
render_service > "$scratch/screen.txt"
grep -q 'Auto-Restart Management' "$scratch/screen.txt"
grep -q 'Edit Configuration' "$scratch/screen.txt"
grep -q '8443' "$scratch/screen.txt"
! grep -q 'Role\|KCP\|MTU' "$scratch/screen.txt"
service_action 2
profile_info main
[[ $P_STATE == inactive ]]
service_action 1
service_action 3
grep -q '^stop ssh-v2ray-main.service$' "$calls"
grep -q '^start ssh-v2ray-main.service$' "$calls"
grep -q '^restart ssh-v2ray-main.service$' "$calls"
echo 'PASS details and actions: SSH settings shown; only the dedicated unit is started/stopped/restarted'

show_service_config > "$scratch/config.txt"
! grep -q 'private-key-content-must-stay-private' "$scratch/config.txt"
grep -q 'ExecStart=' "$scratch/config.txt"
auto_restart_menu <<< $'2\ny'
profile_info main
[[ $P_AUTO == No ]]
auto_restart_menu <<< $'1\ny'
profile_info main
[[ $P_AUTO == Yes ]]
echo 'PASS auto restart: policy toggles; configuration view does not reveal private key contents'

edit_service_config <<< $'\n\n8444\n8445\ny'
grep -q '^IranPort=8444$' "$DIR/summary"
grep -q '^Backend=127.0.0.1:8445$' "$DIR/summary"
grep -q '0.0.0.0:8444:127.0.0.1:8445' "$UNIT_DIR/$UNIT"
cp "$DIR/summary" "$scratch/expected-summary"
cp "$UNIT_DIR/$UNIT" "$scratch/expected-unit"
profile_info main
FAIL_RESTART=1
if (edit_service_config <<< $'\n\n8450\n8446\ny') > "$scratch/rollback.txt" 2>&1; then
  echo 'ERROR: simulated restart failure was not handled'; exit 1
fi
cmp "$DIR/summary" "$scratch/expected-summary"
cmp "$UNIT_DIR/$UNIT" "$scratch/expected-unit"
FAIL_RESTART=0
echo 'PASS edit: new settings written; failed restart restores prior settings'

printf 'reverse\n' > "$BASE/remote/receiver"
printf 'Match User svt-remote\n    PermitListen 0.0.0.0:9443\n' > "$DROP/00-ssh-v2ray-remote.conf"
: > "$calls"
profile_info remote
render_service > "$scratch/receiver.txt"
[[ $P_AUTO == Remote && $P_ENTRY == 9443 ]]
! grep -q '1\. .*Start\|2\. .*Stop\|Edit Configuration' "$scratch/receiver.txt"
service_action 1
auto_restart_menu
[[ ! -s $calls ]]
echo 'PASS receiver: remote service controls are hidden; shared sshd is never stopped or restarted'

profile_info main
remove_profile main <<< 'n'
[[ -d $BASE/main ]]
remove_profile main <<< 'y'
[[ ! -d $BASE/main && -d $BASE/remote && ! -f $UNIT_DIR/ssh-v2ray-main.service ]]
[[ ! -e $UNIT_DIR/ssh-v2ray-main.service.d ]]
echo 'PASS delete: named confirmation; selected profile and its owned auto-restart override removed'
