"""Shared exact-duration parsing for MCP tools and the local command-line client."""
import re

MAX_SECONDS = 2_147_483_647
CLOCK_PATTERN = "[0-9]+:[0-5][0-9]"


def parse_clock(text):
    if not isinstance(text, str) or len(text) > 32 or re.fullmatch(CLOCK_PATTERN, text) is None:
        return None
    minutes, seconds = text.split(":")
    value = int(minutes) * 60 + int(seconds)
    return value if 1 <= value <= MAX_SECONDS else None
