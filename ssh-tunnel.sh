#!/usr/bin/env bash
# SSH TCP tunnel manager for Linux + systemd. Run as root on each server.
set -Eeuo pipefail
export LC_ALL=C
umask 077
BASE=/etc/ssh-v2ray-tunnel
DROP=/etc/ssh/sshd_config.d
[[ ${1:-} == --help ]] && { printf 'Usage: sudo bash %s [--no-color]\nColors are enabled by default. Linux + systemd; TCP forwarding only.\nSee README-fa.md.\n' "$0"; exit 0; }
C_RESET='' C_CYAN='' C_GREEN='' C_RED='' C_YELLOW='' C_BOLD='' C_WHITE='' C_GRAY=''
if [[ -z ${NO_COLOR:-} && ${1:-} != --no-color ]]; then
  C_RESET=$'\033[0m' C_RED=$'\033[31m' C_WHITE=$'\033[37m'
  C_GRAY=$'\033[90m' C_BOLD=$'\033[1m'
  # Existing status and table helpers use the same red / white / gray palette.
  C_CYAN=$C_RED C_GREEN=$C_WHITE C_YELLOW=$C_GRAY
fi
trap 'printf "\n%s[ERROR]%s Command failed at line %s. See the message above.\n" "$C_RED" "$C_RESET" "$LINENO" >&2' ERR

say() { printf '\n%s%s%s%s\n' "$C_BOLD" "$C_WHITE" "$*" "$C_RESET"; }
ok() { printf '\n%s%s[OK] %s%s\n' "$C_BOLD" "$C_WHITE" "$*" "$C_RESET"; }
warn() { printf '\n%s[NOTE] %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
die() { printf '\n%s[ERROR] %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }
ask() {
  local ask_label=$2 ask_default=${3:-} ask_input
  if [[ -n $ask_default ]]; then
    printf '%s > %s%s%s [%s]%s: ' "$C_RED" "$C_WHITE" "$ask_label" "$C_GRAY" "$ask_default" "$C_RESET"
    read -r ask_input || exit 1
    ask_input=${ask_input:-$ask_default}
  else
    printf '%s > %s%s%s: ' "$C_RED" "$C_WHITE" "$ask_label" "$C_RESET"
    read -r ask_input || exit 1
  fi
  printf -v "$1" '%s' "$ask_input"
}
confirm() {
  local answer
  printf '%s > %s%s%s (y/n)%s: ' "$C_RED" "$C_WHITE" "$1" "$C_GRAY" "$C_RESET"
  read -r answer || return 1
  [[ ${answer,,} == yes || ${answer,,} == y ]]
}
get_name() {
  while :; do
    ask NAME 'Tunnel name (lowercase letters, digits, hyphens)' 'main'
    [[ $NAME =~ ^[a-z][a-z0-9-]{0,19}$ ]] && break
    say 'Use up to 20 characters, starting with a lowercase letter.'
  done
  select_profile "$NAME"
}
select_profile() {
  [[ $1 =~ ^[a-z][a-z0-9-]{0,19}$ ]] || die 'Invalid tunnel name.'
  NAME=$1
  DIR=$BASE/$NAME
  UNIT=ssh-v2ray-$NAME.service
  ACCOUNT=svt-$NAME
  SNIPPET=$DROP/00-ssh-v2ray-$NAME.conf
}
get_port() {
  local answer
  while :; do
    ask answer "$2" "$3"
    if [[ $answer =~ ^[0-9]{1,5}$ ]] && (( 10#$answer >= 1 && 10#$answer <= 65535 )); then
      printf -v "$1" '%s' "$((10#$answer))"
      return
    fi
    say 'Enter a port number from 1 to 65535.'
  done
}
get_host() {
  local answer
  while :; do
    ask answer "$2" "${3:-}"
    if [[ $answer =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]; then
      printf -v "$1" '%s' "$answer"
      return
    fi
    say 'Enter an IPv4 address or hostname. IPv6 is not supported in this version.'
  done
}
get_mode() {
  if [[ -n ${QUICK_MODE:-} ]]; then MODE=$QUICK_MODE; return; fi
  say '1) Reverse: SSH initiator = Kharej; SSH receiver = Iran'
  say '2) Direct:  SSH initiator = Iran; SSH receiver = Kharej'
  local answer
  while :; do
    ask answer 'Mode' '1'
    case $answer in 1) MODE=reverse; return;; 2) MODE=direct; return;; esac
  done
}
need_runtime() {
  [[ $EUID == 0 ]] || die 'Run this script with sudo bash.'
  [[ -d /run/systemd/system ]] || die 'This script requires Linux with systemd running.'
  command -v systemctl >/dev/null || die 'systemctl is not installed.'
  mkdir -p "$BASE"
  chmod 700 "$BASE"
}
install_tools() {
  local role=$1
  say 'Installing missing tools automatically...'
  if command -v apt-get >/dev/null; then
    apt-get update
    local -a packages=(openssh-client iproute2 coreutils)
    if [[ $role == receiver ]]; then packages+=(openssh-server openssl passwd procps); fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  elif command -v dnf >/dev/null; then
    local -a packages=(openssh-clients iproute coreutils)
    if [[ $role == receiver ]]; then packages+=(openssh-server openssl shadow-utils procps-ng); fi
    dnf install -y "${packages[@]}"
  else
    die 'Automatic installation requires apt or dnf. Install the missing tools manually on this distribution.'
  fi
}
ensure_tools() {
  need_runtime
  local role=$1 cmd
  local -a required=(ssh ssh-keygen ssh-keyscan timeout ss) missing=()
  if [[ $role == receiver ]]; then required+=(openssl useradd userdel pkill); fi
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  if [[ $role == receiver ]] && ! command -v sshd >/dev/null && [[ ! -x /usr/sbin/sshd ]]; then
    missing+=(sshd)
  fi
  if (( ${#missing[@]} > 0 )); then
    warn "Missing tools: ${missing[*]}"
    install_tools "$role"
    for cmd in "${required[@]}"; do
      command -v "$cmd" >/dev/null || die "Automatic installation did not provide $cmd. Check the package manager output."
    done
    [[ $role != receiver ]] || find_sshd
    ok 'Required tools installed.'
  fi
}
need_client() {
  ensure_tools client
}
ensure_sshd_service() {
  local ssh_unit
  if systemctl cat ssh.service >/dev/null 2>&1; then
    ssh_unit=ssh.service
  elif systemctl cat sshd.service >/dev/null 2>&1; then
    ssh_unit=sshd.service
  else
    die 'OpenSSH server service was not found after dependency checks.'
  fi
  if ! systemctl is-enabled --quiet "$ssh_unit"; then systemctl enable "$ssh_unit"; fi
  if ! systemctl is-active --quiet "$ssh_unit"; then systemctl start "$ssh_unit"; fi
}
find_sshd() {
  SSHD=$(command -v sshd || true)
  [[ -n $SSHD ]] || SSHD=/usr/sbin/sshd
  [[ -x $SSHD ]] || die 'sshd is missing. Run tunnel Setup to install it automatically.'
}
reload_sshd() {
  if systemctl is-active --quiet ssh.service; then
    systemctl reload ssh.service
  elif systemctl is-active --quiet sshd.service; then
    systemctl reload sshd.service
  else
    die 'The SSH service is not running. Run tunnel Setup to prepare it automatically.'
  fi
}
make_key() {
  need_runtime
  need_client
  get_name
  mkdir -p "$DIR"
  if [[ ! -f $DIR/id_ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "ssh-v2ray-$NAME" -f "$DIR/id_ed25519"
  fi
  chmod 600 "$DIR/id_ed25519"
  [[ -f $DIR/id_ed25519.pub ]] || ssh-keygen -y -f "$DIR/id_ed25519" > "$DIR/id_ed25519.pub"
  show_key
}
show_key() {
  say 'COPY THE ENTIRE LINE BELOW to the other server:'
  printf '%s' "$C_GREEN"
  cat "$DIR/id_ed25519.pub"
  printf '%s' "$C_RESET"
  warn 'This is the PUBLIC key. Your private key stays on this server.'
}
write_receiver_snippet() {
  {
    printf '# Managed by ssh-v2ray-tunnel: %s\nMatch User %s\n' "$NAME" "$ACCOUNT"
    printf '    AuthenticationMethods publickey\n    PubkeyAuthentication yes\n    PasswordAuthentication no\n    KbdInteractiveAuthentication no\n'
    printf '    PermitTTY no\n    X11Forwarding no\n    AllowAgentForwarding no\n    AllowStreamLocalForwarding no\n    PermitTunnel no\n    MaxSessions 0\n'
    if [[ $MODE == reverse ]]; then
      printf '    AllowTcpForwarding remote\n    GatewayPorts clientspecified\n    PermitListen %s\n    PermitOpen none\n' "$TARGET"
    else
      printf '    AllowTcpForwarding local\n    GatewayPorts no\n    PermitOpen %s\n    PermitListen none\n' "$TARGET"
    fi
    printf 'Match all\n'
  } > "$SNIPPET"
}
build_ssh_args() {
  local flag forward
  if [[ $MODE == reverse ]]; then flag=-R; else flag=-L; fi
  forward=0.0.0.0:$LISTEN_PORT:$BACKEND:$V2_PORT
  SSH_ARGS=( -F /dev/null -NT -i "$DIR/id_ed25519" -p "$SSH_PORT"
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
    -o "UserKnownHostsFile=$DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null
    -o ExitOnForwardFailure=yes -o ConnectTimeout=10
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes
    -o Compression=no -o LogLevel=VERBOSE "$flag" "$forward" "$ACCOUNT@$REMOTE" )
}
write_unit() {
  local output=$1 ssh_path
  ssh_path=$(command -v ssh)
  {
    printf '[Unit]\nDescription=SSH V2Ray tunnel %s (%s)\nWants=network-online.target\nAfter=network-online.target\nStartLimitIntervalSec=0\n\n' "$NAME" "$MODE"
    printf '[Service]\nType=simple\nUser=root\nExecStart=%s' "$ssh_path"
    printf ' %s' "${SSH_ARGS[@]}"
    printf '\nRestart=always\nRestartSec=5\nTimeoutStopSec=10\nUMask=0077\n'
    printf 'NoNewPrivileges=yes\nPrivateTmp=yes\nProtectSystem=strict\nProtectHome=yes\n\n[Install]\nWantedBy=multi-user.target\n'
  } > "$output"
}
receiver() {
  need_runtime
  ensure_tools receiver
  find_sshd
  ensure_sshd_service
  get_name
  get_mode
  [[ ! -f $DIR/initiator ]] || die 'This name is already used for an initiator on this server. Choose another name.'
  if [[ -f $DIR/receiver ]]; then
    [[ $(cat "$DIR/receiver") == "$MODE" ]] || die 'This profile uses the other mode. Use another name.'
    ok "This server is already prepared for $MODE (account: $ACCOUNT)."
    [[ ! -f $SNIPPET ]] || cat "$SNIPPET"
    if [[ -f /home/$ACCOUNT/.ssh/authorized_keys ]]; then
      say 'Fingerprint of the public key currently authorized here:'
      ssh-keygen -lf "/home/$ACCOUNT/.ssh/authorized_keys"
    fi
    show_host_fingerprints
    say 'Continue Setup on the other server using the same tunnel name.'
    return 0
  fi
  ! id "$ACCOUNT" >/dev/null 2>&1 || die "Account $ACCOUNT already exists. Choose another tunnel name."
  [[ ! -e $SNIPPET ]] || die 'An SSH configuration file with this name already exists. Choose another name.'
  if [[ $MODE == reverse ]]; then
    get_port LISTEN_PORT 'User entry port on Iran' '8443'
    get_port SSH_PORT 'SSH port of this Iran server' '22'
    [[ $LISTEN_PORT != "$SSH_PORT" ]] || die 'The user entry port must differ from the SSH port.'
    (( LISTEN_PORT >= 1024 )) || die 'The restricted account requires a reverse port of 1024 or higher, e.g. 8443.'
    if command -v ss >/dev/null && [[ -n $(ss -H -ltn "sport = :$LISTEN_PORT") ]]; then
      die 'The entry port is already in use. Choose another port.'
    fi
    TARGET=0.0.0.0:$LISTEN_PORT
  else
    get_host BACKEND 'V2Ray address as seen from this Kharej server' '127.0.0.1'
    get_port V2_PORT 'V2Ray TCP port on Kharej' '443'
    get_port SSH_PORT 'SSH port of this Kharej server' '22'
    TARGET=$BACKEND:$V2_PORT
  fi
  if [[ $MODE == reverse ]]; then
    say 'First run: 1) Setup Reverse -> 2) Kharej, on the Kharej server.'
  else
    say 'First run: 2) Setup Direct -> 1) Iran, on the Iran server.'
  fi
  say 'It displays a public key. Copy that entire line here.'
  ask PUBLIC_KEY 'Paste the complete ssh-ed25519 public key line'
  [[ $PUBLIC_KEY =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || die 'Enter a valid Ed25519 public key.'
  mkdir -p "$DIR" "$DROP"
  printf '%s\n' "$PUBLIC_KEY" > "$DIR/public-key.check"
  if ! ssh-keygen -l -f "$DIR/public-key.check"; then
    rm -f "$DIR/public-key.check"
    die 'The public key is invalid.'
  fi
  rm -f "$DIR/public-key.check"
  say "Restricted account: $ACCOUNT | Mode: $MODE | Allowed destination: $TARGET"
  confirm 'Set up this SSH receiver?' || return 0

  # Keep the account usable for pubkey auth, but give it an unknown random password.
  # Password auth is also disabled in the account's Match section.
  local random_password password_hash home_dir backup
  random_password=$(openssl rand -hex 32)
  password_hash=$(printf '%s' "$random_password" | openssl passwd -6 -stdin)
  unset random_password
  home_dir=/home/$ACCOUNT
  [[ ! -e $home_dir ]] || die 'The account home directory already exists. Choose another name.'
  useradd --system --create-home --home-dir "$home_dir" --shell /bin/sh --password "$password_hash" "$ACCOUNT"
  unset password_hash
  printf '%s\n' "$MODE" > "$DIR/receiver"
  mkdir -p "$home_dir/.ssh"
  if [[ $MODE == reverse ]]; then
    printf 'restrict,port-forwarding,permitlisten="%s" %s\n' "$TARGET" "$PUBLIC_KEY" > "$home_dir/.ssh/authorized_keys"
  else
    printf 'restrict,port-forwarding,permitopen="%s" %s\n' "$TARGET" "$PUBLIC_KEY" > "$home_dir/.ssh/authorized_keys"
  fi
  chmod 700 "$home_dir" "$home_dir/.ssh"
  chmod 600 "$home_dir/.ssh/authorized_keys"
  chown -R "$ACCOUNT:$(id -gn "$ACCOUNT")" "$home_dir"
  if command -v restorecon >/dev/null; then restorecon -R "$home_dir"; fi
  write_receiver_snippet
  # Ensure drop-ins are read in global context, before any existing Match blocks.
  backup=$DIR/sshd_config.before
  cp -p /etc/ssh/sshd_config "$backup"
  if ! head -n 1 /etc/ssh/sshd_config | grep -Fxq 'Include /etc/ssh/sshd_config.d/*.conf'; then
    { printf 'Include /etc/ssh/sshd_config.d/*.conf\n'; cat "$backup"; } > "$DIR/sshd_config.new"
    cat "$DIR/sshd_config.new" > /etc/ssh/sshd_config
    rm -f "$DIR/sshd_config.new"
  fi
  if ! "$SSHD" -t; then
    cp -p "$backup" /etc/ssh/sshd_config
    rm -f "$SNIPPET"
    userdel -r "$ACCOUNT" 2>/dev/null || true
    rm -f "$DIR/receiver"
    die 'SSH configuration validation failed. SSH changes were rolled back.'
  fi
  reload_sshd
  ok "Receiver ready. Tunnel: $NAME | SSH user: $ACCOUNT | SSH port: $SSH_PORT"
  show_host_fingerprints
  say "Allow SSH port $SSH_PORT/TCP in the firewall."
  [[ $MODE != reverse ]] || say "Also allow user entry port $LISTEN_PORT/TCP in the Iran firewall."
  say 'Continue Setup on the other server, with the same name.'
}
show_host_fingerprints() {
  say 'Host key fingerprints of this server. Compare these on the SSH initiator:'
  local host_key
  for host_key in /etc/ssh/ssh_host_*_key.pub; do
    [[ -f $host_key ]] && ssh-keygen -lf "$host_key"
  done
}
trust_host() {
  local scanned=$DIR/known_hosts.scan
  say "Fetching host key fingerprints from $REMOTE on port $SSH_PORT ..."
  if ! ssh-keyscan -T 10 -p "$SSH_PORT" "$REMOTE" > "$scanned" 2> "$DIR/keyscan.log"; then
    cat "$DIR/keyscan.log"
    die 'Failed to fetch host keys. Check the network path and SSH port.'
  fi
  [[ -s $scanned ]] || die 'No host key was received.'
  ssh-keygen -lf "$scanned"
  say 'Compare these fingerprints with the receiver output. keyscan alone does not verify identity.'
  if ! confirm 'Do the fingerprints match the SSH receiver?'; then
    rm -f "$scanned"
    return 1
  fi
  mv "$scanned" "$DIR/known_hosts"
  chmod 600 "$DIR/known_hosts"
}
initiator() {
  need_runtime
  need_client
  get_name
  get_mode
  [[ ! -f $DIR/receiver ]] || die 'This name is already used for a receiver on this server. Choose another name.'
  [[ ! -f $DIR/initiator ]] || die 'This tunnel already exists. Remove it from the menu first.'
  mkdir -p "$DIR"
  if [[ ! -f $DIR/id_ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "ssh-v2ray-$NAME" -f "$DIR/id_ed25519"
  fi
  [[ -f $DIR/id_ed25519.pub ]] || ssh-keygen -y -f "$DIR/id_ed25519" > "$DIR/id_ed25519.pub"
  show_key
  if [[ $MODE == reverse ]]; then
    say 'On Iran: run 1) Setup Reverse -> 1) Iran, and paste this key.'
  else
    say 'On Kharej: run 2) Setup Direct -> 2) Kharej, and paste this key.'
  fi
  say 'You can keep this terminal open while preparing the other server.'
  confirm 'Is the other server ready with this public key?' || return 0
  if [[ $MODE == reverse ]]; then
    get_host REMOTE 'Iran server IPv4 address or hostname'
  else
    get_host REMOTE 'Kharej server IPv4 address or hostname'
  fi
  get_port SSH_PORT 'SSH port of the receiver' '22'
  get_port LISTEN_PORT 'User entry port on Iran' '8443'
  if [[ $MODE == reverse ]]; then
    (( LISTEN_PORT >= 1024 )) || die 'The reverse port must be 1024 or higher.'
    [[ $LISTEN_PORT != "$SSH_PORT" ]] || die 'The user entry port must differ from the Iran SSH port.'
  elif command -v ss >/dev/null && [[ -n $(ss -H -ltn "sport = :$LISTEN_PORT") ]]; then
    die 'The user entry port is already in use.'
  fi
  get_host BACKEND 'V2Ray address as seen from the Kharej server' '127.0.0.1'
  warn 'Enter the VLESS inbound port, not the web panel port.'
  get_port V2_PORT 'V2Ray TCP port on Kharej' '443'
  say "Mode: $MODE | Iran entry: $LISTEN_PORT/TCP | Kharej V2Ray: $BACKEND:$V2_PORT"
  if [[ $MODE == direct ]]; then
    say 'The V2Ray address and port must exactly match the destination allowed on the receiver.'
  fi
  trust_host || return 0
  build_ssh_args
  # Save BEFORE testing so failures remain diagnosable from the menu.
  save_summary
  connection_test || return 1
  write_unit "/etc/systemd/system/$UNIT"
  printf '%s\n' "$MODE" > "$DIR/initiator"
  systemctl daemon-reload
  systemctl enable --now "$UNIT"
  sleep 2
  if systemctl is-active --quiet "$UNIT"; then
    ok 'Tunnel service is running and will restart automatically.'
  else
    warn 'The service did not stay running. Recent logs:'
    journalctl -u "$UNIT" -n 40 --no-pager
  fi
  say "Client address: IRAN_IP | Client port: $LISTEN_PORT | UUID: your existing VLESS UUID"
  warn "Allow $LISTEN_PORT/TCP in the Iran firewall. Test with a real VLESS client."
}
save_summary() {
  printf 'Mode=%s\nRemote=%s\nSSHPort=%s\nIranPort=%s\nBackend=%s:%s\n' "$MODE" "$REMOTE" "$SSH_PORT" "$LISTEN_PORT" "$BACKEND" "$V2_PORT" > "$DIR/summary"
}
explain_failure() {
  local result=$1
  printf '\n%s[FAILED] SSH test exit code: %s%s\n' "$C_RED" "$result" "$C_RESET"
  if [[ $result == 124 || $result == 137 ]]; then
    warn 'Time limit reached. This is a timeout, not proof of a wrong public key.'
  fi
  if grep -q 'Permission denied' "$DIR/test.log"; then
    warn 'Authentication rejected. Check that the receiver has THIS public key, and permits the tunnel account.'
  elif grep -q 'REMOTE HOST IDENTIFICATION HAS CHANGED\|Host key verification failed' "$DIR/test.log"; then
    warn 'Host identity check failed. Compare host fingerprints before running Setup again.'
  elif grep -q 'remote port forwarding failed\|Address already in use' "$DIR/test.log"; then
    warn 'Forwarding rejected or the port is occupied. Check the Iran entry port and receiver rules.'
  elif ! grep -q 'Connection established' "$DIR/test.log"; then
    warn 'TCP connection did not complete. Check the SSH address, port, firewall and network path.'
  elif ! grep -q 'Remote protocol version' "$DIR/test.log"; then
    warn 'TCP connected, but the SSH banner was not received. Check sshd and the network path.'
  elif ! grep -q 'SSH2_MSG_NEWKEYS received' "$DIR/test.log"; then
    warn 'SSH stalled during key exchange. Check the receiver SSH log and packet loss / path MTU.'
  elif ! grep -q 'Authenticated to' "$DIR/test.log"; then
    warn 'Key exchange completed, but authentication did not complete. Check the receiver SSH log.'
  else
    warn 'Authentication completed. Check forwarding permission and the requested entry port.'
  fi
  say 'Last 80 lines of the SSH debug log:'
  tail -n 80 "$DIR/test.log"
  warn "Full log: $DIR/test.log"
  say 'Use menu 4 to view logs. To retry, run Setup Reverse or Setup Direct again.'
}
connection_test() {
  say "Testing SSH -> $ACCOUNT@$REMOTE:$SSH_PORT (maximum 30 seconds)..."
  local control=$DIR/test-control-$$
  local result=0 test_pid
  : > "$DIR/test.log"
  timeout --signal=TERM --kill-after=3s 30s ssh -vvv -E "$DIR/test.log" -M -S "$control" -f "${SSH_ARGS[@]}" > "$DIR/test.stderr" 2>&1 &
  test_pid=$!
  while kill -0 "$test_pid" 2>/dev/null; do
    printf '%s.%s' "$C_YELLOW" "$C_RESET"
    sleep 1
  done
  printf '\n'
  wait "$test_pid" || result=$?
  cat "$DIR/test.stderr" >> "$DIR/test.log"
  if [[ $result != 0 ]]; then
    timeout 5s ssh -S "$control" -O exit -p "$SSH_PORT" "$ACCOUNT@$REMOTE" 2>/dev/null || true
    explain_failure "$result"
    return 1
  fi
  timeout 5s ssh -S "$control" -O exit -p "$SSH_PORT" "$ACCOUNT@$REMOTE" >/dev/null 2>&1
  ok 'SSH authentication and port forwarding succeeded.'
}
list_profiles() {
  need_runtime
  local profile name role mode entry state field value choice index row_color
  local border='+----+----------------------+-----------+---------+-----------+--------------+'
  local -a rows=()
  while :; do
    rows=()
    say 'TUNNELS ON THIS SERVER'
    printf '%s%s\n' "$C_CYAN" "$border"
    printf '| %-2s | %-20s | %-9s | %-7s | %-9s | %-12s |\n' '#' 'Name' 'Role' 'Mode' 'Iran port' 'Status'
    printf '%s%s\n' "$border" "$C_RESET"
    for profile in "$BASE"/*; do
      [[ -d $profile && ! -L $profile ]] || continue
      name=${profile##*/}
      [[ $name =~ ^[a-z][a-z0-9-]{0,19}$ ]] || continue
      rows+=("$name")
      mode='-' entry='-' role='Key only' state='Not set up'
      if [[ -f $profile/summary ]]; then
        role='Pending' state='Incomplete'
        while IFS='=' read -r field value; do
          case $field in Mode) mode=$value;; IranPort) entry=$value;; esac
        done < "$profile/summary"
      fi
      if [[ -f $profile/initiator ]]; then
        role='Initiator' mode=$(cat "$profile/initiator")
        state=$(systemctl is-active "ssh-v2ray-$name.service" 2>/dev/null || true)
        case $state in active|inactive|failed|activating|deactivating) ;; *) state='unknown';; esac
      elif [[ -f $profile/receiver ]]; then
        role='Receiver' mode=$(cat "$profile/receiver") state='Configured'
        if [[ -f $DROP/00-ssh-v2ray-$name.conf ]]; then
          while read -r field value; do
            if [[ $field == PermitListen && $value == 0.0.0.0:* ]]; then entry=${value##*:}; fi
          done < "$DROP/00-ssh-v2ray-$name.conf"
        else
          state='Incomplete'
        fi
      fi
      [[ $mode == direct || $mode == reverse ]] || mode='-'
      [[ $entry =~ ^[0-9]{1,5}$ ]] || entry='-'
      row_color=$C_YELLOW
      [[ $state != active && $state != Configured ]] || row_color=$C_GREEN
      [[ $state != failed ]] || row_color=$C_RED
      printf '%s| %-2s | %-20s | %-9s | %-7s | %-9s | %-12s |%s\n' "$row_color" "${#rows[@]}" "$name" "$role" "$mode" "$entry" "$state" "$C_RESET"
    done
    printf '%s%s%s\n' "$C_CYAN" "$border" "$C_RESET"
    if (( ${#rows[@]} == 0 )); then
      say 'No tunnels have been configured yet.'
      return 0
    fi
    warn 'Receiver = prepared here; its tunnel service runs on the other server.'
    printf '\n  Enter a row number to delete that tunnel.\n  r = Refresh table | 0 = Back\n'
    ask choice 'Delete row / action' '0'
    case ${choice,,} in
      0) return 0;;
      r) continue;;
    esac
    if [[ ! $choice =~ ^[0-9]{1,6}$ ]]; then
      warn 'Enter a valid row number, r, or 0.'
      continue
    fi
    index=$((10#$choice))
    if (( index < 1 || index > ${#rows[@]} )); then
      warn 'That row does not exist.'
      continue
    fi
    remove_profile "${rows[index-1]}"
  done
}
manage() {
  need_runtime
  get_name
  [[ -d $DIR ]] || die 'No profile with this name.'
  if [[ -f $DIR/receiver ]]; then
    ok 'This server is the SSH receiver. The tunnel service runs on the other server.'
    [[ ! -f $SNIPPET ]] || cat "$SNIPPET"
    say 'Recent SSH receiver logs (last 15 minutes):'
    journalctl -u ssh.service -u sshd.service --since '15 minutes ago' -n 60 --no-pager
    return 0
  fi
  if [[ ! -f $DIR/initiator ]]; then
    warn 'Setup is incomplete. No tunnel service was created yet.'
    [[ ! -f $DIR/summary ]] || cat "$DIR/summary"
    if [[ -s $DIR/test.log ]]; then
      say 'Last setup attempt:'
      tail -n 80 "$DIR/test.log"
    else
      warn 'No SSH debug log yet. Run Setup Reverse or Setup Direct first.'
    fi
    return 0
  fi
  say '1) Status  2) Service logs  3) Restart  4) Stop  5) Start  6) Last setup log'
  local action
  ask action 'Option' '1'
  case $action in
    1) systemctl --no-pager --full status "$UNIT" || true;;
    2) journalctl -u "$UNIT" -n 80 --no-pager;;
    3) systemctl restart "$UNIT";;
    4) systemctl stop "$UNIT"; say 'Tunnel stopped. To disable startup after reboot, also run systemctl disable.';;
    5) systemctl start "$UNIT";;
    6) [[ ! -f $DIR/test.log ]] || tail -n 80 "$DIR/test.log";;
    *) say 'Invalid option';;
  esac
}
remove_profile() {
  need_runtime
  if [[ -n ${1:-} ]]; then select_profile "$1"; else get_name; fi
  [[ -d $DIR ]] || die 'This name does not exist.'
  say "Removing $NAME affects only this server. Remove the other side separately."
  confirm "Delete tunnel '$NAME', including its service, private key and dedicated account?" || return 0
  if [[ -f $DIR/receiver ]]; then
    find_sshd
    [[ -f $SNIPPET ]] || die 'The dedicated SSH configuration file is missing. Review the configuration before removing it manually.'
    cp -p "$SNIPPET" "$DIR/snippet.before-delete"
    rm -f "$SNIPPET"
    if ! "$SSHD" -t; then
      cp -p "$DIR/snippet.before-delete" "$SNIPPET"
      die 'SSH configuration is invalid. Removal was cancelled.'
    fi
    reload_sshd
    # Existing SSH connections survive a reload. Terminate only this dedicated account.
    pkill -u "$ACCOUNT" 2>/dev/null || true
    if id "$ACCOUNT" >/dev/null 2>&1; then userdel -r "$ACCOUNT"; fi
  fi
  if [[ -f $DIR/initiator ]]; then
    systemctl disable --now "$UNIT"
    rm -f "/etc/systemd/system/$UNIT"
    systemctl daemon-reload
  fi
  [[ $DIR == "$BASE/"* && $DIR != "$BASE/" ]] || die 'Invalid removal path.'
  rm -rf -- "$DIR"
  say 'Profile removed. Installed prerequisites and the shared SSH Include remain.'
}
quick_setup() {
  QUICK_MODE=$1
  local location
  say 'Which server are you running this on?'
  printf '  1) Iran\n  2) Kharej\n'
  while :; do
    ask location 'This server' '1'
    [[ $location == 1 || $location == 2 ]] && break
  done
  if [[ $QUICK_MODE == reverse && $location == 1 ]] || [[ $QUICK_MODE == direct && $location == 2 ]]; then
    say 'This server receives SSH. The other server starts the tunnel.'
    receiver
  else
    say 'This server starts SSH. First copy its public key to the other server.'
    initiator
  fi
}
run_action() {
  local action_result
  # A failed setup must return to the menu; keep errexit enabled inside the action.
  set +e
  ( set -Eeuo pipefail; "$@" )
  action_result=$?
  set -e
  if (( action_result != 0 )); then
    warn 'The action did not complete. You can view logs or retry from this menu.'
  fi
  local pause_answer
  printf '\n%sPress Enter to return to the menu...%s' "$C_YELLOW" "$C_RESET"
  read -r pause_answer || exit 0
}
menu_item() {
  printf '  %s%2s)%s %s%s%-21s%s %s%s%s\n' \
    "$C_RED" "$1" "$C_RESET" "$C_BOLD" "$C_WHITE" "$2" "$C_RESET" "$C_GRAY" "${3:-}" "$C_RESET"
}
render_menu() {
  if [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]]; then printf '\033[H\033[2J'; fi
  printf '\n%s%s' "$C_BOLD" "$C_RED"
  cat <<'BANNER'
   ____  ____  _   _
  / ___|/ ___|| | | |
  \___ \\___ \| |_| |
   ___) |___) |  _  |
  |____/|____/|_| |_|
BANNER
  printf '%s\n  %s%sSSH REVERSE TUNNEL%s  %sv2%s\n' "$C_RESET" "$C_BOLD" "$C_WHITE" "$C_RESET" "$C_RED" "$C_RESET"
  printf '  %sDirect & Reverse | VLESS / Xray | TCP%s\n\n' "$C_GRAY" "$C_RESET"
  printf '%s---------------------------------------------------------------%s\n\n' "$C_GRAY" "$C_RESET"
  menu_item 1 'Setup Reverse' 'Kharej connects to Iran'
  menu_item 2 'Setup Direct' 'Iran connects to Kharej'
  menu_item 3 'Manage Tunnels' 'table, status and deletion'
  menu_item 4 'Status & Logs' 'view logs, start, stop, restart'
  menu_item 5 'Public Key' 'generate or copy your public key'
  menu_item 0 'Exit' 'close this menu'
  printf '\n%s---------------------------------------------------------------%s\n' "$C_GRAY" "$C_RESET"
  printf '  %sGitHub: Mehdi81030/ssh-reverse-tunnel%s\n\n' "$C_GRAY" "$C_RESET"
}
main() {
  need_runtime
  local choice
  while :; do
    render_menu
    ask choice 'Select' '0'
    case $choice in
      1) run_action quick_setup reverse;; 2) run_action quick_setup direct;;
      3) run_action list_profiles;; 4) run_action manage;;
      5) run_action make_key;; 0) exit 0;;
      *) say 'Invalid option';;
    esac
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
