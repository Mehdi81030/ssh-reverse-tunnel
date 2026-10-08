#!/usr/bin/env bash
# Dependency and service behavior tests; package managers and systemctl are mocked.
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-deps.XXXXXX)
trap '[[ $scratch == /tmp/svt-deps.* ]] && rm -rf -- "$scratch"' EXIT
calls=$scratch/calls
: > "$calls"
TOOLS_READY=1
MISSING_CMD=''
PACKAGE_MANAGER=apt
need_runtime() { :; }
find_sshd() { SSHD=/mock/sshd; }
command() {
  if [[ ${1:-} == -v ]]; then
    case $2 in
      apt-get) [[ $PACKAGE_MANAGER == apt ]]; return;;
      dnf) [[ $PACKAGE_MANAGER == dnf ]]; return;;
    esac
    [[ $TOOLS_READY == 1 && $2 != "$MISSING_CMD" ]]
    return
  fi
  builtin command "$@"
}
apt-get() {
  printf 'apt %s\n' "$*" >> "$calls"
  if [[ $1 == install ]]; then TOOLS_READY=1; MISSING_CMD=''; fi
}
dnf() {
  printf 'dnf %s\n' "$*" >> "$calls"
  TOOLS_READY=1; MISSING_CMD=''
}

ensure_tools receiver
[[ ! -s $calls ]]
echo 'PASS dependencies already present: no package manager invoked'

TOOLS_READY=0
ensure_tools client
grep -q '^apt update$' "$calls"
grep -q '^apt install -y openssh-client iproute2 coreutils$' "$calls"
! grep -q 'openssh-server' "$calls"
echo 'PASS missing client tools: installed automatically with apt; no server packages requested'

: > "$calls"
MISSING_CMD=openssl
ensure_tools receiver
grep -q 'openssh-server openssl passwd procps' "$calls"
echo 'PASS receiver tools: server and account packages included'

: > "$calls"
TOOLS_READY=0
PACKAGE_MANAGER=dnf
ensure_tools receiver
grep -q '^dnf install -y openssh-clients iproute coreutils openssh-server openssl shadow-utils procps-ng$' "$calls"
echo 'PASS dnf: correct receiver package names'

: > "$calls"
TOOLS_READY=0
PACKAGE_MANAGER=none
if (ensure_tools client) > "$scratch/unsupported.txt" 2>&1; then
  echo 'ERROR: unsupported package manager did not fail'; exit 1
fi
grep -q 'requires apt or dnf' "$scratch/unsupported.txt"
[[ ! -s $calls ]]
echo 'PASS unsupported distribution: clear error; no package operations'

SSH_RUNNING=1
SSH_ENABLED=1
SSH_UNIT=ssh.service
systemctl() {
  case $1 in
    cat) [[ $2 == "$SSH_UNIT" ]];;
    is-active) [[ $SSH_RUNNING == 1 ]];;
    is-enabled) [[ $SSH_ENABLED == 1 ]];;
    enable) printf 'enable %s\n' "$2" >> "$calls"; SSH_ENABLED=1;;
    start) printf 'start %s\n' "$2" >> "$calls"; SSH_RUNNING=1;;
    *) echo 'Unexpected service operation'; return 1;;
  esac
}
ensure_sshd_service
[[ ! -s $calls ]]
SSH_RUNNING=0
SSH_ENABLED=0
SSH_UNIT=sshd.service
ensure_sshd_service
grep -q '^enable sshd.service$' "$calls"
grep -q '^start sshd.service$' "$calls"
! grep -q 'restart\|stop' "$calls"
echo 'PASS receiver service: existing active service untouched; inactive sshd enabled and started'
