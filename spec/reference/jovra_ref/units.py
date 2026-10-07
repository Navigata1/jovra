"""Unit conversions with exact factors, computed in exact rational arithmetic.

Rules (raw/equipment-stringing.md §4, tennis-rules-and-stats.md §7 rule 6):
* Units convert data, never relabel it. A stored value keeps the unit it was entered in.
* Conversion is exact (rational); rounding happens once, for display, half-up to the unit's step.
* Gauge has no exact conversion: diameter in mm is the stored truth and the gauge label is text.
"""

from __future__ import annotations

from fractions import Fraction

# Factor to a base unit per dimension. Every factor is exact by definition:
# 1 lb = 0.45359237 kg (international pound, 1959); 1 kgf = 9.80665 N (standard gravity);
# 1 in = 2.54 cm; 1 ft = 0.3048 m; 1 mi = 1609.344 m; 1 oz = 28.349523125 g (avoirdupois).
UNITS = {
    # tension (force): base kgf. Players say "lb"/"kg" and mean lbf/kgf; the ratio is the mass ratio.
    "lb": ("tension", Fraction("0.45359237")),
    "kg": ("tension", Fraction(1)),
    "N": ("tension", 1 / Fraction("9.80665")),
    # speed: base m/s
    "mph": ("speed", Fraction("0.44704")),
    "km/h": ("speed", Fraction(1000, 3600)),
    "m/s": ("speed", Fraction(1)),
    # length: base mm
    "mm": ("length", Fraction(1)),
    "cm": ("length", Fraction(10)),
    "m": ("length", Fraction(1000)),
    "in": ("length", Fraction("25.4")),
    "ft": ("length", Fraction("304.8")),
    # area: base cm2
    "cm2": ("area", Fraction(1)),
    "in2": ("area", Fraction("6.4516")),
    # mass: base g
    "g": ("mass", Fraction(1)),
    "oz": ("mass", Fraction("28.349523125")),
}

# Display step per unit (half-up to a multiple of the step).
DISPLAY_STEP = {
    "lb": Fraction(1, 2),
    "kg": Fraction(1, 10),
    "N": Fraction(1),
    "mph": Fraction(1),
    "km/h": Fraction(1),
    "m/s": Fraction(1, 10),
    "mm": Fraction(1, 100),
    "cm": Fraction(1, 10),
    "m": Fraction(1, 100),
    "in": Fraction(1, 100),
    "ft": Fraction(1, 10),
    "cm2": Fraction(1, 10),
    "in2": Fraction(1, 10),
    "g": Fraction(1),
    "oz": Fraction(1, 10),
}

# Gauge help table: two sources disagree, so the label never converts to a single number.
GAUGE_HINTS = {
    "15": {"tennisCompanion": ("1.41", "1.49"), "tennisWarehouse": ("1.35", "1.40")},
    "15L": {"tennisCompanion": ("1.33", "1.41"), "tennisWarehouse": None},
    "16": {"tennisCompanion": ("1.26", "1.34"), "tennisWarehouse": ("1.25", "1.30")},
    "16L": {"tennisCompanion": ("1.22", "1.30"), "tennisWarehouse": None},
    "17": {"tennisCompanion": ("1.16", "1.24"), "tennisWarehouse": ("1.20", "1.25")},
    "18": {"tennisCompanion": ("1.06", "1.16"), "tennisWarehouse": ("1.15", "1.20")},
    "19": {"tennisCompanion": ("0.90", "1.06"), "tennisWarehouse": ("1.10", "1.15")},
}


def convert(value: str, from_unit: str, to_unit: str) -> Fraction:
    dim_a, fa = UNITS[from_unit]
    dim_b, fb = UNITS[to_unit]
    if dim_a != dim_b:
        raise ValueError(f"cannot convert {from_unit} to {to_unit}")
    return Fraction(value) * fa / fb


def round_half_up(x: Fraction, step: Fraction) -> Fraction:
    if x < 0:
        raise ValueError("display rounding is defined for non-negative values")
    q = x / step
    return Fraction((q.numerator * 2 + q.denominator) // (2 * q.denominator)) * step


def decimal_text(x: Fraction, places: int) -> str:
    """Exact decimal text of ``x`` half-up at ``places`` digits, trailing zeros kept."""
    scaled = round_half_up(x, Fraction(1, 10 ** places)) * 10 ** places
    n = int(scaled)
    if places == 0:
        return str(n)
    return f"{n // 10 ** places}.{n % 10 ** places:0{places}d}"


def minimal_text(x: Fraction) -> str:
    """Shortest exact decimal text for a value that is a multiple of a display step."""
    for places in range(0, 7):
        scaled = x * 10 ** places
        if scaled.denominator == 1:
            return decimal_text(x, places)
    raise ValueError("not a terminating display value")


def display(value: str, unit: str, preferred_unit: str) -> dict:
    """Display a stored quantity in the preferred unit. Same unit -> the stored text, untouched
    (52 lb is never round-tripped through kg). Otherwise convert exactly, then round half-up once."""
    if unit == preferred_unit:
        return {"value": value, "unit": unit, "converted": False}
    x = convert(value, unit, preferred_unit)
    text = minimal_text(round_half_up(x, DISPLAY_STEP[preferred_unit]))
    return {"value": text, "unit": preferred_unit, "converted": True}


def gauge_hint(label: str) -> dict:
    hints = GAUGE_HINTS.get(label)
    if hints is None:
        return {"label": label, "known": False, "ranges": []}
    ranges = []
    for source, rng in hints.items():
        if rng is not None:
            ranges.append({"source": source, "minMm": rng[0], "maxMm": rng[1]})
    return {"label": label, "known": True, "ranges": ranges}
