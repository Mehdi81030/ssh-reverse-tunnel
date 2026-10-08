# SSH Reverse Tunnel

A Bash manager for **reverse and direct SSH port-forwarding tunnels** between two Linux servers, with a colored service table and a details/actions screen for each tunnel. Supports V2Ray/Xray TCP inbounds and other TCP services.

[راهنمای فارسی](README-fa.md)

## Download and run

Run on both servers:

```bash
curl -fL --retry 3 -o ssh-tunnel.sh https://raw.githubusercontent.com/Mehdi81030/ssh-reverse-tunnel/main/ssh-tunnel.sh
sudo bash ssh-tunnel.sh
```

Or clone this repository and run `sudo bash ssh-tunnel.sh`. **Colors are enabled by default; no extra flag is needed.** The interface uses cyan tables and section headings, green active states, yellow options, red stop/delete actions, and white values. Disable colors only when needed with `--no-color` or `NO_COLOR=1`.

```text
  1) Setup Reverse         Kharej connects to Iran
  2) Setup Direct          Iran connects to Kharej
  3) Manage Tunnels        select a service, view details and actions
  4) Public Key            generate or copy your public key
  0) Exit                  close this menu
```

## Features

- Guided setup: choose Reverse or Direct, then choose Iran or Kharej.
- Missing tools are installed automatically during setup; existing tools are reused.
- Dedicated SSH account limited to the requested forwarding operation, with shell sessions disabled.
- Reuses existing Ed25519 keys and asks you to compare host key fingerprints.
- A systemd service starts after boot and reconnects after disconnection.
- Multiple independent tunnels, each with its own profile name and Iran entry port.
- A service table opens a details/actions page for the selected tunnel.
- Start, stop, restart, view status/logs/configuration, edit settings, manage auto-restart and delete a selected service.
- SSH debug logs and connection settings are saved even when setup fails.
- Status and logs work on both receivers and initiators.

## Interface

Example service screens rendered from the actual menu output. Your terminal theme controls the background and font.

![Service table](assets/service-table.png)

![Service details and actions](assets/service-details.png)

## Requirements

Linux with systemd running, Bash, root access, and a recent OpenSSH client/server. Local checks used Ubuntu and OpenSSH 9.6. Ubuntu 22.04/24.04 or Debian 12 are suggested starting points. Setup automatically installs missing tools using `apt` or `dnf`; no separate prerequisites step is needed. Client tools are prepared on the initiator, and server/account tools are prepared on the receiver. The receiver's SSH service is started and enabled after the dependency check. Existing running SSH services are not restarted. Other distributions require manual dependency installation.

Forwarding is **TCP only**. The script does not configure firewall rules, change network MTU, or modify your V2Ray/Xray configuration. Independent UDP forwarding is not supported.

## Choose the direction

| Mode | SSH connection starts on | SSH receiver | Client connects to |
|---|---|---|---|
| Reverse | Kharej | Iran | Iran IP and entry port |
| Direct | Iran | Kharej | Iran IP and entry port |

In either mode, the backend V2Ray/Xray service runs on Kharej. These are SSH port-forwarding tunnels, not layer-3 VPNs.

```text
Client -> Iran:8443 -> SSH tunnel -> Kharej:127.0.0.1:443 -> VLESS
```

Use the VLESS **inbound port**, not the web panel port. The Iran entry port and the backend port may differ. The restricted account requires reverse entry ports to be **1024 or higher**.

## Reverse setup

1. Run the script on both machines. Required tools are prepared automatically when you start setup.
2. On **Kharej**, choose **1: Setup Reverse**, then **2: Kharej**. Choose a tunnel name, for example `main`.
3. Copy the entire displayed `ssh-ed25519 ...` public key line. Keep this terminal open.
4. On **Iran**, choose **1: Setup Reverse**, then **1: Iran**. Use the same tunnel name, enter the Iran entry port and actual Iran SSH port, and paste the public key.
5. Return to Kharej and confirm that Iran is ready. Enter the Iran address, SSH port, Iran entry port, backend address (usually `127.0.0.1`) and actual VLESS inbound port.
6. Compare the displayed host key fingerprints with the Iran output. Confirm only if they match.
7. After the SSH test succeeds, the service is installed. Configure the client with the Iran IP and entry port, keeping the backend VLESS UUID and protocol settings.

Iran must allow its SSH port and client entry port in the host and provider firewalls. Kharej must be able to establish an SSH connection to Iran and transfer data.

## Direct setup

Choose **2: Setup Direct** on both servers. Iran generates the public key; Kharej registers it. Iran then starts the SSH connection to Kharej. Use the same profile name, and enter the exact same backend address and port on both sides.

Kharej must allow its SSH port, and Iran must allow the client entry port. The backend must be reachable from the Kharej host; for Docker deployments, use the port published on the host.

## Menu and tunnel table

| Option | Action |
|---|---|
| 1 | Set up Reverse |
| 2 | Set up Direct |
| 3 | Manage Tunnels: service table and actions |
| 4 | Public Key |
| 0 | Exit |

Option **3** shows **Service Name, Status, Mode and Auto Restart**. Enter a row number to open that service's details and actions. Enter `r` to refresh the table or `0` to return. Selecting a row does not delete anything.

The details box shows the Iran entry port, SSH peer/port, V2Ray endpoint, auto-restart policy and boot startup setting. Older receiver profiles may show `-` for settings that were not saved by earlier versions.

| Service action | Function |
|---|---|
| 1 / 2 / 3 | Start / Stop / Restart the dedicated tunnel service |
| 4 | Show Status |
| 5 | View Recent Logs, including the last setup attempt |
| 6 | Edit Configuration and restart the service |
| 7 | View Configuration without showing private key contents |
| 8 | Auto-Restart Management using systemd |
| 9 | Delete Service after confirming its name |
| 0 | Back to the table |

Start/Stop/Restart, Edit and Auto-Restart controls appear on the server running the dedicated tunnel service. On an SSH receiver, status, logs, configuration and deletion are available; shared sshd is not stopped or restarted from this page. `configured` means receiver settings are prepared; `active` means the local tunnel process is running. Test with a real client to confirm end-to-end health. `Auto Restart: Remote` means its policy is managed on the other server.

Editing validates the entered addresses and ports, verifies the host fingerprint when the SSH peer changes, and preserves the prior configuration if applying the service change fails. When changing the entry port or backend, update the matching receiver permissions separately. Changes that start successfully can still fail to connect; inspect Recent Logs and test the client.

Auto-restart management changes the selected tunnel's systemd restart policy. Applying it to an active tunnel restarts that tunnel after confirmation. This setting is separate from starting the service after boot.

To delete, select the service, choose **9**, and confirm its name. Deletion affects this server only. Remove the matching profile on the other server separately.

For multiple Kharej servers, use a different tunnel name and Iran entry port for each. Backend ports may be identical on separate servers. This does not provide automatic load balancing or failover between backends.

## Troubleshooting

Setup automatically tests SSH with a 30-second timeout and prints the last 80 lines of debug output on failure. Exit code **124** means the test reached its time limit; it does not identify the cause by itself. Settings are saved for the tunnel table and diagnostics. If setup failed before creating a service, run Setup Reverse or Setup Direct again with the same profile name to retry.

**Manage Tunnels -> select a service -> 5: View Recent Logs** shows setup logs even if no tunnel service was created. On the receiver it shows SSH service logs. Use **7: View Configuration** for account permissions. If `AllowUsers`, `AllowGroups`, `DisableForwarding` or other SSH restrictions are configured, ensure the dedicated tunnel account is permitted. Entering an SSH port in this script does not change sshd's listening port.

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
bash tests/dependencies.sh
bash tests/table.sh
bash tests/service-menu.sh
sudo bash tests/integration.sh
```

The dependency and service-menu tests mock package managers/systemctl, checking automatic installation, service selection, controls, editing rollback, auto-restart management and deletion without touching shared sshd or exposing private keys. The integration test needs OpenSSH, Python 3, curl, iproute and systemd tools. It creates a temporary localhost SSH daemon and tests real HTTP forwarding in both directions, rejection of shell sessions, timeout logging and menu recovery. Ports `32222` through `32226` must be free. It does not modify the host's production sshd configuration or accounts. VPS connectivity and production capacity are not covered by these local tests.

## License

[MIT](LICENSE).
