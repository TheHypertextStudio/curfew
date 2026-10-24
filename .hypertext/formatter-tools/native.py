#!/usr/bin/env python3
"""Pinned native formatters. Network access occurs only in explicit setup commands."""

import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
RUST_VERSION = "1.98.1"
SWIFT_VERSION = "0.64.0"
SWIFT_ARCHIVE = "95ea62625d0b898a7af870293311ae6f09e4a3147ecd900593687e4b9ab2fd98"
SWIFT_BINARY = "c2b098cc3ae30ff9fdd1acf7342f9b6efac4c403cf0b4e2d473690c92ac41210"
CURFEW_BINARY = "136d4a990a7c63f313baa9081ffa451cb1988eacac3128e810564ca1efbf3083"
MESON_VERSION = "1.10.2"
BLUEPRINT_COMMIT = "ed35ac74de0c1bb1f5e852410b97edd1f08904c9"  # upstream v0.22.2
BLUEPRINT_SHA256 = "710b73a994fb63f6a2c75749ff8794a3b7bafce8f38a7a858184920017d68cc8"
BLUEPRINT_ARCHIVE = CACHE / f"hypertext-formatters/blueprint/{BLUEPRINT_COMMIT}.tar.gz"


def checked_bytes(data, digest):
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError(
            "formatter checksum mismatch; run setup after reviewing the pin"
        )
    return data


def swift_path():
    if (ROOT / "scripts/swiftformat.sh").exists():
        return CACHE / "curfew/swiftformat/0.63.1/swiftformat", CURFEW_BINARY
    return (
        CACHE / f"hypertext-formatters/swiftformat/{SWIFT_VERSION}/swiftformat",
        SWIFT_BINARY,
    )


def setup(tool):
    if tool == "swift":
        if platform.system() != "Darwin":
            raise RuntimeError("the pinned SwiftFormat archive requires macOS")
        path, digest = swift_path()
        if path.exists():
            checked_bytes(path.read_bytes(), digest)
            return
        wrapper = ROOT / "scripts/swiftformat.sh"
        if wrapper.exists():
            subprocess.run([str(wrapper), "--version"], check=True)
            checked_bytes(path.read_bytes(), digest)
            return
        url = f"https://github.com/nicklockwood/SwiftFormat/releases/download/{SWIFT_VERSION}/swiftformat.zip"
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "swiftformat.zip"
            with urllib.request.urlopen(url, timeout=120) as response:
                archive.write_bytes(checked_bytes(response.read(), SWIFT_ARCHIVE))
            with zipfile.ZipFile(archive) as bundle:
                binary = checked_bytes(bundle.read("swiftformat"), SWIFT_BINARY)
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
                output.write(binary)
                name = output.name
            os.chmod(name, 0o755)
            os.replace(name, path)
    elif tool == "blueprint":
        if BLUEPRINT_ARCHIVE.exists():
            checked_bytes(BLUEPRINT_ARCHIVE.read_bytes(), BLUEPRINT_SHA256)
            return
        url = f"https://gitlab.gnome.org/GNOME/blueprint-compiler/-/archive/{BLUEPRINT_COMMIT}/blueprint-compiler-{BLUEPRINT_COMMIT}.tar.gz"
        with urllib.request.urlopen(url, timeout=120) as response:
            data = checked_bytes(response.read(), BLUEPRINT_SHA256)
        BLUEPRINT_ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=BLUEPRINT_ARCHIVE.parent, delete=False
        ) as output:
            output.write(data)
            name = output.name
        os.replace(name, BLUEPRINT_ARCHIVE)
    elif tool == "rust":
        subprocess.run(
            [
                "rustup",
                "toolchain",
                "install",
                RUST_VERSION,
                "--profile",
                "minimal",
                "--component",
                "rustfmt",
            ],
            check=True,
        )
    elif tool == "meson":
        environment = CACHE / f"hypertext-formatters/meson/{MESON_VERSION}"
        subprocess.run(["uv", "venv", "--allow-existing", str(environment)], check=True)
        subprocess.run(
            [
                "uv",
                "pip",
                "install",
                "--python",
                str(environment / "bin/python"),
                f"meson=={MESON_VERSION}",
            ],
            check=True,
        )


def run(argv, source):
    result = subprocess.run(argv, input=source, capture_output=True, cwd=ROOT)
    if result.returncode:
        sys.stderr.buffer.write(result.stderr)
        raise RuntimeError(f"native formatter exited with status {result.returncode}")
    sys.stderr.buffer.write(result.stderr)
    sys.stdout.buffer.write(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tool",
        choices=[
            "setup-swift",
            "setup-rust",
            "setup-meson",
            "setup-blueprint",
            "swift",
            "rust",
            "meson",
            "blueprint",
            "swift-options",
        ],
    )
    parser.add_argument("--path", default="input.swift")
    parser.add_argument("--edition", choices=["2021", "2024"], default="2024")
    args = parser.parse_args()
    if args.tool.startswith("setup-"):
        setup(args.tool.removeprefix("setup-"))
        return
    source = sys.stdin.buffer.read()
    if args.tool == "swift-options":
        # SwiftFormat's config is one option per line, with full-line # comments.
        # Preserve directive order and value contents; normalize only line layout.
        lines = []
        for original in source.decode("utf-8").splitlines():
            line = original.strip()
            if not line or line.startswith("#"):
                lines.append(line)
                continue
            match = re.fullmatch(r"(--[A-Za-z][A-Za-z0-9_-]*)(?:[ \t]+(.*))?", line)
            if not match:
                raise RuntimeError(
                    "unsupported SwiftFormat option syntax; expected --option value"
                )
            lines.append(match[1] + (" " + match[2] if match[2] is not None else ""))
        sys.stdout.buffer.write(("\n".join(lines).rstrip() + "\n").encode("utf-8"))
    elif args.tool == "swift":
        path, digest = swift_path()
        if not path.exists():
            raise RuntimeError("SwiftFormat is not prepared; run native.py setup-swift")
        checked_bytes(path.read_bytes(), digest)
        argv = [
            str(path),
            "stdin",
            "--stdin-path",
            args.path,
            "--quiet",
            "--cache",
            "ignore",
        ]
        config = ROOT / ".swiftformat"
        if config.exists():
            argv += ["--config", str(config)]
        run(argv, source)
    elif args.tool == "rust":
        # rustup run does not install missing toolchains. skip_children prevents
        # a staged module declaration from reading or rewriting working files.
        run(
            [
                "rustup",
                "run",
                RUST_VERSION,
                "rustfmt",
                "--emit",
                "stdout",
                "--edition",
                args.edition,
                "--config",
                "skip_children=true",
            ],
            source,
        )
    elif args.tool == "blueprint":
        if not BLUEPRINT_ARCHIVE.exists():
            raise RuntimeError(
                "Blueprint formatter is not prepared; run native.py setup-blueprint"
            )
        checked_bytes(BLUEPRINT_ARCHIVE.read_bytes(), BLUEPRINT_SHA256)
        # The upstream formatter/tokenizer are pure Python. Import only those
        # modules, avoiding the CLI's GTK introspection and display dependencies.
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "blueprintcompiler"
            package.mkdir()
            with tarfile.open(BLUEPRINT_ARCHIVE) as archive:
                for name in ["__init__", "formatter", "tokenizer", "errors", "utils"]:
                    member = f"blueprint-compiler-{BLUEPRINT_COMMIT}/blueprintcompiler/{name}.py"
                    with archive.extractfile(member) as module:
                        (package / f"{name}.py").write_bytes(module.read())
            sys.path.insert(0, temporary)
            from blueprintcompiler.formatter import format as blueprint_format

            output = blueprint_format(source.decode("utf-8"))
            sys.stdout.buffer.write(output.encode("utf-8"))
    else:
        meson = CACHE / f"hypertext-formatters/meson/{MESON_VERSION}/bin/meson"
        if not meson.exists():
            raise RuntimeError(
                "Meson formatter is not prepared; run native.py setup-meson"
            )
        version = subprocess.check_output([str(meson), "--version"], text=True).strip()
        if version != MESON_VERSION:
            raise RuntimeError("Meson formatter version differs from the reviewed pin")
        run([str(meson), "format", "--source-file-path", args.path, "-"], source)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"format: {error}", file=sys.stderr)
        sys.exit(1)
