"""Unit fixtures. Expected values were worked by hand from the exact factors (raw/equipment-stringing.md §4)."""

from __future__ import annotations

from jovra_ref import conformance

CONVERT = [
    # value, from, to, places, expected exact text (half-up at `places`)
    ("52", "lb", "kg", 8, "23.58680324"),
    ("104", "mph", "km/h", 3, "167.372"),
    ("23", "kg", "lb", 6, "50.706320"),
    ("1", "mph", "m/s", 5, "0.44704"),
    ("1", "lb", "N", 13, "4.4482216152605"),
    ("98", "in2", "cm2", 4, "632.2568"),
    ("1", "oz", "g", 9, "28.349523125"),
    ("40", "ft", "m", 3, "12.192"),
    ("27", "in", "cm", 2, "68.58"),
]

DISPLAY = [
    # stored value, stored unit, preferred unit, expected {value, unit, converted}
    ("52", "lb", "lb", ("52", False)),
    ("52.0", "lb", "lb", ("52.0", False)),
    ("52", "lb", "kg", ("23.6", True)),
    ("50", "lb", "kg", ("22.7", True)),
    ("55", "lb", "kg", ("24.9", True)),
    ("60", "lb", "kg", ("27.2", True)),
    ("52.5", "lb", "kg", ("23.8", True)),
    ("23", "kg", "lb", ("50.5", True)),
    ("25", "kg", "lb", ("55", True)),
    ("28", "kg", "lb", ("61.5", True)),
    ("52", "lb", "N", ("231", True)),
    ("104", "mph", "km/h", ("167", True)),
    ("1.25", "m/s", "km/h", ("5", True)),
    ("120", "mph", "m/s", ("53.6", True)),
    ("98", "in2", "cm2", ("632.3", True)),
    ("645", "cm2", "in2", ("100", True)),
    ("11.3", "oz", "g", ("320", True)),
    ("1.30", "mm", "in", ("0.05", True)),
    ("12.2", "m", "ft", ("40", True)),
]

GAUGES = [
    ("17", {"label": "17", "known": True, "ranges": [
        {"source": "tennisCompanion", "minMm": "1.16", "maxMm": "1.24"},
        {"source": "tennisWarehouse", "minMm": "1.20", "maxMm": "1.25"}]}),
    ("16L", {"label": "16L", "known": True, "ranges": [
        {"source": "tennisCompanion", "minMm": "1.22", "maxMm": "1.30"}]}),
    ("1.25", {"label": "1.25", "known": False, "ranges": []}),
]


def write(out, write_json, version) -> int:
    cases = []
    for value, a, b, places, text in CONVERT:
        cases.append({"op": "convert", "value": value, "from": a, "to": b, "places": places, "expected": {"value": text}})
    for value, unit, pref, (text, converted) in DISPLAY:
        cases.append({"op": "display", "value": value, "unit": unit, "preferredUnit": pref,
                      "expected": {"value": text, "unit": pref, "converted": converted}})
    for label, expected in GAUGES:
        cases.append({"op": "gaugeHint", "label": label, "expected": expected})
    for c in cases:
        actual = conformance.run_units_case(c)
        if actual != c["expected"]:
            raise SystemExit(f"units case disagrees: {c} -> {actual}")
    doc = {
        "schemaVersion": version,
        "kind": "jovra.fixture.units",
        "id": "U01-exact-conversions",
        "title": "Exact factors, one half-up rounding for display, stored values never round-tripped, gauge is a hint",
        "covers": ["§7 rule 6", "raw/equipment-stringing.md §4, §4a"],
        "cases": cases,
    }
    write_json(out / f"{doc['id']}.json", doc)
    return 1
