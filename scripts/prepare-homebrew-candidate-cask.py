"""Prepare a disposable cask from the current public Curfew recipe."""

from pathlib import Path
import re
import sys


def prepare(recipe, image, version, digest):
    versions = re.findall(r'^  version "(0\.0\.(?:0|[1-9][0-9]*))"$', recipe, re.M)
    if len(versions) != 1:
        raise ValueError("Expected exactly one version in the public Curfew cask.")
    public_version = versions[0]
    if not re.fullmatch(r"0\.0\.(?:0|[1-9][0-9]*)", version) or int(
        version.split(".")[-1]
    ) <= int(public_version.split(".")[-1]):
        raise ValueError("The candidate must be newer than the public Curfew cask.")
    if not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Expected the candidate DMG SHA-256.")

    recipe = recipe.replace(
        f'  version "{public_version}"\n', f'  version "{version}"\n', 1
    )
    recipe, digests = re.subn(
        r'^  sha256 "[a-f0-9]{64}"$', f'  sha256 "{digest}"', recipe, flags=re.M
    )
    recipe, urls = re.subn(
        r'^  url "https://github\.com/TheHypertextStudio/curfew/releases/download/[^"]+"$',
        lambda _: f'  url "{image.as_uri()}"',
        recipe,
        flags=re.M,
    )
    if (digests, urls) != (1, 1):
        raise ValueError("Expected the public Curfew checksum and release URL.")
    return public_version, recipe


if __name__ == "__main__":
    source, destination, image, version, digest = sys.argv[1:]
    try:
        public_version, recipe = prepare(
            Path(source).read_text(), Path(image), version, digest
        )
    except ValueError as error:
        sys.exit(str(error))
    staged = Path(destination)
    if not staged.exists() or staged.read_text() != recipe:
        staged.write_text(recipe)
    print(public_version)
