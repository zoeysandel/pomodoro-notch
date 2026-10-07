#!/usr/bin/env python3
"""Exercise the real MCP -> Unix socket -> native app timer lifecycle."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time

root = Path(__file__).resolve().parent.parent
plugin = root / "plugins/pomodoro-notch"
sys.path.insert(0, str(plugin / "scripts"))
# Use a separate same-user app state directory. No user session is changed.
state = Path(os.environ.get("POMODORO_TEST_DIRECTORY", str(root.parent.parent / "work/pomodoro-test")))
os.environ["POMODORO_STATE_DIRECTORY"] = str(state)
os.environ["POMODORO_NO_FOCUS"] = "1"
from client import call, send


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print("PASS " + message, flush=True)


server = None
try:
    app = plugin / "native/Pomodoro Notch.app"
    subprocess.run(["/usr/bin/open", "-g", "-n", str(app), "--args", "--state-directory", str(state), "--no-focus"], check=True)
    until = time.monotonic() + 8
    while True:
        try:
            ready = send({"action": "stop"})
            break
        except (FileNotFoundError, ConnectionRefusedError):
            if time.monotonic() >= until:
                raise
            time.sleep(0.1)
    check(ready["ok"], "native companion starts and accepts private socket requests")
    check(state.stat().st_mode & 0o777 == 0o700, "state directory is private")
    check((state / "control.sock").stat().st_mode & 0o777 == 0o600, "socket is private")
    short = send({"action": "setDuration", "durationSeconds": 30})["session"]
    check(short["display"] == "00:30" and send({"action": "start"})["session"]["durationSeconds"] == 30,
          "a duration under one minute starts with second precision")
    send({"action": "stop"})
    configured = send({"action": "setDuration", "durationSeconds": 1050})["session"]
    check(configured["display"] == "17:30" and configured["focusDurationSeconds"] == 1050,
          "custom duration updates the ready clock in minutes and seconds")
    check(not send({"action": "setDuration", "minutes": True})["ok"]
          and not send({"action": "setDuration", "minutes": 181})["ok"]
          and not send({"action": "setDuration", "durationSeconds": 10801})["ok"],
          "custom duration rejects invalid values")
    custom = send({"action": "start", "task": "Configured duration"})["session"]
    check(custom["durationSeconds"] == 1050, "native start uses the configured focus duration")
    check(not send({"action": "setDuration", "minutes": 25})["ok"],
          "duration cannot change a running timer")
    send({"action": "stop"})
    server = subprocess.Popen([str(plugin / "scripts/launch_mcp")], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, env=os.environ.copy())
    counter = 0

    def rpc(method, params=None):
        global counter
        counter += 1
        message = {"jsonrpc": "2.0", "id": counter, "method": method}
        if params is not None:
            message["params"] = params
        server.stdin.write(json.dumps(message) + "\n")
        server.stdin.flush()
        if not select.select([server.stdout], [], [], 12)[0]:
            raise RuntimeError("MCP server did not reply")
        return json.loads(server.stdout.readline())

    def tool(name, arguments=None):
        result = rpc("tools/call", {"name": "pomodoro_" + name, "arguments": arguments or {}})
        check("result" in result, "MCP " + name + " replies")
        return result["result"]

    init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                              "clientInfo": {"name": "smoke-test", "version": "1"}})
    check(init["result"]["capabilities"]["tools"] == {}, "MCP initialization advertises tools")
    server.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
    server.stdin.flush()
    check(len(rpc("tools/list")["result"]["tools"]) == 7, "all seven tools are discoverable")
    started = tool("start", {"task": "Pomodoro integration test", "minutes": 1})["structuredContent"]
    check(started["session"]["phase"] == "running" and started["session"]["durationSeconds"] == 60, "MCP start controls native timer")
    time.sleep(0.25)
    compact = send({"action": "presentation"})["window"]
    check(compact["height"] == compact["headerHeight"], "collapsed overlay stays within the notch header")
    tool("show")
    time.sleep(0.06)
    intermediate = send({"action": "presentation"})["window"]
    check(intermediate["top"] == compact["top"], "expansion keeps the top at the notch")
    if not intermediate["reduceMotion"]:
        check(compact["height"] < intermediate["height"] < compact["height"] + 140,
              "window and content share an intermediate transition frame")
    send({"action": "start", "task": "Interrupted transition", "durationSeconds": 60, "replace": True})
    time.sleep(0.25)
    collapsed = send({"action": "presentation"})["window"]
    check(collapsed["height"] == compact["height"] and collapsed["expansion"] == 0,
          "reversing a transition returns to the compact frame")
    edited = send({"action": "setTask", "task": "Task changed without restarting"})["session"]
    check(edited["phase"] == "running" and edited["durationSeconds"] == 60 and edited["task"] == "Task changed without restarting",
          "editing optional task preserves the running timer")
    check(tool("start", {"task": "Replace accidentally"})["isError"], "active session cannot be overwritten accidentally")
    before = tool("pause")["structuredContent"]["session"]["remainingSeconds"]
    paused_progress = send({"action": "status"})["session"]["progress"]
    time.sleep(1.1)
    after = tool("status")["structuredContent"]["session"]
    check(after["phase"] == "paused" and after["remainingSeconds"] == before, "pause freezes remaining time")
    check(after["progress"] == paused_progress, "pause also freezes progress")
    resumed = tool("resume")["structuredContent"]["session"]
    time.sleep(1.1)
    check(tool("status")["structuredContent"]["session"]["remainingSeconds"] < resumed["remainingSeconds"], "resume continues countdown")
    invalid = rpc("tools/call", {"name": "pomodoro_start", "arguments": {"minutes": True}})
    check(invalid["error"]["code"] == -32602, "MCP rejects invalid duration types")
    check(not send({"action": "start", "replace": True, "durationSeconds": -1})["ok"], "native owner also validates duration")
    saved_id = tool("status")["structuredContent"]["session"]["sessionID"]
    send({"action": "quit"})
    time.sleep(0.5)
    restored = call({"action": "status"})["session"]
    check(restored["sessionID"] == saved_id and restored["phase"] == "running", "running session restores after native relaunch")
    check(restored["focusDurationSeconds"] == 1050, "custom focus duration preserves seconds after native relaunch")
    tool("stop")
    send({"action": "start", "task": "Task to keep for the break", "durationSeconds": 1})
    time.sleep(1.3)
    rest = tool("break")["structuredContent"]["session"]
    check(rest["durationSeconds"] == 300, "break defaults to five minutes")
    check(rest["task"] == "Task to keep for the break", "break preserves focus task internally")
    tool("stop")
    send({"action": "start", "task": "Completion test", "durationSeconds": 1})
    time.sleep(1.3)
    finished = send({"action": "status"})["session"]
    check(finished["phase"] == "completed" and finished["expanded"], "completion reveals expanded native overlay")
    check(not send({"action": "presentation"})["window"]["keyWindow"], "automatic completion does not take keyboard focus")
    dismissed = send({"action": "finish"})["session"]
    check(dismissed["phase"] == "idle" and not dismissed["visible"], "Close hides and clears the completed session")
    reopened = tool("show")["structuredContent"]["session"]
    check(reopened["visible"] and reopened["expanded"], "Show timer reopens the controls")
    tool("stop")
    independent = send({"action": "start", "task": "Independent lifetime test", "durationSeconds": 5})["session"]
    server.stdin.close()
    server.wait(timeout=4)
    check(server.returncode == 0, "MCP server exits cleanly on EOF")
    time.sleep(1.1)
    independent_after = send({"action": "status"})["session"]
    check(independent_after["phase"] == "running" and independent_after["remainingSeconds"] < independent["remainingSeconds"],
          "native timer keeps counting after MCP session ends")
finally:
    if server is not None and server.poll() is None:
        server.terminate()
        server.wait(timeout=3)
    try:
        send({"action": "stop"})
        send({"action": "setDuration", "minutes": 25})
        send({"action": "quit"})
    except (OSError, RuntimeError):
        pass
