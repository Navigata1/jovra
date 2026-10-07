# One integer rounding function for every displayed percentage, on both platforms

Every displayed percentage is `pct(n, d) = (200·n + d) div (2·d)` in integer arithmetic (round half up), for n ≥ 0 and
d > 0; a zero denominator displays "—", never 0%. The integer is then formatted with the locale's percent sign. No
fraction is ever handed to a platform percent formatter, and differences between rates are computed in percentage
points from the two displayed integers. The Swift and Kotlin domain modules implement the same function and both must
pass the conformance vectors in `spec/` (ADR-0001), including the ties 1/8 → 13 and 5/8 → 63.

## Considered Options

- Platform formatters: they disagree on ties. `NumberFormatter` percent rounds half-even (1/8 → "12%"), Swift
  `rounded()` and Kotlin `roundToInt()` give 13, plain `FormatStyle.percent` shows "12.5%", and Android ICU's default is
  undocumented. The same match would show different numbers on two phones.
- Floating-point half-up: binary representation makes some ties land on the wrong side; integers have no ties to lose.

## Consequences

Rows that should add up to 100 (Deep / Short / Out) may not after rounding; such displays either say so or use
largest-remainder for that view only.
