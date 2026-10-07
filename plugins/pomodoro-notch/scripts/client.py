#!/usr/bin/env python3
"""Local companion client. No network access or third-party dependencies."""
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import time

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
STATE_DIRECTORY = Path(os.environ.get(
    "POMODORO_STATE_DIRECTORY", str(Path.home() / "Library/Application Support/Pomodoro Notch")
))


def send(request):
    path = STATE_DIRECTORY / "control.sock"
    # Reject sockets in shared/wrong-owner directories before sending task text.
    directory = STATE_DIRECTORY.lstat()
    endpoint = path.lstat()
    if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.getuid() or directory.st_mode & 0o077:
        raise RuntimeError("Pomodoro control directory is not private")
    if not stat.S_ISSOCK(endpoint.st_mode) or endpoint.st_uid != os.getuid() or endpoint.st_mode & 0o077:
        raise RuntimeError("Pomodoro control socket is not private")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(6)
        connection.connect(str(path))
        connection.sendall(json.dumps(request, ensure_ascii=False).encode("utf-8") + b"\n")
        data = bytearray()
        while b"\n" not in data:
            chunk = connection.recv(4096)
            if not chunk:
                raise RuntimeError("Native app closed the connection")
            data.extend(chunk)
            if len(data) > 65536:
                raise RuntimeError("Native app response was too large")
        return json.loads(data.split(b"\n", 1)[0])


def call(request, launch=True):
    try:
        return send(request)
    except (FileNotFoundError, ConnectionRefusedError):
        if not launch:
            raise
    app = PLUGIN_ROOT / "native/Pomodoro Notch.app"
    if not app.is_dir():
        raise RuntimeError("Native companion is missing. Build this plugin with script/build.sh first.")
    # Launch Services otherwise reopens an instance using a different state
    # directory. The native owner's lock prevents duplicate normal instances.
    command = ["/usr/bin/open", "-n", str(app)]
    arguments = []
    if "POMODORO_STATE_DIRECTORY" in os.environ:
        arguments += ["--state-directory", str(STATE_DIRECTORY)]
    if os.environ.get("POMODORO_NO_FOCUS") == "1":
        arguments += ["--no-focus"]
    if arguments:
        command += ["--args"] + arguments
    subprocess.run(command, check=True, capture_output=True, timeout=8)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            return send(request)
        except (FileNotFoundError, ConnectionRefusedError):
            time.sleep(0.1)
    raise RuntimeError("Pomodoro Notch did not start within 8 seconds")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["status", "start", "pause", "resume", "stop", "break", "show", "hide", "quit"])
    parser.add_argument("--task")
    parser.add_argument("--seconds", type=int)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--no-launch", action="store_true")
    options = parser.parse_args()
    request = {"action": options.action}
    if options.task is not None:
        request["task"] = options.task
    if options.seconds is not None:
        request["durationSeconds"] = options.seconds
    if options.replace:
        request["replace"] = True
    result = call(request, launch=not options.no_launch)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result.get("ok") else 1)
