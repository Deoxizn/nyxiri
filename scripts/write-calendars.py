#!/usr/bin/env python3
"""write-calendars.py — Replace the clock plugin's calendars.json list.

Called by the Nyxiri settings window's Calendar tab (and nothing else).
Usage: python3 write-calendars.py --file <calendars.json> '<json list>'

The JSON list is one argv, never a shell string, so secret URLs pass
through untouched. Each entry is an object with a name and either a
remote feed (`url`) or a local file (`path`), matching what the clock
plugin's fetch-events.py already reads:

  { "account": "Personal", "name": "My Calendar",
    "url": "https://calendar.google.com/calendar/ical/.../basic.ics",
    "color": "#4285f4", "enabled": true }
  { "account": "Local", "name": "Local Events",
    "path": "~/Documents/calendar.ics",
    "color": "#fbbc05", "enabled": false }

Remote links must be https:// or webcal://: the fetcher refuses plain
http, so accepting one here would only store a feed that never loads.
Validation errors never echo the offending value back, so a secret URL
cannot leak into a log through an error message.

Writes are atomic (temp file + rename) with mode 0600 on the file and
0700 on the parent directory, the same posture as the clock's own
write_private_file. Prints {"status": "ok", "count": N} on stdout, or
{"status": "error", "error": "..."} and exit 1 on failure.
"""

import argparse
import json
import os
import re
import stat
import sys

MAX_ENTRIES = 64
MAX_BYTES = 64 * 1024
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
DEFAULT_COLOR = "#4285f4"


def fail(message):
    print(json.dumps({"status": "error", "error": message}))
    sys.exit(1)


def normalize_entry(entry, index):
    if not isinstance(entry, dict):
        fail(f"entry {index}: not an object")
    name = entry.get("name")
    if not isinstance(name, str) or not name.strip():
        fail(f"entry {index}: missing name")
    url = entry.get("url")
    path = entry.get("path")
    has_url = isinstance(url, str) and url.strip() != ""
    has_path = isinstance(path, str) and path.strip() != ""
    if has_url and has_path:
        fail(f"entry {index}: has both a link and a local path")
    if not has_url and not has_path:
        fail(f"entry {index}: needs a link or a local path")
    if has_url:
        link = url.strip()
        if link.startswith("http://"):
            fail(f"entry {index}: use https://, plain http is refused")
        if not link.startswith("https://") and not link.startswith("webcal://"):
            fail(f"entry {index}: link must start with https:// or webcal://")
        source = {"url": link}
    else:
        source = {"path": path.strip()}
    account = entry.get("account")
    if not isinstance(account, str) or not account.strip():
        account = "Personal"
    color = entry.get("color")
    if not isinstance(color, str) or not HEX_COLOR.match(color):
        color = DEFAULT_COLOR
    enabled = entry.get("enabled", True)
    if not isinstance(enabled, bool):
        enabled = True
    out = {
        "account": account.strip()[:128],
        "name": name.strip()[:128],
        "color": color,
        "enabled": enabled,
    }
    out.update(source)
    return out


def write_private(directory, name, data):
    os.makedirs(directory, mode=0o700, exist_ok=True)
    try:
        os.chmod(directory, 0o700)
    except OSError:
        pass
    tmp_name = f".{name}.tmp.{os.getpid()}"
    tmp_path = os.path.join(directory, tmp_name)
    try:
        fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.write(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, os.path.join(directory, name))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser(description="Replace calendars.json")
    parser.add_argument("--file", required=True, help="Path to calendars.json")
    parser.add_argument("entries", help="JSON list of calendar entries")
    args = parser.parse_args()

    raw = args.entries.encode("utf-8")
    if len(raw) > MAX_BYTES:
        fail("calendar list is too large")
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        fail("calendar list is not valid JSON")
    if not isinstance(parsed, list):
        fail("calendar list must be a JSON list")
    if len(parsed) > MAX_ENTRIES:
        fail("too many calendars")

    normalized = [normalize_entry(e, i) for i, e in enumerate(parsed)]
    data = (json.dumps(normalized, indent=2) + "\n").encode("utf-8")
    try:
        write_private(
            os.path.dirname(os.path.abspath(args.file)),
            os.path.basename(args.file),
            data,
        )
    except OSError as e:
        fail(f"could not write calendars file: {e.strerror or e}")
    print(json.dumps({"status": "ok", "count": len(normalized)}))


if __name__ == "__main__":
    main()
