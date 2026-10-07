#!/bin/bash
set -euo pipefail
POMODORO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POMODORO_MODE="${1:-run}"
POMODORO_BUNDLE="$POMODORO_ROOT/plugins/pomodoro-notch/native/Pomodoro Notch.app"
case "$POMODORO_MODE" in run|--verify|--logs|--telemetry|--debug) ;; *) printf 'Unknown run mode\n' >&2; exit 2;; esac
/usr/bin/python3 "$POMODORO_ROOT/plugins/pomodoro-notch/scripts/client.py" quit --no-launch >/dev/null 2>&1 || true
"$POMODORO_ROOT/script/build.sh"
/usr/bin/open "$POMODORO_BUNDLE"
case "$POMODORO_MODE" in
    --verify)
        /usr/bin/python3 "$POMODORO_ROOT/plugins/pomodoro-notch/scripts/client.py" status
        ;;
    --logs|--telemetry)
        /usr/bin/log stream --info --style compact --predicate 'process == "PomodoroNotch"'
        ;;
    --debug)
        /usr/bin/lldb -n PomodoroNotch
        ;;
esac
