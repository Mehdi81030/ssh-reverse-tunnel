#!/usr/bin/env bash
# Check the whole setup flow when the receiver is not ready yet.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-order.XXXXXX)
trap '[[ $scratch == /tmp/svt-order.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles DROP=$scratch/dropins UNIT_DIR=$scratch/units
mkdir -p "$BASE" "$DROP" "$UNIT_DIR"
need_runtime() { :; }
need_client() { :; }
sleep() { :; }
ss() { :; }
journalctl() { :; }
trust_host() { printf 'trusted-test-host\n' > "$DIR/known_hosts"; }
connection_test() { printf 'initial-test-failed\n' > "$DIR/test.log"; return 1; }
CONNECTED=0
tunnel_connected() { [[ $CONNECTED == 1 ]]; }
systemctl() {
  case $1 in
    daemon-reload) :;;
    enable) [[ $2 == --now && -s $UNIT_DIR/$3 ]];;
    is-active) printf 'active\n';;
    is-enabled) return 0;;
    show)
      case $3 in
        RuntimeDirectory) printf 'ssh-v2ray-%s\n' "$NAME";;
        Restart) printf 'always\n';;
        *) return 1;;
      esac;;
    *) return 1;;
  esac
}
for mode in reverse direct; do
  QUICK_MODE=$mode
  CONNECTED=0
  initiator <<< "$mode"$'\n127.0.0.1\n22\n8443\n443' > "$scratch/$mode.txt"
  [[ -s $DIR/test.log && $(cat "$DIR/initiator") == "$mode" ]]
  [[ -s $UNIT_DIR/$UNIT ]]
  grep -q '^Restart=always$' "$UNIT_DIR/$UNIT"
  grep -q 'Waiting for SSH' "$scratch/$mode.txt"
  ! grep -q 'Is the other server ready' "$scratch/$mode.txt"
  profile_info "$mode"
  [[ $P_KIND == service && $P_STATE == Waiting && $P_AUTO == Yes ]]
  CONNECTED=1
  profile_info "$mode"
  [[ $P_STATE == active ]]
  echo "PASS $mode setup: failed initial test installs service; Waiting becomes active"
done
# Trust must still be verified before installing any service.
trust_host() { return 1; }
QUICK_MODE=direct
initiator <<< $'untrusted\n127.0.0.1\n22\n8443\n443' > "$scratch/untrusted.txt"
[[ ! -f $BASE/untrusted/initiator && ! -f $UNIT_DIR/ssh-v2ray-untrusted.service ]]
echo 'PASS identity: canceled host verification does not install a service'
