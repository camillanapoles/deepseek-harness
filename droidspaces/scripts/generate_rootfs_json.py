#!/usr/bin/env python3
"""Write the Droidspaces rootfs feed for this repository.

The feed metadata comes from the ``droidspaces.*`` labels of every
``templates/<arch>/<Name>.Dockerfile``; the download data comes from the
assets of the published release.

    generate_rootfs_json.py [--lint] [--release <tag>] [repository root]

``--lint`` only validates the template labels: no network access, no write.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

LABEL_PREFIX = "droidspaces."
REQUIRED_LABELS = ("name", "distro", "description")
DEFAULT_AUTHOR = "DeepSeek-Dsh-Agent"
ASSET_MARKER = "-Droidspaces-rootfs-"
GITHUB_API = "https://api.github.com/repos/{repository}/releases"


def parse_labels(dockerfile: Path) -> dict[str, str]:
    """Return every ``droidspaces.*`` label of a Dockerfile."""
    text = dockerfile.read_text(encoding="utf-8").replace("\\\n", " ")
    labels: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.upper().startswith("LABEL "):
            continue
        for token in shlex.split(stripped[len("LABEL "):]):
            key, _, value = token.partition("=")
            if key.startswith(LABEL_PREFIX):
                labels[key[len(LABEL_PREFIX):]] = value
    return labels


def collect_templates(root: Path) -> dict[tuple[str, str], dict[str, str]]:
    """Return the labels of every template, keyed by architecture and name."""
    templates: dict[tuple[str, str], dict[str, str]] = {}
    problems: list[str] = []
    for dockerfile in sorted(root.glob("templates/*/*.Dockerfile")):
        architecture = dockerfile.parent.name
        name = dockerfile.name.removesuffix(".Dockerfile")
        labels = {"author": DEFAULT_AUTHOR, **parse_labels(dockerfile)}
        missing = [label for label in REQUIRED_LABELS if not labels.get(label)]
        if missing:
            problems.append(
                f"{dockerfile}: missing LABEL "
                + ", ".join(LABEL_PREFIX + label for label in missing)
            )
        templates[(architecture, name)] = labels
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        raise SystemExit(1)
    if not templates:
        print("no templates found under templates/<arch>/", file=sys.stderr)
        raise SystemExit(1)
    return templates


def parse_asset_name(asset_name: str) -> tuple[str, str, str, str] | None:
    """Split ``<Name>-Droidspaces-rootfs-<arch>-<date>-<version>.tar.xz``."""
    if ASSET_MARKER not in asset_name or not asset_name.endswith(".tar.xz"):
        return None
    prefix, rest = asset_name.split(ASSET_MARKER, 1)
    parts = rest.removesuffix(".tar.xz").split("-")
    if len(parts) < 3:
        return None
    return prefix, parts[0], parts[1], "-".join(parts[2:])


def fetch_release(repository: str, tag: str | None) -> dict:
    """Return the published release, by tag or the latest one."""
    url = f"{GITHUB_API.format(repository=repository)}/latest"
    if tag:
        url = f"{GITHUB_API.format(repository=repository)}/tags/{tag}"
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        print(f"error fetching the release of {repository}: {error.code} {error.reason}", file=sys.stderr)
        raise SystemExit(1) from error


def sha256_of(path: Path) -> str:
    """Return the hex digest of a file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true", help="validate the template labels only")
    parser.add_argument("--release", help="the release tag to read, instead of the latest one")
    parser.add_argument("--assets", help="a directory holding the release assets, to compute their digests")
    parser.add_argument("root", nargs="?", default=str(Path(__file__).resolve().parent.parent))
    arguments = parser.parse_args()

    root = Path(arguments.root).resolve()
    templates = collect_templates(root)
    print(f"found {len(templates)} templates")
    if arguments.lint:
        return

    repository = os.environ.get("GITHUB_REPOSITORY", "camillanapoles/deepseek-harness")
    release = fetch_release(repository, arguments.release)
    print(f"release {release.get('tag_name')} with {len(release.get('assets', []))} assets")

    assets: dict[tuple[str, str], tuple[dict, str, str]] = {}
    for asset in release.get("assets", []):
        parsed = parse_asset_name(asset["name"])
        if parsed is None:
            continue
        name, architecture, build_date, version = parsed
        assets[(architecture, name)] = (asset, build_date, version)

    entries: list[dict] = []
    missing: list[str] = []
    for (architecture, name), labels in templates.items():
        if (architecture, name) not in assets:
            missing.append(f"{architecture}/{name}")
            continue
        asset, build_date, version = assets[(architecture, name)]
        digest = str(asset.get("digest") or "")
        if digest.startswith("sha256:"):
            checksum = digest.removeprefix("sha256:")
        elif arguments.assets:
            local = Path(arguments.assets) / asset["name"]
            if not local.is_file():
                print(f"error: the asset {local} is missing", file=sys.stderr)
                raise SystemExit(1) from None
            checksum = sha256_of(local)
        else:
            print(f"error: the release reports no digest for {asset['name']}", file=sys.stderr)
            raise SystemExit(1)
        entries.append(
            {
                **labels,
                "architecture": architecture,
                "file": asset["name"],
                "download_url": asset["browser_download_url"],
                "sha256": checksum,
                "size_bytes": asset["size"],
                "version": version,
                "build_date": build_date,
            }
        )

    if missing:
        print("templates without an asset in the release:", file=sys.stderr)
        for item in missing:
            print(f"  {item}", file=sys.stderr)
        raise SystemExit(1)

    entries.sort(key=lambda entry: (entry["distro"], entry["architecture"], entry["name"]))
    output = root / "rootfs.json"
    output.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} entries to {output}")


if __name__ == "__main__":
    main()
