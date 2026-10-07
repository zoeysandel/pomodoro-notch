# Changelog

## 0.2.4 — 2026-10-07

- Allow custom native durations longer than 180 minutes, including 421:09.
- Add exact `duration` (mm:ss) and `seconds` parameters to the start and break MCP tools; keep whole-minute requests compatible.
- Add an exact-duration local CLI fallback for desktop chats whose MCP tools have not loaded.
- Preserve long sessions and second-precise duration preferences after relaunch.
- Reject invalid or conflicting duration arguments before contacting the native app.
- Keep clocks on one line and scale long values to the available space.
- Cover exact custom durations, input boundaries, relaunch and active-session protection in the tests.

## 0.2.3 — 2026-10-07

First GitHub demo release.

- Add a Git-backed marketplace, English installation instructions and an interface screenshot.
- Ship an Apple Silicon release build for macOS 14 or later.
- Keep the native app, portable manifest, Codex compatibility manifest and MCP server version aligned.
- Document local data storage, Python requirements and the ad hoc signature.
- Correct the skill instructions for saved focus durations and the current interface.

The native app is a proof of concept. It is not Developer ID-signed or notarized, and this release has not been submitted to the public OpenAI directory.
