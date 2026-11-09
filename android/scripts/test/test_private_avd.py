"""A03 acquisition through a fake SDK inside temporary private roots."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from private_avd import AcquisitionError, acquire, require_binding

PHONE = "jovra_phone_p9_api35"
FOLD = "jovra_fold_p9pf_api35"
GIB = 1024 ** 3
FAKE_MANAGER = r'''
import json, os, sys
from pathlib import Path
sdk = Path(os.environ["ANDROID_HOME"])
options = json.loads((sdk / "options.json").read_text())
with (sdk / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"args": sys.argv[1:], "env": dict(os.environ)}) + "\n")
args = sys.argv[1:]
assert args[:2] == ["create", "avd"] and "--force" not in args
assert input() == "no"
name = args[args.index("--name") + 1]
path = Path(args[args.index("--path") + 1])
root = Path(os.environ["ANDROID_AVD_HOME"])
assert path.is_dir()
(path / "config.ini").write_text("" if options.get("empty_config") else "hw.ramSize=1024\nother=keep\n")
index = root / (name + ".ini")
index.write_text(f"path={path}\npath.rel=avd/{name}.avd\ntarget=android-35\n")
if options.get("redirect_avd"):
    path.rename(path.with_suffix(".retained"))
    path.symlink_to(options["redirect_avd"], target_is_directory=True)
if options.get("transplant_avd"):
    path.rename(path.with_suffix(".retained"))
    Path(options["transplant_avd"]).rename(path)
if options.get("redirect_index"):
    index.write_text(f'path={options["redirect_index"]}\n')
if options.get("replace_registry"):
    registry = Path(options["replace_registry"])
    registry.rename(registry.with_name("displaced"))
    registry.mkdir(mode=0o700)
'''


class PrivateAVDTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.control = self.root / "control"
        self.registry = self.root / "registry"
        self.sdk = self.root / "sdk"
        for path in (self.control, self.registry, self.sdk):
            path.mkdir(mode=0o700)
        manager = self.sdk / "cmdline-tools/latest/bin/avdmanager"
        manager.parent.mkdir(parents=True)
        manager.write_text(f"#!{sys.executable}\n" + FAKE_MANAGER)
        manager.chmod(0o700)
        image = self.sdk / "system-images/android-35/google_apis/arm64-v8a"
        image.mkdir(parents=True)
        (image / "source.properties").write_text("Pkg.Desc=fake image\n")
        self.options()
        self.global_avds = self.root / "outside/.android/avd"
        self.foreign = self.global_avds / "OlamyPixel.avd"
        self.foreign.mkdir(parents=True)
        self.sentinel = self.foreign / "config.ini"
        self.sentinel.write_text("hw.ramSize=2048\nforeign=keep\n")
        self.receipt = self.control / ".jovra-lock/owner.json"

    def options(self, **options):
        (self.sdk / "options.json").write_text(json.dumps(options))

    def calls(self):
        log = self.sdk / "calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    @staticmethod
    def run_fake(command, env, home):
        subprocess.run(command, env=env, cwd=home, input="no\n", text=True, check=True, capture_output=True)

    def acquire(self, name=PHONE, registry=None, disk_space=lambda _: 16 * GIB):
        return acquire(name, control=self.control, registry=registry or self.registry,
                       sdk=self.sdk, populate=self.run_fake, disk_space=disk_space)

    def test_ambient_android_homes_cannot_select_existing_avds(self):
        legacy_index = self.global_avds / (PHONE + ".ini")
        legacy_index.write_text(f"path={self.foreign}\n")
        original = {path: (path.read_bytes(), path.stat().st_ino) for path in (legacy_index, self.sentinel)}
        with patch.dict(os.environ, {"HOME": str(self.root / "outside"),
                                     "ANDROID_AVD_HOME": str(self.global_avds),
                                     "ANDROID_USER_HOME": str(self.global_avds.parent),
                                     "ANDROID_EMULATOR_HOME": str(self.global_avds.parent),
                                     "ANDROID_SDK_HOME": str(self.root / "outside")}):
            path = self.acquire()
        self.assertTrue(path.is_relative_to(self.registry))
        self.assertEqual(path.name, PHONE + ".avd")
        self.assertEqual(len(self.calls()), 1)
        env = self.calls()[0]["env"]
        self.assertEqual(Path(env["ANDROID_AVD_HOME"]), path.parent)
        self.assertEqual(Path(env["ANDROID_USER_HOME"]) / "avd", path.parent)
        self.assertEqual(Path(env["ANDROID_EMULATOR_HOME"]) / "avd", path.parent)
        self.assertEqual(Path(env["HOME"]) / ".android/avd", path.parent)
        self.assertEqual(Path(env["ANDROID_SDK_HOME"]) / ".android/avd", path.parent)
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt["name"], PHONE)
        self.assertEqual(receipt["phase"], "fixtureAcquired")
        config_metadata = (path / "config.ini").stat()
        self.assertEqual(receipt["entries"]["config.ini"], [config_metadata.st_dev, config_metadata.st_ino])
        self.assertEqual(path.parents[2].stat().st_mode & 0o777, 0o700)
        config = dict(line.split("=", 1) for line in (path / "config.ini").read_text().splitlines())
        self.assertEqual(config, {"other": "keep", "disk.dataPartition.size": "4G",
                                  "fastboot.forceColdBoot": "yes", "fastboot.forceFastBoot": "no",
                                  "fastboot.forceChosenSnapshotBoot": "no", "hw.ramSize": "4096",
                                  "snapshot.present": "false"})
        for original_path, (data, inode) in original.items():
            self.assertEqual((original_path.read_bytes(), original_path.stat().st_ino), (data, inode))

    def test_invalid_manager_outputs_do_not_publish_a_lease_receipt(self):
        original = self.sentinel.read_bytes(), self.sentinel.stat().st_ino
        for mode in ("redirect_avd", "redirect_index", "empty_config", "replace_registry"):
            with self.subTest(mode=mode):
                self.control = self.root / (mode + "-control")
                self.registry = self.root / (mode + "-registry")
                self.control.mkdir(mode=0o700)
                self.registry.mkdir(mode=0o700)
                self.options(**{mode: str(self.registry if mode == "replace_registry" else self.foreign)})
                with self.assertRaises(AcquisitionError):
                    self.acquire()
                self.assertTrue((self.control / ".jovra-lock").is_dir())
                self.assertFalse((self.control / ".jovra-lock/owner.json").exists())
                self.assertEqual((self.sentinel.read_bytes(), self.sentinel.stat().st_ino), original)
        self.assertEqual(len(self.calls()), 4, "each fake SDK fault must execute")
        self.assertTrue((self.root / "displaced").is_dir())
        self.assertEqual(list(self.registry.iterdir()), [])

    def test_same_user_directory_transplant_is_never_rewritten(self):
        original = self.sentinel.read_bytes(), self.sentinel.stat().st_ino
        self.options(transplant_avd=str(self.foreign))
        try:
            with self.assertRaises(AcquisitionError):
                self.acquire()
        finally:
            call, = self.calls()
            args = call["args"]
            transplanted = Path(args[args.index("--path") + 1]) / "config.ini"
            self.assertEqual((transplanted.read_bytes(), transplanted.stat().st_ino), original)
        self.assertFalse(self.receipt.exists())

    def test_late_config_swap_preserves_the_foreign_inode_and_refuses_acquisition(self):
        original = self.sentinel.read_bytes(), self.sentinel.stat().st_ino
        checks = 0
        swaps = []

        def swap_after_binding(parent, name, fd):
            nonlocal checks
            require_binding(parent, name, fd)
            if name != "config.ini":
                return
            checks += 1
            # Interrupt the last successful binding check before writing the config.
            if checks == 3:
                args = self.calls()[0]["args"]
                config = Path(args[args.index("--path") + 1]) / name
                config.rename(config.with_suffix(".retained"))
                self.sentinel.rename(config)
                swaps.append(config)

        with patch("private_avd.require_binding", side_effect=swap_after_binding):
            try:
                with self.assertRaisesRegex(AcquisitionError, r"managed entry changed: config\.ini"):
                    self.acquire()
            finally:
                config, = swaps
                self.assertEqual((config.read_bytes(), config.stat().st_ino), original)
        self.assertFalse(self.receipt.exists())

    def test_late_receipt_swap_preserves_foreign_bytes_and_refuses_acquisition(self):
        original = self.sentinel.read_bytes(), self.sentinel.stat().st_ino
        real_sync = os.fsync
        swaps = []

        def swap_after_receipt_sync(fd):
            real_sync(fd)
            written = os.fstat(fd)
            for candidate in (self.receipt.with_name("pending.json"), self.receipt):
                if candidate.is_file() and not candidate.is_symlink():
                    current = candidate.stat()
                    if (written.st_dev, written.st_ino) == (current.st_dev, current.st_ino):
                        candidate.rename(candidate.with_name("retained.json"))
                        candidate.symlink_to(self.sentinel)
                        swaps.append(candidate)
                        break

        with patch("private_avd.os.fsync", side_effect=swap_after_receipt_sync):
            try:
                with self.assertRaisesRegex(AcquisitionError, r"managed entry changed: owner\.json"):
                    self.acquire()
            finally:
                swapped, = swaps
                self.assertTrue((swapped.parent / "retained.json").is_file())
                self.assertEqual((self.sentinel.read_bytes(), self.sentinel.stat().st_ino), original)
        self.assertTrue(self.receipt.parent.is_dir())

    def test_invalid_names_and_low_disk_refuse_before_any_sdk_call(self):
        for name in ("OlamyPixel", "other", "jovra_wear_xlround_api36", "jovra_wear_smallround_api36"):
            with self.subTest(name=name), self.assertRaises(AcquisitionError):
                self.acquire(name)
        for space in (5 * GIB, 11 * GIB):
            with self.subTest(space=space), self.assertRaisesRegex(AcquisitionError, r"not run \(disk\)"):
                self.acquire(disk_space=lambda _: space)
        self.assertEqual(self.calls(), [])
        self.assertEqual(list(self.registry.iterdir()), [])
        self.assertFalse((self.control / ".jovra-lock").exists())

    def test_named_profiles_and_compact_geometry(self):
        profiles = {FOLD: "pixel_9_pro_fold", "jovra_tablet_ptab_api35": "pixel_tablet",
                    "jovra_compact360_api35": "medium_phone"}
        for name, profile in profiles.items():
            with self.subTest(name=name):
                self.control = self.root / profile
                self.control.mkdir(mode=0o700)
                avd = self.acquire(name)
                args = self.calls()[-1]["args"]
                self.assertEqual(args[args.index("--device") + 1], profile)
                if profile == "medium_phone":
                    config = (avd / "config.ini").read_text().splitlines()
                    self.assertTrue({"hw.lcd.width=1080", "hw.lcd.height=2340", "hw.lcd.density=480"} <= set(config))

    def test_same_account_control_root_serializes_distinct_registries(self):
        self.acquire()
        alternate = self.root / "alternate-registry"
        alternate.mkdir(mode=0o700)
        with self.assertRaisesRegex(AcquisitionError, "lease is held"):
            self.acquire(FOLD, alternate)
        self.assertEqual(list(alternate.iterdir()), [])
        self.assertEqual(len(self.calls()), 1)


if __name__ == "__main__":
    unittest.main()
