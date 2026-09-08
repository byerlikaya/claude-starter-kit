#!/usr/bin/env python3
"""A pseudo-terminal, over stdin and stdout, with nothing installed.

`node-pty` is the usual answer and it wants a native build; Python's `pty` is
in the standard library and this repo already depends on python3 for the
diagram generator. Measured: pty.fork() here yields a real /dev/ttys*, and
`[ -t 0 ]` inside it is true.

Protocol, one JSON object per line each way:

    in   {"t":"in",   "d":"<base64>"}      keystrokes for the child
         {"t":"size", "rows":40,"cols":120}
         {"t":"kill"}
    out  {"t":"out",  "d":"<base64>"}      whatever the child wrote
         {"t":"exit", "code":0}

Base64 because a terminal emits bytes, not text: a partial UTF-8 sequence at a
read boundary must survive the trip and be reassembled by the reader.

Unix only. The `pty` module does not exist on Windows, which is stated rather
than worked around.

Not named pty.py: a script beside a module it imports shadows it, and `import
pty` then finds this file instead of the standard library's.
"""

import base64
import binascii
import fcntl
import json
import os
import pty
import select
import shlex
import signal
import struct
import sys
import termios


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def set_size(fd, rows, cols):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except OSError:
        pass


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
    shell = sys.argv[2] if len(sys.argv) > 2 else (os.environ.get("SHELL") or "/bin/sh")
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    cols = int(sys.argv[4]) if len(sys.argv) > 4 else 100

    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.chdir(cwd)
        except OSError:
            pass
        os.environ["TERM"] = os.environ.get("TERM") or "xterm-256color"
        # A login shell picks up the profile, which is what makes this feel like
        # the terminal the person already uses.
        os.execvp(shell, [shlex.split(shell)[0], "-l"])
        os._exit(127)

    set_size(fd, rows, cols)
    stdin_fd = sys.stdin.fileno()
    buf = ""
    alive = True

    while alive:
        try:
            ready, _, _ = select.select([fd, stdin_fd], [], [], 0.2)
        except (OSError, select.error):
            break

        if fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                alive = False
            else:
                emit({"t": "out", "d": base64.b64encode(data).decode("ascii")})

        if stdin_fd in ready:
            try:
                chunk = os.read(stdin_fd, 65536).decode("utf-8", "replace")
            except OSError:
                chunk = ""
            if not chunk:
                alive = False
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                kind = msg.get("t")
                if kind == "in":
                    # A frame that will not decode is one bad frame, not the end
                    # of the terminal. binascii.Error escaping here took the
                    # whole session down and reported it as an exit with no
                    # code, which reads like the shell died on its own.
                    try:
                        data = base64.b64decode(msg.get("d", ""), validate=False)
                    except (binascii.Error, ValueError, TypeError):
                        continue
                    try:
                        os.write(fd, data)
                    except OSError:
                        alive = False
                elif kind == "size":
                    try:
                        set_size(fd, int(msg.get("rows", rows)), int(msg.get("cols", cols)))
                    except (ValueError, TypeError, OSError):
                        continue
                elif kind == "kill":
                    try:
                        os.kill(pid, signal.SIGHUP)
                    except OSError:
                        pass
                    alive = False

    try:
        os.close(fd)
    except OSError:
        pass
    code = 0
    try:
        _, status = os.waitpid(pid, os.WNOHANG)
        code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
    except OSError:
        pass
    emit({"t": "exit", "code": code})


if __name__ == "__main__":
    main()
