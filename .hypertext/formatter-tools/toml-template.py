#!/usr/bin/env python3
"""Protect the authored Worker route placeholder while formatting TOML scaffold."""

import re
import subprocess
import sys

PLACEHOLDER = b"__CURFEW_LICENSE_WORKER_ROUTE__"
SENTINEL = b"__HYPERTEXT_TOML_ROUTE_PLACEHOLDER__"


def main():
    source = sys.stdin.buffer.read()
    if source.count(PLACEHOLDER) != 1 or SENTINEL in source:
        raise ValueError("expected exactly one unambiguous Worker route placeholder")
    pattern = rb"(?m)^[ \t]*" + PLACEHOLDER + rb"[ \t]*$"
    scaffold, count = re.subn(pattern, b"# " + SENTINEL, source)
    if count != 1:
        raise ValueError("Worker route placeholder must occupy its own line")
    result = subprocess.run(sys.argv[1:], input=scaffold, capture_output=True)
    if result.returncode:
        sys.stderr.buffer.write(result.stderr)
        return result.returncode
    output, count = re.subn(
        rb"(?m)^[ \t]*#[ \t]*" + SENTINEL + rb"[ \t]*$", PLACEHOLDER, result.stdout
    )
    if count != 1 or SENTINEL in output:
        raise ValueError(
            "TOML formatter did not retain the protected route placeholder"
        )
    sys.stdout.buffer.write(output)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"format: {error}", file=sys.stderr)
        sys.exit(1)
