#!/usr/bin/env python3
"""Add a release to Silo's source feed (source.json) so installed copies see the update."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path

KEEP_RELEASES = 10
CARRIED_KEYS = ("releaseChannels", "version", "versionDate", "versionDescription", "downloadURL", "size", "sha256")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True, help="source.json to update in place")
    p.add_argument("--ipa", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--download-url", required=True)
    p.add_argument("--notes", default="")
    p.add_argument("--carry-from", help="previously published source.json whose releases are kept")
    args = p.parse_args()

    source_path = Path(args.source)
    ipa = Path(args.ipa)
    data = json.loads(source_path.read_text(encoding="utf-8"))

    if args.carry_from and Path(args.carry_from).exists():
        previous = json.loads(Path(args.carry_from).read_text(encoding="utf-8"))
        old_apps = {a.get("bundleIdentifier"): a for a in previous.get("apps", [])}
        for new_app in data.get("apps", []):
            old_app = old_apps.get(new_app.get("bundleIdentifier"))
            for key in CARRIED_KEYS:
                if old_app and key in old_app:
                    new_app[key] = old_app[key]

    app = next((a for a in data.get("apps", []) if a.get("bundleIdentifier") == args.bundle_id), None)
    if app is None:
        raise SystemExit(f"{args.bundle_id} is not in {source_path}")

    release = {
        "version": args.version,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": args.notes.strip() or f"Silo Store {args.version}",
        "downloadURL": args.download_url,
        "size": ipa.stat().st_size,
        "sha256": sha256(ipa),
    }

    channels = app.setdefault("releaseChannels", [])
    track = next((t for t in channels if t.get("track") == "stable"), None)
    if track is None:
        track = {"track": "stable", "releases": []}
        channels.insert(0, track)

    releases = [r for r in track.get("releases", []) if r.get("version") != args.version]
    track["releases"] = ([release] + releases)[:KEEP_RELEASES]

    # Older clients read these top-level fields instead of releaseChannels.
    app.update({
        "version": release["version"],
        "versionDate": release["date"],
        "versionDescription": release["localizedDescription"],
        "downloadURL": release["downloadURL"],
        "size": release["size"],
        "sha256": release["sha256"],
    })

    source_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{source_path}: {args.bundle_id} -> {args.version}")


if __name__ == "__main__":
    main()
