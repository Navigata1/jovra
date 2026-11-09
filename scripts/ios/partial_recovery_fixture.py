#!/usr/bin/env python3
"""Prepare or inspect the opt-in partial-recovery relaunch fixture."""

import argparse
from contextlib import ExitStack, contextmanager
from hashlib import sha256
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
from uuid import UUID, uuid4

DAMAGE = b"JOVRA synthetic damaged segment for cold relaunch\n"
TITLE = "Partial recovery fixture"
MEDIA_NAMES = ("segment-0.mp4", "segment-1.mp4")


class FixtureError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise FixtureError(message)


def canonical_uuid(value):
    try:
        return str(UUID(value)).upper() == value
    except ValueError:
        return False


def file_identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@contextmanager
def directory(name, parent=None):
    fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        yield fd
    finally:
        os.close(fd)


def regular_file(name, parent, limit):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and 0 < info.st_size <= limit,
                f"Expected one small, regular owned file: {name}")
        data = stream.read(limit + 1)
        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
        require(len(data) == info.st_size and file_identity(current) == file_identity(info)
                and file_identity(os.fstat(stream.fileno())) == file_identity(info),
                f"Fixture file changed while reading: {name}")
        return data, {"sha256": sha256(data).hexdigest(), "bytes": len(data), "mtimeNs": info.st_mtime_ns,
                      "inode": info.st_ino, "device": info.st_dev}


@contextmanager
def fixture(sessions):
    ids = os.listdir(sessions)
    require(len(ids) == 1 and canonical_uuid(ids[0]), "Expected exactly one synthetic UUID session")
    session_id = ids[0]
    with directory(session_id, sessions) as folder, directory("originals", folder) as originals:
        require(set(os.listdir(originals)) == set(MEDIA_NAMES), "Unexpected originals in fixture")
        document_bytes, document_info = regular_file("session.json", folder, 2 * 1024 * 1024)
        document = json.loads(document_bytes)
        sample = document.get("sample") or {}
        require(document["id"] == session_id and document.get("title") == TITLE
                and sample.get("synthetic") is True and sample.get("generator") == "JOVRAFixtureCamera"
                and document["recording"]["mode"] == "simulatorFixture", "Session is not the opt-in simulator fixture")
        yield session_id, folder, originals, document, document_info


def immutable_files(folder, originals):
    journal_bytes, journal_info = regular_file("capture-journal.json", folder, 2 * 1024 * 1024)
    first, first_info = regular_file(MEDIA_NAMES[0], originals, 16 * 1024 * 1024)
    _, second_info = regular_file(MEDIA_NAMES[1], originals, 16 * 1024 * 1024)
    return json.loads(journal_bytes), first, {"journal": journal_info, "first": first_info, "second": second_info}


def pending_session(session_id, folder, originals, document, document_info):
    require(document["original"]["state"] == "recording" and document["recording"]["mediaAvailable"] is False
            and "capture-recovery.json" not in os.listdir(folder), "Fixture is already saved or recovered")
    journal, first, immutable = immutable_files(folder, originals)
    require(first != DAMAGE and journal["formatVersion"] == 1 and journal["sessionID"] == session_id
            and journal["mode"] == "simulatorFixture" and journal["finished"] is False,
            "Expected an unacknowledged simulator capture")
    require(len(journal["segments"]) == 2, "Expected exactly two finalized fixture segments")
    for index, segment in enumerate(journal["segments"]):
        file = segment["file"]
        current = immutable[("first", "second")[index]]
        require(segment["index"] == index and segment["id"] == f"segment-{index}"
                and segment["finalized"] is True and segment["durationMs"] > 0
                and file["path"] == f"originals/{MEDIA_NAMES[index]}" and file["bytes"] == current["bytes"],
                "Journal does not identify the finalized fixture media")
    return {"sessionID": session_id, "session": document_info, "immutable": immutable,
            "sessionDirectory": list(file_identity(os.fstat(folder))[:2]),
            "originalsDirectory": list(file_identity(os.fstat(originals))[:2])}


def pending_snapshot(sessions):
    with fixture(sessions) as candidate:
        return pending_session(*candidate)


def damage_first_segment(sessions, pending):
    with fixture(sessions) as candidate:
        session_id, folder, originals, _, document_info = candidate
        current = pending_session(*candidate)
        require(current == pending, "Current session and media do not match the pre-damage receipt")
        immutable = current["immutable"]
        temporary = f".partial-recovery-{uuid4().hex}.tmp"
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=originals)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(DAMAGE)
                stream.flush()
                os.fsync(stream.fileno())
            _, current = regular_file(MEDIA_NAMES[0], originals, 16 * 1024 * 1024)
            require(current == immutable["first"], "First fixture segment changed before damage")
            os.replace(temporary, MEDIA_NAMES[0], src_dir_fd=originals, dst_dir_fd=originals)
        finally:
            try:
                os.unlink(temporary, dir_fd=originals)
            except FileNotFoundError:
                pass
        before_damage = immutable["first"]
        _, immutable["first"] = regular_file(MEDIA_NAMES[0], originals, 16 * 1024 * 1024)
        return {"sessionID": session_id, "pendingSession": document_info, "beforeDamage": before_damage,
                "immutable": immutable}


def recovery_snapshot(sessions, seed):
    with fixture(sessions) as (session_id, folder, originals, document, document_info):
        _, first, immutable = immutable_files(folder, originals)
        require(session_id == seed["sessionID"] and first == DAMAGE and immutable == seed["immutable"],
                "Damaged segment, kept segment or WAL changed")
        recording = document["recording"]
        report = recording["recovery"]
        segments = recording["segments"]
        require(document["original"]["state"] == "partial" and recording["mediaAvailable"] is True
                and report["outcome"] == "partial"
                and [item["path"] for item in report["unrecoverable"]] == ["originals/segment-0.mp4"]
                and [segment["id"] for segment in segments] == ["segment-1"]
                and segments[0]["file"]["path"] == "originals/segment-1.mp4"
                and segments[0]["file"]["sha256"] == immutable["second"]["sha256"],
                "Recovered session does not describe the verified playable segment and damage")
        _, report_info = regular_file("capture-recovery.json", folder, 2 * 1024 * 1024)
        return {"sessionID": session_id, "immutable": immutable, "session": document_info, "report": report_info}


def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], text=True, capture_output=True, check=True).stdout.strip()


@contextmanager
def isolated_sessions(simulator, token):
    require(canonical_uuid(simulator) and re.fullmatch(r"[a-f0-9]{12}", token), "Invalid simulator or isolation token")
    device_name = f"JOVRA-PartialRecovery-{token}"
    bundle = f"com.islanddevcrew.jovra.partial-recovery-{token}"
    inventory = json.loads(simctl("list", "devices", "booted", "-j"))["devices"]
    matches = [device for runtime, devices in inventory.items() if ".iOS-" in runtime
               for device in devices if device["udid"] == simulator and device["name"] == device_name
               and device["state"] == "Booted" and device.get("isAvailable") is True]
    require(len(matches) == 1, "Expected the booted test-owned iOS simulator and exact tokenized name")
    container = Path(simctl("get_app_container", simulator, bundle, "data"))
    expected = Path.home() / "Library/Developer/CoreSimulator/Devices" / simulator / "data/Containers/Data/Application"
    require(container.is_absolute() and container.parent == expected and canonical_uuid(container.name.upper()),
            "App container is outside the dedicated simulator")
    with ExitStack() as descriptors:
        parent = descriptors.enter_context(directory("/"))
        for component in container.parts[1:]:
            parent = descriptors.enter_context(directory(component, parent))
        metadata, _ = regular_file(".com.apple.mobile_container_manager.metadata.plist", parent, 1024 * 1024)
        require(plistlib.loads(metadata).get("MCMMetadataIdentifier") == bundle, "Container bundle identity does not match")
        for component in ("Library", "Application Support", "JOVRA", "sessions"):
            parent = descriptors.enter_context(directory(component, parent))
        yield parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Dedicated simulator UUID")
    parser.add_argument("--token", required=True, help="Token shared by test-owned simulator and bundle names")
    parser.add_argument("--confirmed-stopped", action="store_true", required=True,
                        help="Confirm the preceding XCTest passed and the isolated app is stopped")
    sub = parser.add_subparsers(dest="phase", required=True)
    sub.add_parser("pending")
    sub.add_parser("damage").add_argument("--pending", type=Path, required=True)
    sub.add_parser("snapshot").add_argument("--seed", type=Path, required=True)
    args = parser.parse_args()
    try:
        custody = {"simulatorID": args.simulator, "token": args.token}
        with isolated_sessions(args.simulator, args.token) as sessions:
            if args.phase == "pending":
                result = pending_snapshot(sessions)
            else:
                receipt = json.loads((args.pending if args.phase == "damage" else args.seed).read_text())
                require(receipt.pop("custody", None) == custody, "Receipt belongs to another simulator or app token")
                result = (damage_first_segment(sessions, receipt) if args.phase == "damage"
                          else recovery_snapshot(sessions, receipt))
        print(json.dumps({"custody": custody, **result}, sort_keys=True))
        return 0
    except (FixtureError, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"partial recovery fixture refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
