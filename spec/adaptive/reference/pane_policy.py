#!/usr/bin/env python3
"""Reference pane policy (ADR-0025 §1-§5, §8). Python 3 standard library only; no I/O.

A pure function of the app window, its posture, the text-size band, the input mode and the screen's task:

    decide({widthDp, heightDp, posture, hinge, textScaleBand, inputMode, task})
        -> {widthClass, heightClass, panes, navigation, arrangement, hingeBounds}

The device model, brand, diagonal, physical pixels and any "is tablet" flag are never inputs (ADR-0025 §1).
spec/adaptive/pane-policy.vectors.json holds the golden vectors; the Kotlin (A15) and Swift (W22) ports must
reproduce them, and scripts/spec/validate_adaptive.py checks this reference against them.

Rule order (each step is one rule; the validator's --mutations removes them one at a time):
  1. Classify width and height (ADR-0025 §2).
  2. Window table (§3): compact width 1; medium width 2 only for a list-led task (listDetail, workspace) with height
     at least medium, otherwise 1; expanded 2; large and extra-large up to 3; never more than the task's own panes.
  3. Compact height (§3): at most 2, and a player keeps priority with 1 pane (supporting panels become sheets).
  4. Posture (§4): a separating vertical hinge gives exactly 2 panes split at the hinge; tabletop (half-opened,
     horizontal hinge) puts a player's picture above the hinge and its controls below. A fold that does not separate
     is ignored. Posture is an arrangement hint only; it never starts or stops capture or playback.
  5. Accessibility text band (§3): one fewer pane, never below 1, unconditionally; navigation unchanged.
  6. Navigation (§3): bottom bar on compact width unless the height is compact; rail otherwise.
Input mode (touch, keyboard, pointer) is an input (§1) but never changes panes or navigation.
"""

from __future__ import annotations

BREAKPOINTS = {
    "width": [
        {"class": "compact", "min": 0, "maxExclusive": 600},
        {"class": "medium", "min": 600, "maxExclusive": 840},
        {"class": "expanded", "min": 840, "maxExclusive": 1200},
        {"class": "large", "min": 1200, "maxExclusive": 1600},
        {"class": "extraLarge", "min": 1600, "maxExclusive": None},
    ],
    "height": [
        {"class": "compact", "min": 0, "maxExclusive": 480},
        {"class": "medium", "min": 480, "maxExclusive": 900},
        {"class": "expanded", "min": 900, "maxExclusive": None},
    ],
}

# The most panes each task ever shows (adaptive-screens §0.2 and §4.5): list | detail; main | supporting;
# video | supporting (the player has priority); list | detail | inspector (lesson 55, Studio sync 46, Studio Home).
TASK_PANES = {"listDetail": 2, "supporting": 2, "player": 2, "workspace": 3}
LIST_LED_TASKS = frozenset({"listDetail", "workspace"})
WINDOW_PANES = {"compact": 1, "medium": 2, "expanded": 2, "large": 3, "extraLarge": 3}

ANDROID_ACCESSIBILITY_FONT_SCALE = 1.5
IOS_DYNAMIC_TYPE_SIZES = ("xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
                          "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5")


def size_class(value: float, axis: str) -> str:
    for row in BREAKPOINTS[axis]:
        if value >= row["min"] and (row["maxExclusive"] is None or value < row["maxExclusive"]):
            return row["class"]
    raise ValueError(f"{axis} {value!r} is outside every class")


def text_scale_band(platform: str, value) -> str:
    """Android: font scale >= 1.5 is the accessibility band. iOS: the accessibility Dynamic Type sizes are."""
    if platform == "android":
        return "accessibility" if float(value) >= ANDROID_ACCESSIBILITY_FONT_SCALE else "default"
    if platform == "ios":
        if value not in IOS_DYNAMIC_TYPE_SIZES:
            raise ValueError(f"unknown DynamicTypeSize {value!r}")
        return "accessibility" if value.startswith("accessibility") else "default"
    raise ValueError(f"unknown platform {platform!r}")


def window_panes(width_class: str, height_class: str, task: str) -> int:
    if width_class == "medium" and (task not in LIST_LED_TASKS or height_class == "compact"):
        allowed = 1
    else:
        allowed = WINDOW_PANES[width_class]
    return min(allowed, TASK_PANES[task])


def decide(inputs: dict) -> dict:
    width_class = size_class(inputs["widthDp"], "width")
    height_class = size_class(inputs["heightDp"], "height")
    task = inputs["task"]
    hinge = inputs["hinge"]
    posture = inputs["posture"]
    text_scale_band = inputs["textScaleBand"]

    panes = window_panes(width_class, height_class, task)
    if height_class == "compact":
        panes = 1 if task == "player" else min(panes, 2)

    separating = hinge is not None and hinge["separating"]
    vertical_split = separating and hinge["orientation"] == "vertical"
    tabletop = (separating and posture == "halfOpened" and hinge["orientation"] == "horizontal"
                and task == "player")
    if vertical_split:
        panes, arrangement = 2, "splitAtHinge"
    elif tabletop:
        panes, arrangement = 2, "tabletop"
    else:
        arrangement = "columns"

    if text_scale_band == "accessibility":
        panes = max(1, panes - 1)
    if panes == 1:
        arrangement = "single"

    if not separating:
        hinge_bounds = "ignore"
    elif hinge["occluding"]:
        hinge_bounds = "noContent"
    else:
        hinge_bounds = "noControls"

    navigation = "bottomBar" if width_class == "compact" and height_class != "compact" else "rail"
    return {"widthClass": width_class, "heightClass": height_class, "panes": panes, "navigation": navigation,
            "arrangement": arrangement, "hingeBounds": hinge_bounds}
