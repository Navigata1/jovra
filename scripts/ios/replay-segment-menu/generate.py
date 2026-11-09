"""Export a clean tracked checkout and configure a DEBUG alternate simulator probe."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import subprocess
import tarfile
from tempfile import TemporaryFile
from uuid import uuid4

import yaml


PROBE = Path("scripts/ios/replay-segment-menu")
MEDIA = Path("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
PROJECT = Path("ios/project.yml")
FIXTURE = "segment-menu-fixture.json"
TEST = "ReplaySegmentMenuUITests.swift"
SELECTOR = "JovraUITests/ReplaySegmentMenuUITests/testActualMenuOpensLaterSegmentAfterTheFirstIsUnavailable"
PRODUCTION_BUNDLE = "com.islanddevcrew.jovra"
ENTRY = "App/JovraApp.swift"
SESSION_SHA256 = "003fe33ad9fc29b35b8e7628bc12a2823baa9da4d9afec51d92da9648ac6d331"
MEDIA_SHA256 = "b939a95362096f89cd5f8a1c4171d2ee8148f3eb0ecf87cbe7cd7af6675644b5"


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def generate(source: Path, output: Path) -> dict:
    source = source.resolve(strict=True)
    output = output.absolute()
    if (output.parent.resolve(strict=True) != output.parent or not output.parent.is_dir()
            or output.is_relative_to(source)):
        raise ValueError("output parent must be a real directory outside the source checkout")
    git = ["git", "-C", str(source)]
    if subprocess.check_output([*git, "status", "--porcelain"], timeout=15):
        raise ValueError("requires a clean checkout")
    head = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True, timeout=15).strip()
    output.mkdir(mode=0o700)
    checkout = output / "checkout"
    checkout.mkdir(mode=0o700)
    with TemporaryFile(dir=output) as archive:
        subprocess.run([*git, "archive", "--format=tar", head], stdout=archive, check=True, timeout=60)
        archive.seek(0)
        with tarfile.open(fileobj=archive) as packed:
            packed.extractall(checkout, filter="data")
    inputs = checkout / PROBE
    if digest(inputs / FIXTURE) != SESSION_SHA256 or digest(checkout / MEDIA) != MEDIA_SHA256:
        raise ValueError("fixture bytes differ from the pinned synthetic inputs")

    run_id = uuid4()
    token, bundle = str(run_id), PRODUCTION_BUNDLE + ".menuprobe" + run_id.hex
    probe = checkout / "ios/MenuProbe"
    probe.mkdir(mode=0o700)
    entry = (inputs / "AlternateApp.swift.in").read_text()
    for marker, value in (("@TOKEN@", token), ("@APP_BUNDLE@", bundle)):
        if entry.count(marker) != 1:
            raise ValueError(f"unexpected alternate entry template marker {marker}")
        entry = entry.replace(marker, value)
    (probe / "AlternateApp.swift").write_text(entry)
    for name in ("ProbeCustody.swift", FIXTURE, TEST):
        (probe / name).write_bytes((inputs / name).read_bytes())
    configure(checkout / PROJECT, bundle, token)

    files = [PROJECT, MEDIA, *(p.relative_to(checkout) for p in sorted(probe.iterdir())),
             Path("ios/Jovra") / ENTRY]
    manifest = {"head": head, "token": token, "appBundle": bundle, "runnerBundle": bundle + ".uitests.xctrunner",
                "selector": SELECTOR, "files": {str(path): digest(checkout / path) for path in files}}
    with (output / "probe-manifest.json").open("x") as receipt:
        json.dump(manifest, receipt, indent=2, sort_keys=True)
        receipt.write("\n")
    return manifest


def configure(path: Path, bundle: str, token: str) -> None:
    project = yaml.safe_load(path.read_text())
    app, ui = (project["targets"][name] for name in ("Jovra", "JovraUITests"))
    app_settings = app["settings"]["base"]
    ui_settings = ui["settings"]["base"]
    if (app_settings["PRODUCT_BUNDLE_IDENTIFIER"] != PRODUCTION_BUNDLE
            or ui_settings["TEST_TARGET_NAME"] != "Jovra"):
        raise ValueError("production project target identities changed")
    project["settings"]["base"]["SUPPORTED_PLATFORMS"] = "iphonesimulator"
    app_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle
    ui_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle + ".uitests"
    project["targets"] = {"Jovra": app, "JovraUITests": ui}
    app.pop("entitlements", None)
    app.pop("configFiles", None)
    props = app["info"]["properties"]
    props["CFBundleDisplayName"] = "JOVRA Segment Menu Probe"
    for key in list(props):
        if key.startswith("JovraDrive") or key in (
            "CFBundleURLTypes", "BGTaskSchedulerPermittedIdentifiers", "UIBackgroundModes", "NSBonjourServices",
            "NSLocalNetworkUsageDescription", "JovraAppleSignInEnabled", "JovraStudioEnvironment",
        ):
            del props[key]
    [normal] = [item for item in app["sources"] if item["path"] == "Jovra"]
    normal.setdefault("excludes", []).append(ENTRY)
    app["sources"] += [
        {"path": "MenuProbe/AlternateApp.swift"},
        {"path": "MenuProbe/ProbeCustody.swift"},
        {"path": "MenuProbe/" + FIXTURE, "buildPhase": "resources"},
    ]
    ui["sources"] = [
        {"path": "MenuProbe/" + TEST},
        {"path": "Jovra/Platform/LaunchConfiguration/LaunchConfiguration.swift"},
        {"path": "JovraUITests/Support/JovraLaunch.swift"},
    ]
    project["schemes"] = {"Jovra": {
        "build": {"targets": {"Jovra": "all", "JovraUITests": ["test"]}},
        "test": {"targets": ["JovraUITests"], "language": "en", "region": "US",
                 "environmentVariables": {"JOVRA_SEGMENT_MENU_PROBE_TOKEN": token}},
    }}
    path.write_text(yaml.safe_dump(project, sort_keys=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new private directory outside the checkout")
    args = parser.parse_args()
    manifest = generate(Path(__file__).resolve().parents[3], args.output)
    print(json.dumps(manifest, indent=2, sort_keys=True))
