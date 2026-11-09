"""A03 managed acquisition boundary. No operational CLI or emulator lifecycle yet."""
from collections.abc import Callable
from contextlib import ExitStack, contextmanager
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time
import uuid


PROFILES = {
    "jovra_phone_p9_api35": "pixel_9",
    "jovra_fold_p9pf_api35": "pixel_9_pro_fold",
    "jovra_tablet_ptab_api35": "pixel_tablet",
    "jovra_compact360_api35": "medium_phone",
}
IMAGE = "system-images;android-35;google_apis;arm64-v8a"
GIB = 1024 ** 3
DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
LEASE = ".jovra-lock"


class AcquisitionError(RuntimeError):
    """The caller must retain any incomplete acquisition for inspection."""


@contextmanager
def opened(path, flags, *, mode=0o600, parent=None):
    fd = os.open(path, flags, mode, dir_fd=parent)
    try:
        yield fd
    finally:
        os.close(fd)


@contextmanager
def private_root(path):
    if not path.is_absolute() or path.anchor != "/" or ".." in path.parts:
        raise AcquisitionError("roots must be absolute and contain no parent traversal")
    with ExitStack() as stack:
        fd = stack.enter_context(opened("/", DIRECTORY))
        for name in path.parts[1:]:
            fd = stack.enter_context(opened(name, DIRECTORY, parent=fd))
        metadata = os.fstat(fd)
        if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
            raise AcquisitionError("roots must be private directories owned by this account (0700)")
        yield fd


def identity(metadata):
    return metadata.st_dev, metadata.st_ino


def require_binding(parent, name, fd):
    if identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != identity(os.fstat(fd)):
        raise AcquisitionError(f"managed entry changed: {name}")


def create_dir(stack, parent, name):
    os.mkdir(name, 0o700, dir_fd=parent)
    fd = stack.enter_context(opened(name, DIRECTORY, parent=parent))
    os.fsync(parent)
    return fd


@contextmanager
def regular_file(parent, name):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with opened(name, flags, parent=parent) as fd:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid() or metadata.st_nlink != 1:
            raise AcquisitionError(f"unexpected file type or ownership: {name}")
        yield fd


def properties(fd):
    with os.fdopen(os.dup(fd), "rb") as source:
        raw = source.read(64 * 1024 + 1)
    if len(raw) > 64 * 1024:
        raise AcquisitionError("SDK properties exceed the expected size")
    entries = {}
    for line in raw.decode("utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith(("#", "!")):
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or not re.fullmatch(r"[A-Za-z0-9_.-]+", key) or key in entries or "\\" in value or "\0" in value:
            raise AcquisitionError("ambiguous SDK properties")
        entries[key] = value.strip()
    return entries


def write_new(parent, name, data):
    with opened(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, parent=parent) as fd:
        with os.fdopen(os.dup(fd), "wb") as out:
            out.write(data)
            out.flush()
        os.fsync(fd)


def free_bytes(volume):
    capacity = os.fstatvfs(volume) if isinstance(volume, int) else os.statvfs(volume)
    return capacity.f_bavail * capacity.f_frsize


def verify_roots(control, control_fd, registry, registry_fd):
    with private_root(control) as current_control, private_root(registry) as current_registry:
        if (identity(os.fstat(current_control)), identity(os.fstat(current_registry))) != (
            identity(os.fstat(control_fd)), identity(os.fstat(registry_fd))
        ):
            raise AcquisitionError("managed root changed during acquisition")


def acquire(name, *, control: Path, registry: Path, sdk: Path,
            populate: Callable[[list[str], dict[str, str], Path], None], disk_space=free_bytes) -> Path:
    """Reserve private roots and populate anchored files through an injected adapter.

    This slice has no SDK adapter. The fake adapter fills the reserved config and
    index in place. A real SDK requiring an absent target needs a separate staging
    and adoption adapter. Uncertain acquisitions retain the lease.
    """
    if name not in PROFILES:
        raise AcquisitionError(f"{name} is not an approved API 35 JOVRA AVD")
    if control == registry or control in registry.parents or registry in control.parents:
        raise AcquisitionError("control and AVD roots must be separate")
    manager = sdk / "cmdline-tools/latest/bin/avdmanager"
    image = sdk / "system-images/android-35/google_apis/arm64-v8a/source.properties"
    if not sdk.is_absolute() or not manager.is_file() or not os.access(manager, os.X_OK) or not image.is_file():
        raise AcquisitionError("the approved API 35 image and avdmanager must already be installed")
    try:
        with ExitStack() as stack:
            control_fd = stack.enter_context(private_root(control))
            registry_fd = stack.enter_context(private_root(registry))
            if identity(os.fstat(control_fd)) == identity(os.fstat(registry_fd)):
                raise AcquisitionError("control and AVD roots refer to the same directory")
            if disk_space("/") < 8 * GIB or disk_space(registry_fd) < 12 * GIB:
                raise AcquisitionError("not run (disk): 8 GiB internal and 12 GiB managed free space required")
            try:
                lease_fd = create_dir(stack, control_fd, LEASE)
            except FileExistsError:
                time.sleep(1)
                try:
                    lease_fd = create_dir(stack, control_fd, LEASE)
                except FileExistsError as error:
                    raise AcquisitionError("another JOVRA AVD lease is held") from error

            slot = "jovra-" + uuid.uuid4().hex
            slot_fd = create_dir(stack, registry_fd, slot)
            home_fd = create_dir(stack, slot_fd, "home")
            user_fd = create_dir(stack, home_fd, ".android")
            avds_fd = create_dir(stack, user_fd, "avd")
            home = registry / slot / "home"
            user_home = home / ".android"
            avds = user_home / "avd"
            data_name = name + ".avd"
            index_name = name + ".ini"
            destination = avds / data_name
            data_fd = create_dir(stack, avds_fd, data_name)
            write_new(avds_fd, index_name, b"")
            write_new(data_fd, "config.ini", b"")
            index_fd = stack.enter_context(regular_file(avds_fd, index_name))
            config_fd = stack.enter_context(regular_file(data_fd, "config.ini"))
            bindings = [(control_fd, LEASE, lease_fd), (registry_fd, slot, slot_fd), (slot_fd, "home", home_fd),
                        (home_fd, ".android", user_fd), (user_fd, "avd", avds_fd), (avds_fd, data_name, data_fd),
                        (avds_fd, index_name, index_fd)]
            env = {"HOME": str(home), "PATH": os.defpath, "ANDROID_SDK_HOME": str(home),
                   "ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": str(sdk), "ANDROID_USER_HOME": str(user_home),
                   "ANDROID_EMULATOR_HOME": str(user_home), "ANDROID_AVD_HOME": str(avds)}
            command = [str(manager), "create", "avd", "--name", name, "--package", IMAGE,
                       "--device", PROFILES[name], "--path", str(destination)]
            def verify_custody():
                verify_roots(control, control_fd, registry, registry_fd)
                for parent, entry, fd in bindings:
                    require_binding(parent, entry, fd)

            verify_custody()
            require_binding(data_fd, "config.ini", config_fd)
            populate(command, env, home)
            verify_custody()
            require_binding(data_fd, "config.ini", config_fd)
            index = properties(index_fd)
            if index.get("path") != str(destination) or index.get("path.rel", f"avd/{data_name}") != f"avd/{data_name}":
                raise AcquisitionError("SDK index points outside its managed AVD")

            config = properties(config_fd)
            if not config:
                raise AcquisitionError("SDK did not populate the managed config")
            config.update({"disk.dataPartition.size": "4G", "fastboot.forceColdBoot": "yes", "fastboot.forceFastBoot": "no",
                           "fastboot.forceChosenSnapshotBoot": "no", "hw.ramSize": "4096", "snapshot.present": "false"})
            if name == "jovra_compact360_api35":
                config.update({"hw.lcd.width": "1080", "hw.lcd.height": "2340", "hw.lcd.density": "480"})
            write_new(data_fd, ".jovra-config.tmp", "".join(f"{key}={value}\n" for key, value in config.items()).encode())
            final_config_fd = stack.enter_context(regular_file(data_fd, ".jovra-config.tmp"))
            require_binding(data_fd, "config.ini", config_fd)
            os.replace(".jovra-config.tmp", "config.ini", src_dir_fd=data_fd, dst_dir_fd=data_fd)
            os.fsync(data_fd)
            os.fsync(index_fd)
            os.fsync(avds_fd)

            bindings.append((data_fd, "config.ini", final_config_fd))
            verify_custody()
            receipt = {"phase": "fixtureAcquired", "name": name, "slot": slot, "registry": str(registry),
                       "entries": {entry: identity(os.fstat(fd)) for _, entry, fd in bindings}}
            write_new(lease_fd, "pending.json", (json.dumps(receipt) + "\n").encode())
            os.link("pending.json", "owner.json", src_dir_fd=lease_fd, dst_dir_fd=lease_fd, follow_symlinks=False)
            os.unlink("pending.json", dir_fd=lease_fd)
            os.fsync(lease_fd)
            return destination
    except (OSError, subprocess.CalledProcessError, UnicodeError) as error:
        raise AcquisitionError(f"managed acquisition failed ({type(error).__name__})") from error
