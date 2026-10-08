"""Fixture sets, discovered by convention: every module here defines ``SET`` and ``clips()``."""

from __future__ import annotations

import importlib
import pkgutil
from pathlib import Path
from types import ModuleType


def discover() -> list[ModuleType]:
    modules = []
    for info in sorted(pkgutil.iter_modules([str(Path(__file__).parent)]), key=lambda m: m.name):
        module = importlib.import_module(f"{__name__}.{info.name}")
        if not hasattr(module, "SET") or not hasattr(module, "clips"):
            raise RuntimeError(f"set module {info.name} must define SET and clips()")
        modules.append(module)
    return modules
