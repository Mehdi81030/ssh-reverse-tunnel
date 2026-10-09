#!/usr/bin/env bash
set -Eeuo pipefail
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$TEST_DIR/../ssh-tunnel.sh" --no-color
scratch=$(mktemp -d /tmp/svt-link.XXXXXX)
trap '[[ $scratch == /tmp/svt-link.* ]] && rm -rf -- "$scratch"' EXIT
BASE=$scratch/profiles
mkdir -p "$BASE"
select_profile example
mkdir -p "$DIR"
ssh-keygen -q -t ed25519 -N '' -C 'comment with spaces' -f "$DIR/id_ed25519"
# A stale .pub file must not be exported instead of the actual private key's public part.
printf 'stale-public-key\n' > "$DIR/id_ed25519.pub"
for MODE in reverse direct; do
  REMOTE=receiver.example.org SSH_PORT=2299 LISTEN_PORT=60250 V2_PORT=443
  make_setup_link
  link=$SETUP_LINK
  [[ $LINK_NAME == example && $LINK_MODE == "$MODE" && $LINK_RECEIVER == receiver.example.org ]]
  [[ $LINK_SSH_PORT == 2299 && $LINK_IRAN_PORT == 60250 && $LINK_CONFIG_PORT == 443 ]]
  actual=$(ssh-keygen -y -f "$DIR/id_ed25519" | awk '{print $1,$2}')
  [[ $LINK_PUBLIC_KEY == "$actual ssh-v2ray-example" ]]
  show_setup_link > "$scratch/output.txt"
  grep -q 'bash ssh-tunnel.sh --import' "$scratch/output.txt"
  ! grep -q 'PRIVATE KEY\|stale-public-key' "$scratch/output.txt"
  echo "PASS $MODE export: address/ports/name/key round-trip; actual public key exported"
done
reject() {
  local payload=$1 bad
  bad=ssh-tunnel://v1/$(printf '%s' "$payload" | encode_setup_data)
  if (parse_setup_link "$bad") > "$scratch/rejected.txt" 2>&1; then exit 1; fi
}
valid=$(printf 'Kind=receiver\nName=example\nMode=reverse\nReceiver=receiver.example.org\nSSHPort=2299\nIranPort=60250\nConfigPort=443\nPublicKey=%s' "$LINK_PUBLIC_KEY")
reject "$valid"$'\nName=duplicate'
reject "$valid"$'\nCommand=touch /tmp/do-not-run'
reject "${valid/Name=example/Name=..\/bad}"
reject "${valid/SSHPort=2299/SSHPort=65536}"
reject "${valid/IranPort=60250/IranPort=2299}"
reject "${valid/PublicKey=ssh-ed25519/PublicKey=invalid}"
reject "${valid/ConfigPort=443/ConfigPort=\$(touch injected)}"
if (parse_setup_link 'ssh-tunnel://v1/!invalid') > /dev/null 2>&1; then exit 1; fi
echo 'PASS input validation: bad/duplicate/unknown fields and shell expressions rejected'
# Import forwards the parsed settings into receiver setup without requesting them again.
need_runtime() { :; }
ensure_tools() { :; }
receiver() {
  [[ $SETUP_LINK_IMPORT == 1 && $LINK_NAME == example && $LINK_IRAN_PORT == 60250 ]]
  printf 'called\n' > "$scratch/import-called"
}
import_setup_link "$link" > "$scratch/import.txt"
[[ -f $scratch/import-called ]]
echo 'PASS import: validated settings reach the receiver setup flow'
