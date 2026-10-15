import argparse
import os
from pathlib import Path
import re


def next_version(version, bump):
    if bump not in ("patch", "minor", "major", "current"):
        raise ValueError("choose patch, minor, major, or current")
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("expected a stable version")
    parts = list(map(int, version.split(".")))
    if bump != "current":
        index = {"major": 0, "minor": 1, "patch": 2}[bump]
        parts[index] += 1
        parts[index + 1:] = [0] * (2 - index)
    return ".".join(map(str, parts))


def read_version(root):
    matches = re.findall(r'^  @version "([^"\n]+)"$', (root / "mix.exs").read_text(encoding="utf-8"), re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("expected exactly one project version")
    next_version(matches[0], "current")
    return matches[0]


def bump_package(root, bump):
    before = read_version(root)
    after = next_version(before, bump)
    readme_path = root / "README.md"
    readme = readme_path.read_text(encoding="utf-8")
    pattern = r'(\{:lingo,\s*"~> )\d+\.\d+\.\d+("\})'
    updated, count = re.subn(pattern, lambda m: m[1] + after + m[2], readme)
    if count != 1:
        raise ValueError("expected one README installation version")
    if bump != "current":
        project = root / "mix.exs"
        text = project.read_text(encoding="utf-8").replace(f'  @version "{before}"', f'  @version "{after}"')
        project.write_text(text, encoding="utf-8", newline="\n")
    if updated != readme:
        readme_path.write_text(updated, encoding="utf-8", newline="\n")
    return after


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bump", choices=("patch", "minor", "major", "current"))
    args = parser.parse_args()
    version = bump_package(Path(__file__).resolve().parents[2], args.bump)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"version={version}\ntag=v{version}\n")
    print(f"Release version: {version}")
