# SSH Reverse Tunnel

A colorful Bash menu for managing **reverse and direct SSH port-forwarding tunnels** between two Linux servers. Supports V2Ray/Xray TCP inbounds and other TCP services.

[راهنمای فارسی](README-fa.md)

## Download and run

Run on both servers:

```bash
curl -fL --retry 3 -o ssh-tunnel.sh https://raw.githubusercontent.com/Mehdi81030/ssh-reverse-tunnel/main/ssh-tunnel.sh
sudo bash ssh-tunnel.sh
```

Or clone this repository and run `sudo bash ssh-tunnel.sh`. Force terminal colors with `--color`; disable them with `--no-color` or `NO_COLOR=1`.

## Features

- Guided setup: choose Reverse or Direct, then choose Iran or Abroad.
- Dedicated SSH account limited to the requested forwarding operation, with shell sessions disabled.
- Reuses existing Ed25519 keys and asks you to compare host key fingerprints.
- A systemd service starts after boot and reconnects after disconnection.
- Multiple independent tunnels, each with its own profile name and Iran entry port.
- A tunnel table with row selection and a named confirmation for deletion.
- SSH debug logs and retry settings are saved even when setup fails.
- Status and logs work on both receivers and initiators.

## Requirements

Linux with systemd running, Bash, root access, and a recent OpenSSH client/server. Local checks used Ubuntu and OpenSSH 9.6. Ubuntu 22.04/24.04 or Debian 12 are suggested starting points. Menu option **7** installs dependencies using `apt` or `dnf`; other distributions require manual dependency installation.

Forwarding is **TCP only**. The script does not configure firewall rules, change network MTU, or modify your V2Ray/Xray configuration. Independent UDP forwarding is not supported.

## Choose the direction

| Mode | SSH connection starts on | SSH receiver | Client connects to |
|---|---|---|---|
| Reverse | Abroad | Iran | Iran IP and entry port |
| Direct | Iran | Abroad | Iran IP and entry port |

In either mode, the backend V2Ray/Xray service runs on Abroad. These are SSH port-forwarding tunnels, not layer-3 VPNs.

```text
Client -> Iran:8443 -> SSH tunnel -> Abroad:127.0.0.1:443 -> VLESS
```

Use the VLESS **inbound port**, not the web panel port. The Iran entry port and the backend port may differ. The restricted account requires reverse entry ports to be **1024 or higher**.

## Reverse setup

1. Install prerequisites with option **7** on both machines if needed.
2. On **Abroad**, choose **1: Setup Reverse**, then **2: Abroad**. Choose a tunnel name, for example `main`.
3. Copy the entire displayed `ssh-ed25519 ...` public key line. Keep this terminal open.
4. On **Iran**, choose **1: Setup Reverse**, then **1: Iran**. Use the same tunnel name, enter the Iran entry port and actual Iran SSH port, and paste the public key.
5. Return to Abroad and confirm that Iran is ready. Enter the Iran address, SSH port, Iran entry port, backend address (usually `127.0.0.1`) and actual VLESS inbound port.
6. Compare the displayed host key fingerprints with the Iran output. Confirm only if they match.
7. After the SSH test succeeds, the service is installed. Configure the client with the Iran IP and entry port, keeping the backend VLESS UUID and protocol settings.

Iran must allow its SSH port and client entry port in the host and provider firewalls. Abroad must be able to establish an SSH connection to Iran and transfer data.

## Direct setup

Choose **2: Setup Direct** on both servers. Iran generates the public key; Abroad registers it. Iran then starts the SSH connection to Abroad. Use the same profile name, and enter the exact same backend address and port on both sides.

Abroad must allow its SSH port, and Iran must allow the client entry port. The backend must be reachable from the Abroad host; for Docker deployments, use the port published on the host.

## Menu and tunnel table

| Option | Action |
|---|---|
| 1 | Set up Reverse |
| 2 | Set up Direct |
| 3 | Tunnel table / Delete |
| 4 | Status / Logs / Start / Stop |
| 5 | Retry SSH test / finish setup |
| 6 | Show public key |
| 7 | Install prerequisites |
| 0 | Exit |

Option **3** shows the profile name, local role, mode, Iran entry port (when known), and local status. Enter a row number to delete that profile and confirm its name. The table refreshes after deletion; enter `r` to refresh or `0` to return. Deletion affects this server only. Remove the matching profile on the other server separately.

`Configured` means the receiver's local configuration is prepared; the actual tunnel service runs on the initiator. `active` means the local service is running. Test with a real client to confirm end-to-end service health.

For multiple Abroad servers, use a different tunnel name and Iran entry port for each. Backend ports may be identical on separate servers. This does not provide automatic load balancing or failover between backends.

## Troubleshooting

Setup uses a 30-second timeout and prints the last 80 lines of SSH debug output on failure. Exit code **124** means the test reached its time limit; it does not identify the cause by itself. Settings are saved before testing, so option **5** can retry without re-entering everything. Stop an active service using option **4** before retesting its forwarding port.

Option **4** shows setup logs even if no tunnel service was created. On the receiver it shows SSH service logs and account configuration. If `AllowUsers`, `AllowGroups`, `DisableForwarding` or other SSH restrictions are configured, ensure the dedicated tunnel account is permitted. Entering an SSH port in this script does not change sshd's listening port.

For profile `main`:

```bash
tail -n 80 /etc/ssh-v2ray-tunnel/main/test.log
journalctl -u ssh-v2ray-main.service -n 80 --no-pager
systemctl status ssh-v2ray-main.service
```

The script requires a working ordinary SSH/TCP path. It does not guarantee a fix for packet loss, path-MTU issues or network filtering. A successful setup test confirms SSH authentication and port-forward creation; backend availability and capacity still require testing with real traffic.

## Files and behavior

- Profile files and keys: `/etc/ssh-v2ray-tunnel/NAME/`.
- Receiver account: `svt-NAME`, home directory `/home/svt-NAME`.
- Receiver SSH settings: `/etc/ssh/sshd_config.d/00-ssh-v2ray-NAME.conf`.
- Initiator service: `ssh-v2ray-NAME.service`.
- The main SSH configuration is backed up before adding its drop-in Include. `sshd -t` validates changes before reload; failed validation restores the main configuration.
- Keepalives run every 15 seconds; after three missed responses, SSH exits. systemd waits five seconds before reconnecting.
- Existing client connections are lost if the SSH session disconnects.
- Removing a profile deletes its private key, service and dedicated receiver account when present. Shared prerequisites and the SSH Include remain.

To stop automatic startup for an initiator:

```bash
sudo systemctl disable --now ssh-v2ray-main.service
```

Only copy public keys between servers. SSH encrypts the server-to-server segment. Plain VLESS with `encryption=none` and no TLS/Reality does not gain tunnel encryption on the client-to-Iran segment.

## Tests

```bash
bash -n ssh-tunnel.sh
bash tests/table.sh
sudo bash tests/integration.sh
```

The integration test needs OpenSSH, Python 3, curl, iproute and systemd tools. It creates a temporary localhost SSH daemon and tests real HTTP forwarding in both directions, rejection of shell sessions, timeout logging and menu recovery. Ports `32222` through `32226` must be free. It does not modify the host's production sshd configuration or accounts. VPS connectivity and production capacity are not covered by these local tests.

## License

[MIT](LICENSE).
