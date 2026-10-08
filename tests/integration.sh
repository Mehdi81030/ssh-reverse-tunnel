#!/usr/bin/env bash
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh"
[[ $EUID == 0 ]] || die "Run this integration test with sudo bash."
for test_port in 32222 32223 32224 32225 32226; do
  [[ -z $(ss -H -ltn "sport = :$test_port") ]] || die "Test port $test_port is already in use."
done
get_port CHECK_PORT test 8443 <<< $'invalid\n0\n65536\n08443' >/dev/null
[[ $CHECK_PORT == 8443 ]]
get_host CHECK_HOST test <<< $'bad host\nserver.example.com' >/dev/null
[[ $CHECK_HOST == server.example.com ]]
get_mode <<< '2' >/dev/null
[[ $MODE == direct ]]
get_name <<< $'../../bad\nmain' >/dev/null
[[ $NAME == main && $ACCOUNT == svt-main ]]
echo 'PASS menu: invalid values rejected; defaults and input assignment work'
scratch=$(mktemp -d /run/svt-test.XXXXXX)
sshd_pid=''
ssh_pid=''
backend_pid=''
stall_pid=''
cleanup() {
  for process in "$ssh_pid" "$sshd_pid" "$backend_pid" "$stall_pid"; do
    [[ -z $process ]] || kill "$process" 2>/dev/null || true
  done
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'tail -n 30 "$scratch/test.log" >&2; echo "failed at $LINENO" >&2' ERR
DIR=$scratch
NAME=integration
ACCOUNT=root
REMOTE=127.0.0.1
SSH_PORT=32222
BACKEND=127.0.0.1
V2_PORT=32223
SNIPPET=$scratch/receiver.conf
ssh-keygen -q -t ed25519 -N '' -f "$scratch/host"
ssh-keygen -q -t ed25519 -N '' -f "$DIR/id_ed25519"
chmod 700 "$scratch"
python3 -m http.server "$V2_PORT" --bind 127.0.0.1 --directory "$scratch" > "$scratch/backend.log" 2>&1 &
backend_pid=$!
printf 'forwarding-success\n' > "$scratch/probe.txt"
for MODE in direct reverse; do
  if [[ $MODE == direct ]]; then LISTEN_PORT=32224; TARGET=$BACKEND:$V2_PORT; else LISTEN_PORT=32225; TARGET=0.0.0.0:$LISTEN_PORT; fi
  write_receiver_snippet
  if [[ $MODE == direct ]]; then
    printf 'restrict,port-forwarding,permitopen="%s" %s\n' "$TARGET" "$(cat "$DIR/id_ed25519.pub")" > "$scratch/authorized_keys"
  else
    printf 'restrict,port-forwarding,permitlisten="%s" %s\n' "$TARGET" "$(cat "$DIR/id_ed25519.pub")" > "$scratch/authorized_keys"
  fi
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
  /usr/sbin/sshd -T -f "$scratch/sshd_config" -C user=root,host=localhost,addr=127.0.0.1 > "$scratch/effective-$MODE.txt"
  /usr/sbin/sshd -D -e -f "$scratch/sshd_config" > "$scratch/sshd-$MODE.log" 2>&1 &
  sshd_pid=$!
  sleep 1
  ssh-keyscan -p "$SSH_PORT" 127.0.0.1 > "$DIR/known_hosts" 2>/dev/null
  build_ssh_args
  write_unit "$scratch/ssh-v2ray-$MODE.service"
  systemd-analyze verify "$scratch/ssh-v2ray-$MODE.service"
  save_summary
  connection_test > "$scratch/test-success-$MODE.txt"
  grep -q 'succeeded' "$scratch/test-success-$MODE.txt"
  [[ -s $DIR/test.log ]]
  ssh "${SSH_ARGS[@]}" > "$scratch/ssh-$MODE.log" 2>&1 &
  ssh_pid=$!
  sleep 1
  actual=$(curl --fail --silent --max-time 5 "http://127.0.0.1:$LISTEN_PORT/probe.txt")
  [[ $actual == forwarding-success ]] || { cat "$scratch/ssh-$MODE.log"; exit 1; }
  # MaxSessions=0 must prevent shell/command execution on the tunnel account.
  if ssh -i "$DIR/id_ed25519" -p "$SSH_PORT" -o BatchMode=yes -o "UserKnownHostsFile=$DIR/known_hosts" root@127.0.0.1 true 2> "$scratch/shell-$MODE.log"; then
    echo 'ERROR: shell execution was allowed'; exit 1
  fi
  echo "PASS $MODE: real HTTP payload forwarded; shell denied; sshd config accepted"
  kill "$ssh_pid" "$sshd_pid"
  wait "$ssh_pid" 2>/dev/null || true
  wait "$sshd_pid" 2>/dev/null || true
  ssh_pid=''; sshd_pid=''
done

# A genuine timeout after key exchange: the receiver delays public-key lookup.
printf '#!/bin/sh\nsleep 40\ncat "%s/id_ed25519.pub"\n' "$scratch" > "$scratch/slow-key"
chmod 700 "$scratch/slow-key"
sed -e 's/Port 32222/Port 32226/' -e 's|AuthorizedKeysFile .*|AuthorizedKeysFile none|' "$scratch/sshd_config" > "$scratch/sshd-slow"
printf 'AuthorizedKeysCommand %s/slow-key\nAuthorizedKeysCommandUser root\n' "$scratch" >> "$scratch/sshd-slow"
/usr/sbin/sshd -t -f "$scratch/sshd-slow"
/usr/sbin/sshd -D -e -f "$scratch/sshd-slow" > "$scratch/stall.log" 2>&1 &
sshd_pid=$!
sleep 1
SSH_PORT=32226
ssh-keyscan -p "$SSH_PORT" 127.0.0.1 > "$DIR/known_hosts" 2>/dev/null
build_ssh_args
if connection_test > "$scratch/timeout-output.txt"; then
  echo 'ERROR: stalled SSH test reported success'; exit 1
fi
grep -q 'exit code: 124' "$scratch/timeout-output.txt"
grep -q 'authentication did not complete' "$scratch/timeout-output.txt"
grep -q 'Offering public key' "$scratch/timeout-output.txt"
[[ -s $DIR/test.log ]]
echo 'PASS timeout: exit 124 explained; debug log printed and saved'

# An action failure must not exit the top-level menu.
deliberate_failure() { die 'test failure'; }
run_action deliberate_failure <<< '' > "$scratch/recovery-output.txt" 2>&1
grep -q 'You can view logs or retry' "$scratch/recovery-output.txt"
echo 'PASS recovery: failed action returned to menu'
