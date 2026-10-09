#!/usr/bin/env bash
# Build, delete BOTH ends and rebuild with the same name using real SSH/systemd.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
[[ $EUID == 0 && -d /run/systemd/system ]] || die 'This test requires root and running systemd.'
for port in 32422 32423 32424 32425; do
  [[ -z $(ss -H -ltn "sport = :$port") ]] || die "Test port $port is occupied."
done
scratch=$(mktemp -d /run/svt-recreate.XXXXXX)
chmod 711 "$scratch"
test_name=rebuild-$$
test_account=svt-$test_name
test_unit=ssh-v2ray-$test_name.service
HOME_ROOT=$scratch/homes
DROP=$scratch/dropins
SSHD_CONFIG=$scratch/sshd_config
UNIT_DIR=/run/systemd/system
receiver_base=$scratch/receiver
initiator_base=$scratch/initiator
sshd_pid='' backend_pid='' stubborn_pid=''
! id "$test_account" >/dev/null 2>&1 || die 'Test account already exists.'
[[ ! -e $UNIT_DIR/$test_unit ]] || die 'Test unit already exists.'
cleanup() {
  systemctl disable --now "$test_unit" >/dev/null 2>&1 || true
  rm -f -- "/run/systemd/system/$test_unit"
  systemctl daemon-reload
  systemctl reset-failed "$test_unit" >/dev/null 2>&1 || true
  if id "$test_account" >/dev/null 2>&1; then
    pkill -KILL -u "$test_account" 2>/dev/null || true
    sleep 0.3
    userdel -r "$test_account" 2>/dev/null || true
  fi
  for process in "$sshd_pid" "$backend_pid" "$stubborn_pid"; do
    [[ -z $process ]] || kill "$process" 2>/dev/null || true
  done
  [[ $scratch == /run/svt-recreate.* ]] && rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'journalctl -u "$test_unit" -n 25 --no-pager >&2; tail -n 20 "$scratch/sshd.log" >&2; echo "FAIL line $LINENO" >&2' ERR
mkdir -p "$HOME_ROOT" "$DROP" "$receiver_base" "$initiator_base"
mkdir -p "$scratch/receiver-units" "$scratch/receiver-runtime"
chmod 755 "$HOME_ROOT"
printf '# unrelated SSH drop-in\n' > "$DROP/00-other.conf"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/host"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/stale-key"
cat > "$SSHD_CONFIG" <<EOF
Include $DROP/*.conf
Port 32422
ListenAddress 127.0.0.1
HostKey $scratch/host
PidFile $scratch/sshd.pid
AuthorizedKeysFile %h/.ssh/authorized_keys
StrictModes yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
EOF
/usr/sbin/sshd -t -f "$SSHD_CONFIG"
/usr/sbin/sshd -D -e -f "$SSHD_CONFIG" > "$scratch/sshd.log" 2>&1 &
sshd_pid=$!
printf 'recreated-forwarding\n' > "$scratch/probe.txt"
python3 -m http.server 32423 --bind 127.0.0.1 --directory "$scratch" > "$scratch/backend.log" 2>&1 &
backend_pid=$!
# Use only the isolated SSH daemon, never the production SSH service.
ensure_sshd_service() { :; }
reload_sshd() { kill -HUP "$sshd_pid"; sleep 0.2; }
show_host_fingerprints() { :; }
# Simulate separate hosts: the receiver cannot see the initiator's systemd unit.
systemctl() {
  if [[ $BASE == "$receiver_base" && $1 == show && ${3:-} == LoadState ]]; then
    printf 'not-found\n'
  else
    command systemctl "$@"
  fi
}
for mode in reverse direct; do
  prior_fingerprint=''
  for cycle in 1 2; do
    BASE=$initiator_base
    make_key <<< "$test_name" > "$scratch/key.txt"
    public_key=$(cat "$DIR/id_ed25519.pub")
    fingerprint=$(ssh-keygen -lf "$DIR/id_ed25519.pub")
    [[ $fingerprint != "$prior_fingerprint" ]]
    prior_fingerprint=$fingerprint
    MODE=$mode REMOTE=127.0.0.1 SSH_PORT=32422 BACKEND=127.0.0.1 V2_PORT=32423
    if [[ $mode == reverse ]]; then LISTEN_PORT=32424; else LISTEN_PORT=32425; fi
    make_setup_link
    peer_link=$SETUP_LINK
    BASE=$receiver_base
    UNIT_DIR=$scratch/receiver-units RUNTIME_ROOT=$scratch/receiver-runtime
    QUICK_MODE=$mode
    if [[ $cycle == 2 ]]; then
      # The receiver gets every field from the link; only Create Tunnel? is answered.
      import_setup_link "$peer_link" <<< y > "$scratch/receiver.txt"
      entry=$LISTEN_PORT
    elif [[ $mode == reverse ]]; then
      receiver <<< "$test_name"$'\n32424\n32422\n'"$public_key"$'\ny' > "$scratch/receiver.txt"
      entry=32424
    else
      receiver <<< "$test_name"$'\n32423\n32422\n'"$public_key"$'\ny' > "$scratch/receiver.txt"
      entry=32425
    fi
    BASE=$initiator_base
    UNIT_DIR=/run/systemd/system RUNTIME_ROOT=/run
    select_profile "$test_name"
    MODE=$mode REMOTE=127.0.0.1 SSH_PORT=32422 LISTEN_PORT=$entry BACKEND=127.0.0.1 V2_PORT=32423
    printf '[127.0.0.1]:32422 %s\n' "$(cat "$scratch/host.pub")" > "$DIR/known_hosts"
    build_ssh_args
    install_tunnel_service > "$scratch/initiator.txt"
    profile_info "$test_name"
    [[ $P_STATE == active ]]
    [[ $(curl --fail --silent --max-time 5 "http://127.0.0.1:$entry/probe.txt") == recreated-forwarding ]]
    if [[ $cycle == 2 ]]; then
      # Reproduce an existing receiver with stale port/key settings.
      BASE=$receiver_base
      UNIT_DIR=$scratch/receiver-units RUNTIME_ROOT=$scratch/receiver-runtime
      select_profile "$test_name"
      before_uid=$(id -u "$ACCOUNT")
      touch "$HOME_ROOT/$ACCOUNT/keep-me"
      if [[ $mode == reverse ]]; then TARGET=0.0.0.0:32426; else TARGET=127.0.0.1:32426; fi
      PUBLIC_KEY=$(cat "$scratch/stale-key.pub")
      write_receiver_snippet
      write_authorized_key "$HOME_ROOT/$ACCOUNT/.ssh/authorized_keys"
      reload_sshd
      stop_receiver_sessions
      import_setup_link "$peer_link" <<< y > "$scratch/reapply.txt"
      [[ $(id -u "$ACCOUNT") == "$before_uid" && -f $HOME_ROOT/$ACCOUNT/keep-me ]]
      [[ -s $DIR/sshd.before-link && -s $DIR/authorized_keys.before-link ]]
      BASE=$initiator_base
      UNIT_DIR=/run/systemd/system RUNTIME_ROOT=/run
      select_profile "$test_name"
      connected=false
      for ((attempt=0; attempt<100; attempt++)); do
        if tunnel_connected; then connected=true; break; fi
        sleep 0.2
      done
      $connected
      [[ $(curl --fail --silent --max-time 5 "http://127.0.0.1:$entry/probe.txt") == recreated-forwarding ]]
      echo "PASS $mode existing receiver: link updated stale port/key; account/home preserved; real SSH reconnected and HTTP forwarded"
    fi
    if [[ $mode == reverse && $cycle == 1 ]]; then
      # TERM alone cannot finish this process: removal must wait then use KILL.
      runuser -u "$test_account" -- bash -c 'trap "" TERM; exec sleep 120' > /dev/null 2>&1 &
      stubborn_pid=$!
      sleep 0.2
    fi
    # Delete the receiver while its forwarding session is still connected.
    BASE=$receiver_base
    UNIT_DIR=$scratch/receiver-units RUNTIME_ROOT=$scratch/receiver-runtime
    remove_profile "$test_name" <<< y > "$scratch/delete-receiver.txt"
    [[ ! -e $BASE/$test_name && ! -e $HOME_ROOT/$test_account && ! -e $DROP/00-ssh-v2ray-$test_name.conf ]]
    ! id "$test_account" >/dev/null 2>&1
    [[ -s $DROP/00-other.conf ]]
    kill -0 "$sshd_pid"
    if [[ -n $stubborn_pid ]]; then wait "$stubborn_pid" 2>/dev/null || true; stubborn_pid=''; fi
    BASE=$initiator_base
    UNIT_DIR=/run/systemd/system RUNTIME_ROOT=/run
    remove_profile "$test_name" <<< y > "$scratch/delete-initiator.txt"
    [[ ! -e $BASE/$test_name && ! -e $UNIT_DIR/$test_unit && ! -e /run/ssh-v2ray-$test_name ]]
    ! systemctl is-enabled --quiet "$test_unit" 2>/dev/null
    ! systemctl is-active --quiet "$test_unit"
    echo "PASS $mode cycle $cycle: actual account/key/unit removed; same name rebuilt and HTTP forwarded"
  done
done
