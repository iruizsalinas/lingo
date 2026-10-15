import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request

API = "https://hex.pm/api"


def request_json(url, data=None, headers=None, missing_ok=False):
    request = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        error.close()
        if missing_ok and error.code == 404:
            return None
        raise RuntimeError(f"HTTP {error.code} from {url}") from None
    return json.loads(body) if body else {}


def get_release(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("expected a stable release version")
    return request_json(f"{API}/packages/lingo/releases/{version}", missing_ok=True)


def validate_artifacts(directory, version, commit):
    metadata = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if (metadata["name"], metadata["version"], metadata["commit"]) != ("lingo", version, commit):
        raise ValueError("release artifact does not match the tested commit and version")
    if set(metadata["files"]) != {"package.tar", "docs.tar.gz"}:
        raise ValueError("unexpected release artifact files")
    for name, expected in metadata["files"].items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"release artifact checksum mismatch: {name}")
    return metadata


def mask(value):
    if not isinstance(value, str) or not value:
        raise ValueError("empty authentication token")
    escaped = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::add-mask::{escaped}", flush=True)
    return value


def authenticate():
    key = os.environ.get("HEX_API_KEY", "")
    if not key or any(character.isspace() for character in key):
        raise ValueError("HEX_API_KEY must contain a valid Hex API key")
    return mask(key)


def publish(directory, version, commit):
    metadata = validate_artifacts(directory, version, commit)
    existing = get_release(version)
    if existing is not None and existing.get("checksum") != metadata["files"]["package.tar"]:
        raise ValueError("published version has different contents; refusing to replace it")
    token = authenticate()
    headers = {"Authorization": token, "Content-Type": "application/octet-stream"}
    if existing is None:
        request_json(f"{API}/packages/lingo/releases?replace=false", data=(directory / "package.tar").read_bytes(), headers=headers)
    else:
        print(f"lingo {version} already has identical package contents; uploading docs only.")
    request_json(f"{API}/packages/lingo/releases/{version}/docs", data=(directory / "docs.tar.gz").read_bytes(), headers=headers)
    print(f"Published lingo {version} and HexDocs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("check", "publish"))
    parser.add_argument("version")
    parser.add_argument("--bump", choices=("patch", "minor", "major", "current"), default="current")
    args = parser.parse_args()
    if args.command == "check":
        should_release = get_release(args.version) is None or args.bump == "current"
        if output := os.environ.get("GITHUB_OUTPUT"):
            with open(output, "a", encoding="utf-8") as stream:
                stream.write(f"should_release={str(should_release).lower()}\n")
        print("Version is ready for release." if should_release else "Version already published; skipping.")
    else:
        publish(Path(".release"), args.version, os.environ["RELEASE_COMMIT"])
