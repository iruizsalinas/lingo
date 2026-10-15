import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

from release_version import read_version


def package_release(root):
    output = root / ".release"
    if not (output / "package.tar").is_file() or not (root / "doc/index.html").is_file():
        raise ValueError("build the Hex package and documentation first")
    with tarfile.open(output / "docs.tar.gz", "w:gz") as archive:
        for path in sorted((root / "doc").rglob("*")):
            if path.is_symlink():
                raise ValueError("unexpected symlink in documentation")
            if path.is_file():
                archive.add(path, arcname=path.relative_to(root / "doc").as_posix(), recursive=False)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    metadata = {"name": "lingo", "version": read_version(root), "commit": commit, "files": {}}
    for name in ("package.tar", "docs.tar.gz"):
        metadata["files"][name] = hashlib.sha256((output / name).read_bytes()).hexdigest()
    (output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    package_release(Path(__file__).resolve().parents[2])
