#!/usr/bin/env python3
"""Extract printable strings from a binary, for reconnaissance on a local copy.

Only intended for binaries you legitimately have on disk (for example the
application you are studying for interoperability). It performs a single pass
over the file and prints runs of printable characters, optionally filtered by
regular expression.

Usage:
    python tools/extract_strings.py <binary> [--min 5] [--grep PATTERN] [--urls]

Examples:
    python tools/extract_strings.py "<install root>/data/app.so" --grep player_api
    python tools/extract_strings.py data/app.so --urls --min 12
"""

from __future__ import annotations

import argparse
import re
import sys

# Printable ASCII plus the common UTF-8 continuation range, so single-byte and
# UTF-8 text are both recovered without decoding errors.
_PRINTABLE = re.compile(rb"[\x20-\x7e\xc2-\xf4][\x20-\x7e\x80-\xbf]*")
_URL = re.compile(
    r"(?:https?://|/)[\w\-./?=&%:+#~]{4,}",
)


def extract(path: str, minimum: int):
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1 << 20)
            if not chunk:
                break
            for match in _PRINTABLE.finditer(chunk):
                text = match.group().decode("utf-8", errors="replace")
                if len(text) >= minimum:
                    yield text


def main() -> int:
    # Windows consoles default to a legacy code page; make non-ASCII output
    # printable instead of raising UnicodeEncodeError.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover - non-reconfigurable stream
        pass

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary", help="file to scan")
    parser.add_argument("--min", type=int, default=5, help="minimum string length (default: 5)")
    parser.add_argument("--grep", help="only print strings matching this regex")
    parser.add_argument("--urls", action="store_true", help="only print URL/path-like strings")
    parser.add_argument("--unique", action="store_true", help="drop duplicates")
    parser.add_argument("--count", action="store_true", help="print the number of matches instead of the matches")
    args = parser.parse_args()

    pattern = re.compile(args.grep) if args.grep else None
    seen: set[str] = set()
    total = 0

    try:
        for text in extract(args.binary, args.min):
            if pattern and not pattern.search(text):
                continue
            if args.urls and not _URL.search(text):
                continue
            if args.unique:
                if text in seen:
                    continue
                seen.add(text)
            total += 1
            if not args.count:
                print(text)
    except FileNotFoundError:
        print(f"not found: {args.binary}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"cannot read {args.binary}: {error}", file=sys.stderr)
        return 1

    if args.count:
        print(total)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
