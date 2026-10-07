---
name: pomodoro
description: Start, pause, resume or check a Pomodoro focus session in a native macOS notch timer; start a five-minute break after focusing. Use when the user asks for a pomodoro or wants a timed focus session.
---

# Pomodoro Notch

Use the Pomodoro MCP tools to control the native timer. The app owns the timer independently of this chat.

- Start a focus session with `pomodoro_start`. For a time such as `421:09`, pass `duration: "421:09"` (421 minutes and 9 seconds). For a request in total seconds, pass `seconds`; for whole minutes, pass `minutes`. Supply only one duration field and preserve the exact requested time, including seconds. Omit all duration fields unless the user requested a duration; the native app uses its saved focus duration, initially 25 minutes. Use the task the user named; omit it when no task was given. Start directly when requested.
- Read remaining time with `pomodoro_status`; do not guess from previous chat messages.
- Pause, resume and end with `pomodoro_pause`, `pomodoro_resume`, and `pomodoro_stop`.
- Start a break with `pomodoro_break`, defaulting to 5 minutes. A break starts only when requested or clicked in the native UI.
- Show or expand the overlay with `pomodoro_show`.
- Never replace an active session unless the user requested replacing it; otherwise report the current session. The tool enforces this by default.
- Only say the action succeeded after the tool returns `ok: true`. Keep the response short and use the user's language.
- After the first successful start in a chat, briefly explain that the timer is at the Mac's notch, has its own pause control, and keeps running independently of the chat. Do not repeat this explanation for subsequent actions.

The native overlay includes its own controls and a menu bar timer. The circular control pauses in orange and starts or resumes in green. The task is optional: Add task opens a small inline editor; Enter confirms and Escape cancels. Click the ready clock to set a custom duration in minutes or mm:ss, including sessions longer than 180 minutes such as 421:09. The minimum is one second; the technical maximum is 2,147,483,647 seconds. Focus and break are labeled explicitly; the work task is kept internally during the break. Close hides the completed session. Show timer opens the controls with keyboard focus; automatic completion does not take keyboard focus. No account, browser, recording or network permission is needed. A session keeps running when switching apps or ending the chat; pausing freezes the remaining time. Quitting and reopening restores the saved deadline. Completion shows the expanded overlay and plays a short sound. There is no background chat wakeup or automatic next session.

If the MCP tools are unavailable and a local terminal tool is available, use this plugin's bundled `scripts/client.py` instead of Computer Use. Resolve the plugin root relative to this skill (`../../`), then call `/usr/bin/python3 -B "<plugin-root>/scripts/client.py" start --duration "421:09"` for an exact requested duration. Use `--seconds` for total seconds; omit duration arguments when none were requested. Pass `--task` only for the task the user supplied. The same client supports status, pause, resume, stop, break and show; a break without a duration defaults to five minutes. Add `--replace` only when the user explicitly requested replacing an active session. Read the returned JSON and claim success only when `ok` is true. Do not start a session merely to check availability. If neither route is available, ask the user to reload plugins or open a new chat; do not pretend that a timed session started.
