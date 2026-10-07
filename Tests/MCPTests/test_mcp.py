"""Verify exact durations reach the native owner without launching an app."""
import sys
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "plugins/pomodoro-notch/scripts"))
import mcp_server


class DurationToolsTests(unittest.TestCase):
    def request(self, arguments, name="start"):
        return mcp_server.dispatch({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                    "params": {"name": "pomodoro_" + name, "arguments": arguments}})

    def test_custom_minutes_seconds_and_exact_seconds_are_forwarded(self):
        examples = [({"duration": "421:09"}, 25269), ({"duration": "00:01"}, 1),
                    ({"duration": "35791394:07"}, mcp_server.MAX_SECONDS),
                    ({"seconds": 25269}, 25269), ({"minutes": 421}, 25260)]
        for name in ("start", "break"):
            for arguments, expected in examples:
                with self.subTest(tool=name, arguments=arguments), patch.object(mcp_server, "call", return_value={"ok": True}) as native:
                    response = self.request(arguments, name)
                    self.assertFalse(response["result"]["isError"])
                    native.assert_called_once_with({"action": name, "durationSeconds": expected})

    def test_saved_duration_and_replacement_flag_keep_their_meaning(self):
        with patch.object(mcp_server, "call", return_value={"ok": True}) as native:
            self.request({"task": "Presentation"})
            native.assert_called_once_with({"action": "start", "task": "Presentation"})
        with patch.object(mcp_server, "call", return_value={"ok": True}) as native:
            self.request({"duration": "421:09", "replace": True})
            native.assert_called_once_with({"action": "start", "durationSeconds": 25269, "replace": True})

    def test_invalid_or_ambiguous_durations_never_contact_native_app(self):
        invalid = [{"duration": value} for value in ["00:00", "421:60", "-1:09", "421:9",
                    "421:09\n", "35791394:08", "999999999999999999999999999999999:59", 25269, None]]
        invalid += [{"seconds": value} for value in [0, -1, True, 2.5, "30", mcp_server.MAX_SECONDS + 1]]
        invalid += [{"minutes": value} for value in [0, -1, True, 1.5, "421", mcp_server.MAX_SECONDS // 60 + 1]]
        invalid += [{"duration": "421:09", "minutes": 421}, {"duration": "421:09", "seconds": 25269},
                    {"minutes": 421, "seconds": 25269}]
        for name in ("start", "break"):
            for arguments in invalid:
                with self.subTest(tool=name, arguments=arguments), patch.object(mcp_server, "call") as native:
                    self.assertEqual(self.request(arguments, name)["error"]["code"], -32602)
                    native.assert_not_called()

    def test_tool_discovery_advertises_exact_durations_without_a_default(self):
        response = mcp_server.dispatch({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        tools = {tool["name"]: tool for tool in response["result"]["tools"]}
        self.assertEqual(len(tools), 7)
        for name in ("pomodoro_start", "pomodoro_break"):
            properties = tools[name]["inputSchema"]["properties"]
            self.assertIn("duration", properties)
            self.assertIn("seconds", properties)
            self.assertNotIn("default", properties["minutes"])

    def test_local_cli_rejects_invalid_or_conflicting_duration_arguments(self):
        client = Path(mcp_server.__file__).with_name("client.py")
        examples = [["--duration", "00:00"], ["--duration", "421:60"],
                    ["--seconds", "0"], ["--seconds", str(mcp_server.MAX_SECONDS + 1)],
                    ["--duration", "421:09", "--seconds", "25269"]]
        for arguments in examples:
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, "-B", str(client), "start", "--no-launch"] + arguments,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("error:", result.stderr)


if __name__ == "__main__":
    unittest.main()
