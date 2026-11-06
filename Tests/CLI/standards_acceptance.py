#!/usr/bin/env python3
"""Exercise the real CLI with private pipes and pseudo-terminals only."""

import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

CLI = str(Path(sys.argv[1]).resolve())
checks = 0


def require(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


def run(*arguments, expected=0, env=None):
    result = subprocess.run(
        [CLI, *arguments],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    require(
        result.returncode == expected,
        f"{arguments!r}: expected {expected}, got {result.returncode}: {result.stderr}",
    )
    return result


def read_pty(master, process, timeout=10, until=None):
    result = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if ready:
            try:
                part = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not part:
                break
            result += part
            if until and until in result:
                return result
        elif process.poll() is not None:
            break
    return result


def terminal(arguments, environment, interruption=None, twice=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 5, 40, 0, 0))
    process = subprocess.Popen(
        [CLI, *arguments],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=environment,
        start_new_session=True,
    )
    os.close(slave)
    try:
        started = time.monotonic()
        if interruption:
            output = read_pty(master, process, until=b"PAGER-READY")
            require(b"PAGER-READY" in output, "The configured pager did not start.")
            process.send_signal(interruption)
            if twice:
                time.sleep(0.1)
                process.send_signal(interruption)
            output += read_pty(master, process)
        else:
            output = read_pty(master, process)
        status = process.wait(timeout=5)
        return (
            status,
            output.decode("utf-8", errors="strict"),
            time.monotonic() - started,
        )
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.close(master)


version = run("--version").stdout.strip()
require(
    re.fullmatch(r"curfew-ctl \d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?", version)
    is not None,
    "The CLI did not print a semantic version.",
)
require(run("-V").stdout.strip() == version, "The short version flag disagrees.")
reader, writer = os.pipe()
os.close(reader)
closed = subprocess.Popen(
    [CLI, "--help"], stdin=subprocess.DEVNULL, stdout=writer, stderr=subprocess.PIPE
)
os.close(writer)
_, closed_errors = closed.communicate(timeout=10)
require(
    closed.returncode in (-signal.SIGPIPE, 128 + signal.SIGPIPE),
    "Closed stdout did not return SIGPIPE/141.",
)
require(not closed_errors, "Closed stdout printed an error.")

help_text = run("--help").stdout
require(help_text.startswith("EXAMPLES"), "Help did not lead with examples.")
require(
    "beta" in help_text.lower() and "setup" in help_text and "completion" in help_text,
    "Help did not expose beta status, setup, and completion.",
)
require(
    run("help", "schedule").stdout == run("schedule", "--help").stdout,
    "The two help forms disagree.",
)
for arguments in [
    ("activity", "--days", "0"),
    ("activity", "--days", "1", "--days=2"),
    ("completion", "unknown"),
    ("status", "--quiet", "--verbose"),
]:
    result = run(*arguments, "--json", expected=64)
    document = json.loads(result.stdout)
    require(
        document["schema_version"] == 1 and document["status"] == "error",
        "A JSON failure lacked its versioned envelope.",
    )
    require(
        document["error"]["exit_status"] == 64
        and document["error"]["code"] in result.stderr,
        "JSON and stderr failures disagree.",
    )
for arguments in [
    ("status",),
    ("schedule", "show"),
    ("request", "status", "977D6355-106A-4C51-B758-66893199EC92"),
]:
    document = json.loads(run(*arguments, "--json").stdout)
    require(
        document["schema_version"] == 1 and document["status"] == "ok",
        "A read command lacked its versioned result.",
    )
require(
    json.loads(run("--json", "status").stdout)["status"] == "ok",
    "A root JSON option did not reach the default command.",
)

with tempfile.TemporaryDirectory(prefix="curfew-cli-terminal-") as temporary:
    directory = Path(temporary)
    for shell in ["bash", "zsh", "fish"]:
        script = run("completion", shell).stdout
        require(
            "curfew-ctl" in script and "break-glass" in script and "setup" in script,
            f"The {shell} completion omitted commands.",
        )
        path = directory / f"completion.{shell}"
        path.write_text(script)
        executable = shutil.which(shell)
        if executable:
            require(
                subprocess.run(
                    [executable, "-n", str(path)], capture_output=True
                ).returncode
                == 0,
                f"The generated {shell} script failed its native syntax check.",
            )
            if shell == "bash":
                load = [
                    executable,
                    "--noprofile",
                    "--norc",
                    "-c",
                    'source "$1"; complete -p curfew-ctl',
                    "bash",
                    str(path),
                ]
            elif shell == "zsh":
                load = [
                    executable,
                    "-f",
                    "-c",
                    'autoload -Uz compinit; compinit -D; source "$1"; whence -w _curfew-ctl',
                    "zsh",
                    str(path),
                ]
            else:
                load = [
                    executable,
                    "--no-config",
                    "-c",
                    'source "$argv[1]"; complete -C "curfew-ctl "',
                    str(path),
                ]
            clean_environment = {
                **os.environ,
                "HOME": str(directory),
                "ZDOTDIR": str(directory),
            }
            clean_environment.pop("BASH_ENV", None)
            loaded = subprocess.run(
                load, capture_output=True, env=clean_environment, timeout=10
            )
            require(
                loaded.returncode == 0, f"The generated {shell} script did not load."
            )
    pager = directory / "fake pager"
    pager.write_text(
        "#!/usr/bin/python3\nimport os,sys,time\n"
        "sys.stderr.write('PAGER-READY\\n');sys.stderr.flush()\n"
        "time.sleep(float(os.environ.get('CURFEW_TEST_PAGER_DELAY','0')))\n"
        "sys.stdout.write(sys.stdin.read())\n"
    )
    pager.chmod(0o700)
    environment = {
        **os.environ,
        "CI": "0",
        "NO_COLOR": "1",
        "COLUMNS": "40",
        "LINES": "5",
        "TERM": "xterm",
        "PAGER": f"'{pager}'",
    }
    status, text, _ = terminal(["--help"], environment)
    require(status == 0 and "PAGER-READY" in text, "Long terminal help skipped PAGER.")
    require("\x1b" not in text, "NO_COLOR output contained an ANSI escape.")
    status, text, _ = terminal(["--help", "--no-pager"], environment)
    require(
        status == 0 and "PAGER-READY" not in text, "--no-pager did not bypass PAGER."
    )
    status, text, _ = terminal(["--help", "--no-input"], environment)
    require(
        status == 0 and "PAGER-READY" not in text, "--no-input did not bypass PAGER."
    )
    require(
        "PAGER-READY" not in run("--help", env=environment).stderr,
        "Piped output invoked a pager.",
    )
    status, text, _ = terminal(["status", "--no-pager"], environment)
    require(
        status == 0 and text.startswith("Curfew status\r\n\r\n  "),
        "Terminal results lacked the heading and margin.",
    )
    require(
        all(len(line) <= 40 for line in text.splitlines()),
        "Terminal prose exceeded 40 columns.",
    )
    environment["CURFEW_TEST_PAGER_DELAY"] = "1.5"
    status, text, elapsed = terminal(["--help"], environment, signal.SIGINT)
    require(
        status == 130 and elapsed >= 1,
        "The first interrupt abandoned the protected step.",
    )
    require(
        "Stopping after the current step" in text
        and "Completed changes were kept" in text,
        "The interruption did not explain what was kept.",
    )
    status, _, elapsed = terminal(["--help"], environment, signal.SIGINT, twice=True)
    require(
        status == 130 and elapsed < 1, "The second interrupt did not stop immediately."
    )
    status, _, _ = terminal(["--help"], environment, signal.SIGTERM)
    require(status == 143, "SIGTERM did not return 143.")

print(
    json.dumps(
        {"checks": checks, "fish_syntax_checked": shutil.which("fish") is not None}
    )
)
