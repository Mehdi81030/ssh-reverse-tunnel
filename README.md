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

Prompts support UTF-8 editing with Backspace, Delete and arrow keys. If you erase a mistyped character, only the final text is validated. Persian and Arabic digits are accepted in numeric answers such as ports and menu selections.

```text
  1) Setup Reverse         Kharej connects to Iran
  2) Setup Direct          Iran connects to Kharej
  3) Manage Tunnels        select a service, view details and actions
  4) Public Key            generate or copy your public key
  L) Import Setup Link     configure this server from a peer setup link
  0) Exit                  close this menu
```

## Features

- Guided setup: choose Reverse or Direct, then choose Iran or Kharej.
- A setup link and ready-to-run command transfer the receiver settings and public key automatically.
- Missing tools are installed automatically during setup; existing tools are reused.
- Dedicated SSH account limited to the requested forwarding operation, with shell sessions disabled.
- Reuses existing Ed25519 keys and asks you to compare host key fingerprints.
- A systemd service starts after boot and reconnects after disconnection.
- Either server can finish setup last; an unprepared receiver does not block service installation.
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

At **Config port on kharej**, enter the VLESS inbound port, not the web panel port. The backend address is fixed to `127.0.0.1` on Kharej, so there is no backend-address question. The service must listen there or have its container port published on the host. The Iran entry port and the config port may differ. The restricted account requires reverse entry ports to be **1024 or higher**.

## Setup with a link

For setup with one link, **start on Kharej in Reverse mode**, or **Iran in Direct mode**. Complete the initiator setup using the receiver address, SSH port, Iran entry port and config port on Kharej. The receiver's ordinary SSH must be reachable so you can verify its host fingerprints. Registering the tunnel account can happen later; the installed initiator waits and retries.

The name prompt suggests a fresh random name such as `tunnel-a1b2c3d4e5f6` instead of `main`. Press Enter to accept it, or enter your own name. The setup link carries this exact name to the other server. Use a separate name and Iran entry port for each Kharej server. Existing profiles keep their names; when managing or rebuilding one, enter its existing name. In manual setup, copy the first server's name to the second rather than accepting a second random suggestion.

At the end, the initiator prints a **`ssh-tunnel://v1/...` Setup Link** and a command that downloads this script and imports the link on the receiver. On the other server, run that command as root, or choose **L: Import Setup Link** and paste the link. The mode, profile name, ports and public key are filled automatically. Review the displayed settings and answer **Create Tunnel?**; the waiting initiator then connects automatically.

The link contains receiver settings and the **public key only**. The private key stays on the initiator. Export derives the public part from the actual private key, so a stale `.pub` file is not copied into the link. Links are decoded and validated as data; imported content is never evaluated as shell code. An existing receiver in the same mode can apply a link to update its port permissions, public key and saved settings without deleting its account. Changed permissions or keys reconnect only this tunnel's account sessions. An identical link keeps existing sessions. Backups are saved before applying; configuration validation, file update or SSH reload failures restore the previous files. A reverse entry port occupied by another listener is rejected before changing settings. Open the new entry port in the Iran firewall separately. The link does not change sshd's listening port.

For an existing initiator, select its service in **Manage Tunnels** and choose **10: Show Setup Link**. This generates a fresh link from the current saved settings. The one-link workflow starts on the initiator; manual setup below still supports completing either side last.

SSH itself does not require matching local service names. This manager derives the receiver account as `svt-NAME`, so its manual workflow requires the same profile name on both servers. Importing a setup link fills that name automatically.

## Reverse setup

1. Run the script on both machines. Required tools are prepared automatically when you start setup.
2. On **Kharej**, choose **1: Setup Reverse**, then **2: Kharej**. Accept the random tunnel name or enter your own; keep it for the Iran setup.
3. Copy the entire displayed `ssh-ed25519 ...` public key line.
4. On **Iran**, choose **1: Setup Reverse**, then **1: Iran**. Use the same tunnel name, enter the Iran entry port and actual Iran SSH port, and paste the public key.
5. On Kharej, enter the Iran address, SSH port, Iran entry port and **Config port on kharej**. The backend address is filled automatically as `127.0.0.1`.
6. Compare the displayed host key fingerprints with the Iran output. Confirm only if they match.
7. The service is installed even if its first SSH test fails. It retries automatically. Configure the client with the Iran IP and entry port, keeping the backend VLESS UUID and protocol settings.

This is a suggested order. You can finish Kharej before step 4; it will connect automatically after Iran registers the key. You do not need to keep the setup terminal open. Iran's ordinary SSH service must be reachable for the initial host identity check. If its tunnel setup has not run yet, obtain its fingerprints directly on Iran:

```bash
for key in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf "$key"; done
```

Iran must allow its SSH port and client entry port in the host and provider firewalls. Kharej must be able to establish an SSH connection to Iran and transfer data.

## Direct setup

Choose **2: Setup Direct** on both servers. Iran generates the public key; Kharej registers it. You can finish Iran before or after registering the key on Kharej. Iran's installed service retries until the receiver is ready. Use the same profile name and config port on both sides. The backend address is automatically set to `127.0.0.1` on Kharej. Kharej's ordinary SSH service must be reachable for the initial host identity check; its fingerprints can be obtained with the command above.

Kharej must allow its SSH port, and Iran must allow the client entry port. The backend must be reachable from the Kharej host; for Docker deployments, use the port published on the host.

## Menu and tunnel table

| Option | Action |
|---|---|
| 1 | Set up Reverse |
| 2 | Set up Direct |
| 3 | Manage Tunnels: service table and actions |
| 4 | Public Key |
| L | Import Setup Link |
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
| 10 | Show Setup Link for the other server |
| 0 | Back to the table |

Start/Stop/Restart, Edit and Auto-Restart controls appear on the server running the dedicated tunnel service. On an SSH receiver, status, logs, configuration and deletion are available; shared sshd is not stopped or restarted from this page. `configured` means receiver settings are prepared. New services show `Waiting` while trying to establish SSH and `active` once their SSH control connection is available. Older services without a control socket still report process status. Test with a real client to confirm backend health. `Auto Restart: Remote` means its policy is managed on the other server.

Editing validates the entered addresses and ports, verifies the host fingerprint when the SSH peer changes, and preserves the prior configuration if applying the service change fails. When changing the entry port or backend, update the matching receiver permissions separately. Changes that start successfully can still fail to connect; inspect Recent Logs and test the client.

Auto-restart management changes the selected tunnel's systemd restart policy. Applying it to an active tunnel restarts that tunnel after confirmation. This setting is separate from starting the service after boot.

To delete, select the service, choose **9**, and confirm its name. Deletion affects this server only. Remove the matching profile on the other server separately. Receiver deletion waits for the dedicated account's processes to exit before removing the account and its home directory; it force-stops remaining processes if necessary. Partial profiles can be cleaned up even if their service marker or SSH snippet is missing. Service cleanup stops and disables the named unit, removes its generated file and owned override, clears failed state and its control socket, and checks that it is no longer active or enabled. A failed deletion retains the profile and reports the failure.

Deleting both ends removes the key pair. Rebuilding creates a new public key: copy that new line to the receiver rather than reusing a key from an earlier setup.

For multiple Kharej servers, use a different tunnel name and Iran entry port for each. Backend ports may be identical on separate servers. This does not provide automatic load balancing or failover between backends.

## Troubleshooting

Setup automatically tests SSH with a 30-second timeout and prints the last 80 lines of debug output on failure. Exit code **124** means the test reached its time limit; it does not identify the cause by itself. Failure of this initial test no longer blocks service installation. Once the receiver has the correct public key and forwarding settings, the service connects automatically. Incorrect settings or a blocked network path still need correction; use Recent Logs. Initiator profiles left `Incomplete` by an older version require one Setup run with the same name to install their service. Host key verification remains required before installation.

If the initiator was recreated and the receiver still has its old key, SSH reports `Permission denied (publickey)`. Copy the current public key from **4: Public Key** on the initiator. On the receiver, run Setup again with the same mode and tunnel name, then paste it at **Paste new ssh-ed25519 public key (Enter to keep current)**. Enter without text keeps the existing key. A replacement is validated and written atomically, with the previous authorized key backed up in the profile directory. The existing forwarding permission is retained. No account recreation or SSH restart is needed; the initiator reconnects automatically.

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
- New services use a root-only SSH control socket under `/run/ssh-v2ray-NAME/` to check connection status. systemd creates and cleans up this directory.
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
bash tests/input.sh
python3 tests/input.py
bash tests/dependencies.sh
bash tests/table.sh
bash tests/service-menu.sh
bash tests/setup-order.sh
bash tests/setup-link.sh
bash tests/receiver-key.sh
bash tests/receiver-link-update.sh
bash tests/removal.sh
sudo bash tests/integration.sh
sudo bash tests/systemd-order.sh
sudo bash tests/recreate.sh
```

The input tests check UTF-8 corrections and numeric answers, including real terminal editing with the kernel's UTF-8 erase setting disabled. The dependency and service-menu tests mock package managers/systemctl, checking automatic installation, service selection, controls, editing rollback, auto-restart management and deletion without touching shared sshd or exposing private keys. The setup-order test checks that a failed initial SSH test installs a retrying service, and that canceled host verification still prevents installation. The setup-link test checks data round-tripping, actual public-key derivation, and rejection of malformed/duplicate/unknown fields and shell expressions. The receiver-key test checks manual replacement, backups, unchanged manual forwarding permissions, rejection of invalid keys, and keeping the existing key with Enter. The receiver-link-update test checks port/key updates, identical links, occupied ports, and restoration of config/key/summary on validation, reload, session shutdown or file-write failure. The removal test covers partial profiles, waiting for account processes, SSH validation rollback and service-stop failures.

The integration tests need OpenSSH, Python 3, curl, iproute and systemd tools. `integration.sh` creates a temporary localhost SSH daemon and tests real HTTP forwarding in both directions, rejection of shell sessions, timeout logging and menu recovery; ports `32222` through `32226` must be free. `systemd-order.sh` additionally needs running systemd and free ports `32322` through `32325`. It installs temporary, uniquely named services, verifies real forwarding when either side finishes last (including reconnecting after replacing a stale receiver key), and cleans up its own units and boot links. These tests do not modify production sshd configuration or accounts. VPS connectivity and production capacity are not covered by these local tests.

`recreate.sh` requires root, running systemd and free ports `32422` through `32425`. It creates its own temporary account, home directory, SSH daemon and tunnel unit. It tests real forwarding, deletes both profiles and rebuilds using the same name in both modes, including a process that ignores TERM. The second cycle creates the receiver entirely from a setup link, with only the final creation confirmation, then repairs a stale receiver port/key by applying the link again. The account/home are preserved and SSH automatically reconnects with real HTTP forwarding. It removes only its temporary account/unit and leaves production SSH configuration untouched.

## License

[MIT](LICENSE).
