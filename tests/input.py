#!/usr/bin/env python3
"""Exercise the real Bash prompts through a terminal, including UTF-8 editing."""
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import time

SCRIPT = Path(__file__).resolve().parent.parent / "ssh-tunnel.sh"


def check(label, command, prompt, keystrokes, expected, forbidden=()):
    master, slave = pty.openpty()
    # Reproduce terminals whose kernel erase setting is not UTF-8 aware.
    subprocess.run(["stty", "-iutf8"], stdin=slave, check=True)
    env = dict(os.environ, LANG="C", LC_ALL="C", TERM="xterm", NO_COLOR="1")
    process = subprocess.Popen(
        ["bash", "--noprofile", "--norc", "-c", 'source "$1"; ' + command,
         "input-test", str(SCRIPT)],
        stdin=slave, stdout=slave, stderr=slave, env=env,
    )
    os.close(slave)
    output = b""
    sent = False
    deadline = time.monotonic() + 5
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output += data
            if not sent and prompt.encode() in output:
                time.sleep(0.06)
                os.write(master, keystrokes.encode())
                sent = True
        if process.poll() is None:
            process.wait(timeout=0.5)
        decoded = output.decode("utf-8", errors="replace")
        assert process.returncode == 0, (label, process.returncode, decoded)
        assert expected in decoded, (label, decoded)
        for message in forbidden:
            assert message not in decoded, (label, decoded)
        print("PASS terminal input:", label)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)


name_command = 'get_name; printf "RESULT=%s\\n" "$NAME"'
port_command = 'get_port PORT "Config port" 8443; printf "RESULT=%s\\n" "$PORT"'
confirm_command = 'if confirm "Create Tunnel?"; then printf "RESULT=yes\\n"; else exit 2; fi'
bad_name = ("Use up to 20 characters",)
bad_port = ("Enter a port number",)
check("Persian character erased with DEL", name_command, "Tunnel name",
      "mس\x7fain\r", "RESULT=main", bad_name)
check("Persian character erased with Ctrl-H", name_command, "Tunnel name",
      "mس\x08ain\r", "RESULT=main", bad_name)
check("Two Persian characters erased", name_command, "Tunnel name",
      "بد\x7f\x7fmain\r", "RESULT=main", bad_name)
check("Arrow keys and Delete edit the middle", name_command, "Tunnel name",
      "maiXn\x1b[D\x1b[D\x1b[3~\r", "RESULT=main", bad_name)
check("Erased input uses the default", name_command, "Tunnel name",
      "س\x7f\r", "RESULT=main", bad_name)
check("Persian digits accepted as a port", port_command, "Config port",
      "۸۴۴۳\r", "RESULT=8443", bad_port)
check("Corrected invalid port accepted", port_command, "Config port",
      "س\x7f8443\r", "RESULT=8443", bad_port)
check("Corrected confirmation accepted", confirm_command, "Create Tunnel?",
      "س\x7fy\r", "RESULT=yes", ("Enter y or n",))
check("Uncorrected name is rejected", name_command, "Tunnel name",
      "mainس\rmain\r", "RESULT=main")
check("Uncorrected name displays validation", name_command, "Tunnel name",
      "mainس\rmain\r", "Use up to 20 characters")
