#!/usr/bin/env bash
# Real systemd reconnects when a localhost receiver authorizes the key later.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
[[ $EUID == 0 && -d /run/systemd/system ]] || die 'This test needs root and running systemd.'
for port in 32322 32323 32324 32325; do
  [[ -z $(ss -H -ltn "sport = :$port") ]] || die "Test port $port is occupied."
done
scratch=$(mktemp -d /run/svt-order.XXXXXX)
BASE=$scratch/profiles DROP=$scratch/dropins UNIT_DIR=/run/systemd/system
mkdir -p "$BASE" "$DROP"
sshd_pid='' backend_pid=''
test_units=()
cleanup() {
  local unit
  for unit in "${test_units[@]}"; do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    rm -f -- "$UNIT_DIR/$unit"
  done
  systemctl daemon-reload
  [[ -z $sshd_pid ]] || kill "$sshd_pid" 2>/dev/null || true
  [[ -z $backend_pid ]] || kill "$backend_pid" 2>/dev/null || true
  [[ $scratch == /run/svt-order.* ]] && rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'journalctl -u "$UNIT" -n 25 --no-pager >&2; echo "FAIL line $LINENO" >&2' ERR
ssh-keygen -q -t ed25519 -N '' -f "$scratch/host"
printf 'order-independent-forwarding\n' > "$scratch/probe.txt"
python3 -m http.server 32323 --bind 127.0.0.1 --directory "$scratch" > "$scratch/backend.log" 2>&1 &
backend_pid=$!
wait_connected() {
  local attempt
  for ((attempt=0; attempt<100; attempt++)); do
    if tunnel_connected; then return 0; fi
    sleep 0.2
  done
  return 1
}
for MODE in reverse direct; do
  select_profile "order-${MODE:0:1}-$$"
  test_units+=("$UNIT")
  mkdir -p "$DIR"
  ACCOUNT=root REMOTE=127.0.0.1 SSH_PORT=32322 BACKEND=127.0.0.1 V2_PORT=32323
  if [[ $MODE == reverse ]]; then LISTEN_PORT=32324; TARGET=0.0.0.0:$LISTEN_PORT
  else LISTEN_PORT=32325; TARGET=$BACKEND:$V2_PORT; fi
  ssh-keygen -q -t ed25519 -N '' -f "$DIR/id_ed25519"
  printf '[127.0.0.1]:%s %s\n' "$SSH_PORT" "$(cat "$scratch/host.pub")" > "$DIR/known_hosts"
  write_receiver_snippet
  : > "$scratch/authorized_keys"
  cat > "$scratch/sshd_config" <<EOF
Include $SNIPPET
Port $SSH_PORT
ListenAddress 127.0.0.1
HostKey $scratch/host
PidFile $scratch/sshd.pid
AuthorizedKeysFile $scratch/authorized_keys
StrictModes yes
PermitRootLogin prohibit-password
UsePAM no
LogLevel VERBOSE
EOF
  /usr/sbin/sshd -t -f "$scratch/sshd_config"
  /usr/sbin/sshd -D -e -f "$scratch/sshd_config" > "$scratch/sshd.log" 2>&1 &
  sshd_pid=$!
  sleep 0.5
  build_ssh_args
  # The receiver exists, but has not registered the tunnel's public key yet.
  install_tunnel_service > "$scratch/setup-$MODE.txt"
  grep -q 'first SSH test failed' "$scratch/setup-$MODE.txt"
  profile_info "$NAME"
  [[ $P_STATE == Waiting && $P_AUTO == Yes && $P_BOOT == Yes ]]
  # Finish the receiver LAST. Do not restart or reconfigure the initiator.
  if [[ $MODE == reverse ]]; then permission=permitlisten; else permission=permitopen; fi
  printf 'restrict,port-forwarding,%s="%s" %s\n' "$permission" "$TARGET" "$(cat "$DIR/id_ed25519.pub")" > "$scratch/authorized_keys"
  chmod 600 "$scratch/authorized_keys"
  wait_connected
  profile_info "$NAME"
  [[ $P_STATE == active ]]
  [[ $(curl --fail --silent --retry 5 --retry-connrefused --max-time 5 "http://127.0.0.1:$LISTEN_PORT/probe.txt") == order-independent-forwarding ]]
  echo "PASS $MODE initiator-first: real systemd connected after key registration; HTTP forwarded"
  # Finish the initiator LAST with the receiver already prepared.
  systemctl stop "$UNIT"
  ACCOUNT=root
  build_ssh_args
  install_tunnel_service > "$scratch/receiver-first-$MODE.txt"
  grep -q 'SSH authentication and port forwarding succeeded' "$scratch/receiver-first-$MODE.txt"
  wait_connected
  [[ $(curl --fail --silent --max-time 5 "http://127.0.0.1:$LISTEN_PORT/probe.txt") == order-independent-forwarding ]]
  echo "PASS $MODE receiver-first: setup succeeds and real HTTP forwards"
  systemctl disable --now "$UNIT" >/dev/null
  kill "$sshd_pid"
  wait "$sshd_pid" 2>/dev/null || true
  sshd_pid=''
done
