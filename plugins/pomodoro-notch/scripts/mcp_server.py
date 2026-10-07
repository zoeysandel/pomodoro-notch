#!/usr/bin/env python3
"""Small JSON-RPC stdio MCP server delegating to the native timer owner."""
import json
import sys
from client import call

EMPTY = {"type": "object", "properties": {}, "additionalProperties": False}


def tool(name, description, schema=EMPTY, read_only=False):
    return {"name": "pomodoro_" + name, "description": description, "inputSchema": schema,
            "annotations": {"readOnlyHint": read_only, "destructiveHint": False, "openWorldHint": False}}


TOOLS = [
    tool("start", "Start a focus session and show its native macOS notch timer. Without minutes, uses the saved native focus duration, initially 25 minutes. An active session is never replaced unless replace=true.",
         {"type": "object", "properties": {
             "task": {"type": "string", "maxLength": 160, "description": "The one thing to focus on."},
             "minutes": {"type": "integer", "minimum": 1, "maximum": 180},
             "replace": {"type": "boolean", "default": False}}, "additionalProperties": False}),
    tool("status", "Read the current Pomodoro session and remaining time. Opens the local companion if it is not running.", read_only=True),
    tool("pause", "Pause the running Pomodoro timer without losing remaining time."),
    tool("resume", "Resume a paused Pomodoro timer."),
    tool("stop", "End the current session and return the native timer to its ready state."),
    tool("break", "Start a break session, normally 5 minutes. Keeps the previous task title. Does not replace an active session unless replace=true.",
         {"type": "object", "properties": {
             "minutes": {"type": "integer", "minimum": 1, "maximum": 60, "default": 5},
             "replace": {"type": "boolean", "default": False}}, "additionalProperties": False}),
    tool("show", "Show and expand the native Pomodoro timer without changing the session.")
]


def rpc_error(identifier, code, message):
    return {"jsonrpc": "2.0", "id": identifier, "error": {"code": code, "message": message}}


def dispatch(message):
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        return rpc_error(None, -32600, "Invalid request")
    if "id" not in message:
        return None
    identifier = message["id"]
    method = message.get("method")
    params = message.get("params") or {}
    if not isinstance(params, dict):
        return rpc_error(identifier, -32602, "Invalid params")
    if method == "initialize":
        supported = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}
        version = params.get("protocolVersion")
        result = {"protocolVersion": version if version in supported else "2025-03-26",
                  "capabilities": {"tools": {}}, "serverInfo": {"name": "pomodoro-notch", "version": "0.2.3"},
                  "instructions": "The native macOS companion owns the timer. Use start, pause, resume, status, stop, break or show. No account or network is required."}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        name = params.get("name")
        definition = next((item for item in TOOLS if item["name"] == name), None)
        if definition is None:
            return rpc_error(identifier, -32602, "Unknown tool")
        arguments = params.get("arguments", {})
        if not isinstance(arguments, dict):
            return rpc_error(identifier, -32602, "Arguments must be an object")
        properties = definition["inputSchema"]["properties"]
        if set(arguments) - set(properties):
            return rpc_error(identifier, -32602, "Unknown argument")
        for key, value in arguments.items():
            spec = properties[key]
            if spec["type"] == "integer" and (type(value) is not int or not spec["minimum"] <= value <= spec["maximum"]):
                return rpc_error(identifier, -32602, "Invalid minutes")
            if spec["type"] == "boolean" and type(value) is not bool:
                return rpc_error(identifier, -32602, "Invalid replace flag")
            if spec["type"] == "string" and (not isinstance(value, str) or len(value) > spec["maxLength"] or any(ord(c) < 32 or ord(c) == 127 for c in value)):
                return rpc_error(identifier, -32602, "Invalid task")
        request = {"action": name.removeprefix("pomodoro_")}
        if "minutes" in arguments:
            request["durationSeconds"] = arguments["minutes"] * 60
        for field in ("task", "replace"):
            if field in arguments:
                request[field] = arguments[field]
        try:
            response = call(request)
            result = {"content": [{"type": "text", "text": json.dumps(response, ensure_ascii=False)}],
                      "structuredContent": response, "isError": not response.get("ok", False)}
        except Exception as error:
            print("Pomodoro tool failed: " + str(error), file=sys.stderr)
            result = {"content": [{"type": "text", "text": str(error)}], "isError": True}
    else:
        return rpc_error(identifier, -32601, "Method not found")
    return {"jsonrpc": "2.0", "id": identifier, "result": result}


def main():
    for line in sys.stdin.buffer:
        if len(line) > 65536:
            response = rpc_error(None, -32600, "Request too large")
        else:
            try:
                response = dispatch(json.loads(line))
            except (ValueError, UnicodeDecodeError):
                response = rpc_error(None, -32700, "Invalid JSON")
            except Exception as error:
                print("MCP request failed: " + str(error), file=sys.stderr)
                response = rpc_error(None, -32603, "Internal error")
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
