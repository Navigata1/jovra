# Equipment and stringing research: Racket Vault and String Journal

Researcher notes for JOVRA Tennis. Date: 2026-10-07. Scope: racket and string logging apps, what a serious home stringer records, units, tension-loss evidence, restring rules of thumb, whether an on-device acoustic tension estimate is feasible, and a recommended data model.

**Labels used throughout**
- **OBSERVED**: I saw it in the cited source (URL in Sources).
- **INFERRED**: my reasoning or arithmetic from observed facts.
- **UNVERIFIED**: plausible, but not confirmed against a primary source.

**How this builds on the earlier brief:** `design-reference/brief/research.md` covered video competitors and storage, and said almost nothing about equipment. The brief constrains three things that matter here:
- Screen 17 (Racket Vault) must use "user-entered model names as text only, no endorsements, no invented frame specs".
- Screen 18 (String Journal) must show "No automated tension sensor, tension loss prediction or medical claim".
- `implementation-states.md` lists the restring form fields: frame, string inventory, gauge and units, mains/crosses, date, optional machine/method, note/photos and session association.

These notes stay inside those constraints. The acoustic feature is evaluated as a gated, later option, and is not recommended for the reference screens.

---

## 0. Key takeaways for decisions

1. **The three video competitors have no equipment features in their listings. OBSERVED.** The US App Store listing text of SwingVision 11.9.67, SevenSix 4.0.2 and Onform 4.7.3 does not mention strings, tension or racket logging (keyword scan). The single "equipment" hit in SevenSix means "no expensive equipment".
   - *Implication (INFERRED):* linking each recorded session to the exact racket and string job is a clear way to stand apart. The string-only apps cannot do this because they have no video or match data.
2. **The stringing-log category is crowded but shallow.** In 2025 and 2026 at least 15 new US iOS apps log restrings or estimate tension: String GOAT, StringSense, RacketLog, String Master, String Tension AI, mystrings, RacketTune, RacquetTuner, String Tension Meter, StringTension and others. Most have fewer than 10 ratings. OBSERVED.
   - The long-running benchmark is **RacquetTune**: $2.99, version 7.7 (2026-04-02), 4.62 stars from 482 US ratings, first released 2010-04-07. OBSERVED.
3. **Reviewers like acoustic tension apps for relative trends and dislike them for absolute numbers.** In the 128 RacquetTune reviews in the public RSS feed:
   - The most common praise is tracking tension loss over time and comparing rackets.
   - The most common complaints are readings 7–15 lb below the machine setting, readings that vary between taps, no reading at all, and trouble with hybrids.
   - Reviews since 2020 average 3.1 stars (20 reviews), against 3.96 for the whole RSS set. OBSERVED. The keyword tally is INFERRED.
4. **The physics explains why.** Cross & Bower (2001) showed that the vibration frequency of the string bed follows `f = (1/(2L))·√(T/μ)` with `L = √(area)`. OBSERVED. Rearranged: `T = π·ρ·D²·A·f²`.
   - The tension in a strung racket right after stringing is about 30% below the machine pull tension for nylon and about 40% below for polyester. OBSERVED.
   - So an honest acoustic reading will never match the number the stringer dialled in.
   - Small input errors also matter. A 0.05 mm gauge error moves the absolute estimate by about 8%. INFERRED by calculation.
   - **Ratios cancel the inputs.** `T/T₀ = (f/f₀)²` for the same racket and string job. **Relative-to-baseline tracking is robust; absolute tension is not.** INFERRED.
5. **Polyester tension loss is real, front-loaded and logarithmic in time.** OBSERVED.
   - Tension falls roughly linearly with log(time) after the first ~100 s and keeps falling over days (Cross, Lindsey & Andruczyk 2000).
   - Polyester loses tension faster than nylon or gut.
   - Pre-stretching or holding tension longer slows the loss.
   - Heat after stringing adds 30–76% more loss (TWU 2016).
6. **Restring intervals are rules of thumb, and the sources disagree.**
   - "Restring as many times a year as you play per week" (Tennis Warehouse; attributed to the USRSA by TennisCompanion).
   - "Restring when tension has dropped about 10%" (Cross 2006).
   - Luxilon: polyester every 20 hours of play.
   - TennisCompanion: twice the times-per-week rule.
   - *Implication (INFERRED):* show these as user-chosen reminder thresholds, never as predictions.
7. **Store string diameter in millimetres as the truth, and the gauge label only as text.** OBSERVED: gauge-to-mm tables disagree between sources. For example, gauge 17 is 1.16–1.24 mm (TennisCompanion) versus 1.20–1.25 mm (Tennis Warehouse). Manufacturers also pick labels for marketing.
8. **Recommended scope (INFERRED):**
   - **P1:** a manual Racket Vault and String Journal with full stringer fields, one-tap "clone last job", automatic hours since restring from JOVRA sessions, and comparisons of performance by setup.
   - **P2, only if it passes a lab gate:** an opt-in "Pitch check" that stores Hz and shows *percentage change from your fresh-string baseline*, labelled Estimated.
   - **Never:** a "tension sensor", wear prediction or medical claim, as the brief requires.

---

## 1. Market scan: racket, string and tension apps (US App Store, 2026-10-07)

Data comes from the iTunes Search and Lookup APIs. OBSERVED unless marked. Rating values are averages; the count is the number of US ratings.

### 1a. Acoustic tension meters (microphone)

| App (id) | Seller | US rating / count | Price model | Version (date) | First release | What it does |
|---|---|---|---|---|---|---|
| **RacquetTune – String Tension** (365729342) | Sten Kaiser | 4.62 / 482 | $2.99 paid | 7.7 (2026-04-02) | 2010-04-07 | Tap-to-measure tension and stringbed stiffness; tension history list and graph; swingweight calculator; stiffness simulator; emails a spreadsheet; tennis, squash, racquetball and badminton. Claims it detects changes as small as 0.1 kg / 0.2 lb. The listing itself warns that in-racket tension and the machine setting are "incomparable". |
| **String Tension AI: Tennis** (6763697805) | Trader Prosperity LLC | 5.0 / 2 | Freemium (PRO) | 2.34 (2026-10-05) | 2026-05-03 | Tension estimate in kg or lb; quality coaching; cross-checks across taps; **calibration against a known reference tension**; readings that fail are set aside; separate main and cross tensions; Apple Health tennis import with duplicates flagged; on-device "String AI Coach" (iOS 26 Apple Intelligence); audio processed on device and never saved; widgets, Siri and Shortcuts; cost per hour. |
| **stringster for Tennis 2.0** (6446997820) | Sportsnext Application GmbH | 1.89 / 9 | Free | 2.1.50 (2025-12-10) | 2023-04-20 | Frequency-based tension; claims data on 200+ frames and 600+ strings; stringer "freshness check" and customer reports. All 4 RSS reviews are 1-star about the racket/string picker blocking measurement (2023–2026). Listing makes arm-protection claims. |
| **TennisTension Pro** (6741165303) | Ivaylo Velichkov | 2.0 / 2 | $1.99/mo or $9.99/yr, 3-day trial | 2.0.1 (2025-06-26) | 2025-06-05 | Claims 0.1 kg accuracy; library of 130+ string models; head size and pattern inputs; "remove the dampener" instruction; calibration. |
| **RacketTune** (6746103106) | Liu Guanchen | 3.5 / 2 | Free | 1.0 (2025-05-23) | 2025-05-23 | Racket specs and tuning calculator; tension measurement that the listing itself calls only an estimate, to be used as a baseline between string jobs. |
| **RacquetTuner** (6755720177) | GijikGumba | 1.0 / 2 | Free plus Premium | 1.0.2 (2025-11-27) | 2025-11-27 | Close copy of RacquetTune's feature list: accuracy indicator, waveform, swingweight, stiffness, CSV. |
| **SweetSpot: Racket Tension** (6742414896) | Gage Fassam | 3.75 / 4 | Free | 1.9 (2026-06-06) | 2025-02-25 | Badminton-focused. One 2026 review reports every reading came out at 800 Hz. |
| **StringTension** (6761807131) | Shenzhen Huopu | 0 ratings | Free plus member | 1.0 (2026-04-09) | 2026-04-09 | Tennis and badminton; "machine setting vs actual" verification for stringers; says readings are "algorithmic estimates for reference only". |
| **String Tension Meter** (6782812710) | Tzu Yu Chou | 0 ratings | Free | 1.0 (2026-06-30) | 2026-06-30 | Mic-based lb/kg readings; racket profiles; archive of string jobs. |
| **mystrings – Tennis** (6670494565) | ARSoftware UG | 0 ratings | Free | 1.0.4 (2026-03-19) | 2026-03-06 | Stringing log plus "tension loss measurement". |

### 1b. String and racket journals without a primary acoustic feature

| App (id) | Rating / count | Version (date) | Notable fields and mechanics (OBSERVED from listing) |
|---|---|---|---|
| **String GOAT – for tennis** (6444395925) | 3.78 / 9 | 1.6.9 (2026-10-06) | Racket specs: brand, model, head size, weight, swingweight, balance, grip size, RA stiffness. String setup: brand, model, type, shape, tension, gauge. Hybrid mains/crosses, **knots and pre-stretch**, 6 feel ratings (Power, Spin, Control, Comfort, Feel, Durability), Apple Watch and Galaxy Watch sessions, "predicted string lifespan", tension history (mains vs crosses), AI chat. Tiers: Free (1 racket), Pro, and Premium with stringer customer management. One 2026 review asks for autocomplete of string names. |
| **StringSense** (6758571944) | 0 ratings | 3.9.0 (2026-09-21) | "String health" score from string type, play time, surface, temperature, intensity, level and racket specs. Claims a dense 18×20 small head extends string life by up to 15% and an open 16×19 large head shortens it by up to 13% (vendor model, UNVERIFIED). After each session it asks whether the strings felt crisp, normal or mushy, and learns your threshold. 1–5 stars plus 5 traits; favourite setups as templates; offline-first; CSV/JSON export in Pro. |
| **RacketLog** (6759014238) | 0 ratings | 1.1 (2026-03-26) | Wear from **two limits, play hours and string age, whichever comes first**. Four statuses: Healthy, Heads-up, Replace soon, Overdue. Defaults per material, user-adjustable. Job fields: brand, model, gauge, material, tension, stringer, colour, cost. Full bed or hybrid; copy previous setup; 7 rating categories; racket nicknames for identical frames; cost per hour; JSON export. |
| **String Master – Tennis Log** (6757102423) | 5.0 / 7 | 1.8.0 (2026-08-08) | Clone the previous job ("Restring"); backdating; feel tags (Soft, Crisp, Stiff, Dead Poly); weather and temperature; community lifespan rankings; racket weight, RA, swingweight, balance in mm, serial; reminder at 90 days or 20% "health". Also makes an arm-strain claim. |
| **Tennis String Hub / WolfPro** (6757133258) | 5.0 / 1 | 1.1.6 (2026-05-23) | "780+ strings" performance data; finding a stringer; shop job tracking and inventory. |
| **Tennis Strings** (6760190408) | 5.0 / 1 | 2.1.0 (2026-03-12) | String encyclopaedia, pro setups, hours-played tracker. |

### 1c. Stringer-shop and marketplace apps (job workflow)

- **RacquetBuddy** (6444046878). OBSERVED: completed jobs notify the customer; job queue; history searchable by customer or stringer.
- **STRUNG App** (6757720720). OBSERVED: job statuses pending/completed/paid; racket library per customer; repeatable setups; string stock consumed as jobs complete; metric or imperial gauge display; QR labels.
- **ServiceLine / ServiceLine Pro** (6777587708 / 6777588537). OBSERVED: marketplace with separate main and cross tensions; filters for stringers with an electric machine; Stripe payouts.
- **StringIt, Racket Ready, Stringer Map, Stringlab (Singapore).** OBSERVED: order tracking and pickup.
- **CourtReserve's stringing module** (web club software). OBSERVED: string inventory with manufacturer, name, gauge and stock; pattern/configuration with lb or kg and main/cross tensions; five preloaded job statuses.

*Implication (INFERRED):* the founder strings his own rackets, so JOVRA needs the stringer's data fields without the shop workflow. Default "Strung by" to Self. Track reel inventory, because screen 18 shows "Add to inventory".

### 1d. What to copy and what to fix (INFERRED from 1a–1c and the reviews in §2)

| Praised or common pattern to keep | Problem to design around |
|---|---|
| One-tap "clone last job" or favourite as a template (String Master, RacketLog, StringSense) | Racket/string pickers that block the main task. stringster's only reviews are about a picker that would not accept a selection. **Free text must always be allowed; a catalog is only a suggestion.** |
| Separate mains and crosses: string, gauge and tension (almost every app) | Hybrids break single-peak acoustic estimates (RacquetTune reviews 2012, 2020). |
| Hours *and* calendar age, whichever comes first (RacketLog) | "Health %" and "predicted lifespan" numbers with no shown evidence. The brief forbids prediction. |
| Feel ratings across 5–7 axes; ratings at more than one point in the string's life | Medical and arm claims (stringster, String Master). Do not copy. |
| Apple Health tennis import with duplicates flagged (String Tension AI) | Apps that need an account or cloud sign-in for basic logging (String Master is ending guest mode). JOVRA's local-first stance fits better. |
| Export to CSV/JSON (RacketLog, StringSense, RacquetTune email spreadsheet) | No support route. One RacquetTune review says there was no way to ask a question. |

---

## 2. RacquetTune review analysis: the category benchmark

Source: the App Store customer-reviews RSS, pages 1–10, sorted most recent. **128 reviews** dated 2010-04-21 to 2026-06-09. Star mix: 80 five-star, 14 four, 4 three, 9 two, 21 one. OBSERVED. The theme counts below come from a keyword pass (INFERRED, approximate).

- **Praise for relative use (about 44 reviews, average about 4.5★).** Reviewers use it to track tension decay after each session or week, compare several rackets, and check whether they or their stringer are consistent. Several say it is "not accurate but precise" (2025-05-27 review, paraphrased). One home stringer re-tests weekly to decide which racket to restring next (2012). One user stops at about 40 lb after stringing at 50 lb (2017). OBSERVED.
- **Absolute readings far below the machine setting (about 18).** Examples:
  - Strung 55 lb, read 40.2 lb (2022).
  - Three DR98s strung at 55 lb, all read about 48 lb (2020).
  - Read 1–2 kg low against other testers (2025).
  - Strung 47 lb on an ERT-confirmed racket, read 58 lb (2020). This one is in the opposite direction.
  - These users are comparing in-racket tension with the machine's pull tension. That mismatch is expected physically (§9.1). OBSERVED, with the interpretation INFERRED.
- **Inconsistent readings or no reading (about 17, average about 2★).**
  - 30 to 60 lb on the same racket within 10 minutes (2025-02).
  - ±4–5 lb when held over a table and struck with a spatula (2021).
  - Never got a reading (2026-06).
  - INFERRED cause: locking onto a higher vibration mode, plus ambient noise and tap technique (§9.4).
- **Hybrids (4 reviews):** no consistent reading with different mains and crosses (2012, 2020). OBSERVED.
- **"String factor" (8 reviews):** advanced users tune the per-string factor until a freshly strung racket matches expectation. One reviewer says the shared online database "can be hit or miss" (2020). OBSERVED.
- **Quiet room needed (3 reviews):** examples include a lawnmower and birds (2010). OBSERVED.
- **iOS regressions:**
  - A March 2026 review reports the app stopped hearing taps after iOS 26.4.
  - Release notes for 7.7: "Fixed the problem with detecting sound on iOS 26.4 and later."
  - *Implication (INFERRED):* a microphone feature needs a pinned audio-session configuration and a regression check on every iOS beta.
- **Usage technique from users (OBSERVED):** tap with a spoon or small wrench; remove dampeners. One racquetball user notes that built-in damping elements defeat the method.

**What this means for JOVRA (INFERRED):**
- Lead with "change since you strung it". Show an in-racket estimate as secondary, with a clear explanation of why it is lower than the machine number.
- Detect a bad tap and refuse to show a number, rather than show a wrong one.
- Treat hybrids as a known limitation.

---

## 3. What a serious stringer records

Each field below is attested by at least one primary or app source (cited inline), or flagged.

### 3a. Frame model (catalog-level, "what kind of racket")
- Brand and model as **free text**. The brief requires text labels only.
- Variant and year. *Why it matters (OBSERVED via retailer and blog sources):* "Head Prestige" covers several heads and patterns. The 2023 line includes Pro 98 in² 18×20, MP 99 in² 16×19 and Tour 95 in² 16×19. A bare model name is ambiguous for the acoustic estimate, which needs head area.
- **Head size**: in² and cm². 1 in² = 6.4516 cm² exactly (from 1 in = 2.54 cm). Examples: 85 in² = 548.4 cm², 98 in² = 632.3 cm², 100 in² = 645.2 cm². INFERRED arithmetic.
- **String pattern**: mains × crosses, for example 16×19, 18×20, 16×18.
- **Stringing instructions**, as the manufacturer prints them:
  - one-piece or two-piece;
  - mains skip holes, tie-off holes, start crosses, shared holes;
  - string lengths (for example 40 ft / 12.2 m one-piece; 23 ft mains + 19 ft crosses two-piece).
  - Source: OBSERVED via a search snippet of a Wilson instruction PDF. The PDF did not download, so the exact values are UNVERIFIED.
- Recommended tension range from the manufacturer (optional).
- Specs, optional and user-measured preferred:
  - length;
  - strung and unstrung weight (g; 1 oz = 28.349523125 g);
  - balance (mm from butt, or "points head-light", widely defined as 1 pt = 1/8 in; UNVERIFIED, not confirmed on the TWU page I fetched);
  - swingweight (kg·cm²);
  - stiffness (RA);
  - beam width (mm).
  - String GOAT, String Master and RacketLog all capture subsets of these. OBSERVED.

### 3b. Racket (a physical stick the player owns)
- Nickname or marker, to tell identical frames apart. RacketLog added "Racket nicknames" in 1.1. OBSERVED.
- Serial number, grip size, purchase date and price (RacketLog, String Master).
- Customisation such as lead tape position and grams, and grip or overgrip notes (String Master "tuning notes").
- Photo.
- Active or retired status.

### 3c. String product
- Brand, model and **aliases**. *Why aliases (OBSERVED):* the string the brief calls "Tier One Ghost Wire" is sold by at least one UK retailer as "Tru Pro T1 Ghost Wire". It is a co-poly in 1.10, 1.175, 1.22 and 1.27 mm (retailer pages). Brand naming is unsettled, so catalog matching must tolerate it.
- **Material category**: natural gut, synthetic gut (nylon solid core with wraps), multifilament, polyester (with "co-poly" meaning a polyester with added feel-enhancing ingredients), and aramid/Kevlar.
  - The four main categories are defined by Tennis Warehouse. OBSERVED.
  - Kevlar is measured separately by Cross et al. (2000). OBSERVED.
  - *Hybrid* is a property of the job, not of the product.
- Construction or shape: round mono, shaped mono (for example 5- or 8-sided), textured, multifilament. UNVERIFIED as a standard taxonomy; String GOAT captures "shape".
- **Gauge label as text** (for example "16L", "17", "1.25") and **nominal diameter in mm**.
  - Real product lines label by mm: Solinco Hyper-G sells 16/1.30, 16L/1.25, 17/1.20, 18/1.15, 19/1.10 and 20/1.05 (retailer listings via search). OBSERVED.
  - Weiss Cannon names products by mm, for example "Silverstring 1.25" in the TWU database. OBSERVED.
- Colour, and lot or reel ID (optional).

### 3d. String job (one restring event)
- Date and time; racket.
- **Strung by**: Self, a named person, or a shop. Keep names local; they are personal data.
- **Machine**: make/model text, and type from {drop-weight, crank lockout, electronic constant-pull, electronic lockout, unknown} (§6).
- **Layout**: full bed or hybrid. For each of mains and crosses:
  - string product;
  - tension value **with the unit as entered**, lb or kg;
  - pre-stretch (none, machine %, or manual);
  - optional measured diameter.
- **Method**: two-piece, one-piece (standard), one-piece around-the-world (ATW), or unknown. Knot types; tie-off tension bump; clamp type (fixed or flying). Machines have a "knot function" that raises the final pull before tie-off. OBSERVED, Gamma 7900 ELS. One guide recommends an extra 20% on the tie-off pull. OBSERVED, TennisGear guide by Richard Parnell; one source only.
- Stringing duration; cost; notes; photos.
- **Measurements after stringing**: an ERT DT, a RDC reading, a Stringmeter reading, or a JOVRA pitch check, with method and units.
- End of life: date; reason (broke, cut out, planned restring, retired); breakage detail (mains or crosses; centre, off-centre, near frame, throat).

### 3e. Use and feel
- **Hours played since restring** and **days since restring**. RacketLog and StringSense use both. OBSERVED.
- **Feel ratings**, user-entered sliders. Apps use 5–7 axes: Power, Spin, Control, Comfort, Feel, Durability, and RacketLog adds Appearance. OBSERVED. The JOVRA reference screen shows Control, Comfort and Spin.
- Ratings at more than one moment: fresh, mid-life and at removal. StringSense asks "once when it comes off". OBSERVED.
- Optional conditions: temperature and humidity (String Master, StringSense). These matter physically because temperature changes stiffness and tension loss (§8).

---

## 4. Units: exact factors and display rules

| Quantity | Exact relation | Notes |
|---|---|---|
| Mass pound to kilogram | **1 lb = 0.45359237 kg exactly** (1959 international pound; NIST lists 4.535 924 E-01 in SP 811 App. B) | OBSERVED (NIST SP 811 rounded factor; exact value per the pound-force definition citing NIST SP 811). |
| Force units used for "tension" | 1 kgf = **9.80665 N exactly** (NIST bold, exact); 1 lbf = 4.4482216152605 N | OBSERVED. Stringing machines and players say "lb" and "kg" but mean lbf and kgf. |
| lb to kg for tension | **kgf = lbf × 0.45359237** exactly, because both use the same standard gravity | INFERRED from the two definitions. |
| Worked values | 50 lb = 22.680 kg; 52 lb = 23.587 kg; 55 lb = 24.948 kg; 60 lb = 27.216 kg; 23 kg = 50.706 lb; 25 kg = 55.116 lb; 28 kg = 61.729 lb | INFERRED arithmetic. |
| Head area | 1 in² = 6.4516 cm² exactly | INFERRED from 1 in = 2.54 cm. |
| String length | 1 ft = 0.3048 m exactly; a typical set is 12.2 m / 40 ft (Tru Pro set page 12.2 m; Wilson 40 ft one-piece) | Partly OBSERVED. |
| Machine tension increments | Yonex Precision 5.2: 11–82 lb in 0.5 lb steps; 5–37 kg in 0.2 kg steps. Gamma 7900 ELS: 11.0–90.0 lb (5.0–40.0 kg) in 0.1 steps, with lb/kg conversion | OBSERVED (retailer spec pages). |

**Display and storage rules (INFERRED recommendation):**
- Store the tension **as entered**: value plus unit, for example 52 lb.
- Compute other units only for display: lb to 0.5, kg to 0.1.
- **Never round-trip the stored value through the other unit.** 52 lb would come back as 23.6 kg and then 52.03 lb, which looks like data corruption to a stringer.
- Keep the user's unit preference in Settings. Screen 20 shows "mph · lb".

### 4a. Gauge and diameter tables: sources disagree

| US gauge | TennisCompanion (author is a USRSA Master Racquet Technician) | Tennis Warehouse Learning Center |
|---|---|---|
| 15 | 1.41–1.49 mm | 1.35–1.40 mm |
| 15L | 1.33–1.41 mm | n/a |
| 16 | 1.26–1.34 mm | 1.25–1.30 mm |
| 16L | 1.22–1.30 mm | n/a |
| 17 | 1.16–1.24 mm | 1.20–1.25 mm |
| 18 | 1.06–1.16 mm | 1.15–1.20 mm |
| 19 | 0.90–1.06 mm | 1.10–1.15 mm |

Both tables are OBSERVED.
- TennisCompanion also lists international gauge equivalents (for example 16 = 8.5) and gauges 13–22.
- It notes that ranges overlap and that manufacturers can pick a gauge for marketing reasons. It says it prefers to quote thickness in millimetres. Paraphrased, OBSERVED.

*Decision (INFERRED):*
- `nominalDiameterMm` is the field the maths uses.
- `gaugeLabel` is display text copied from the packet.
- Show the table only as a hint ("16L is usually about 1.22–1.30 mm") and cite the source in the UI help.
- When an acoustic estimate is involved, prompt for mm, because the error from gauge alone is ±8% (§9.3).

---

## 5. String material categories (for the picker and the help sheet)

OBSERVED from Tennis Warehouse unless noted.
- **Natural gut**: made from cow intestine. Best tension maintenance and most arm-friendly; most expensive.
  - Cross et al. 2000: gut has one of the lowest rates of tension loss and the lowest dynamic stiffness of the types tested (about 20 kN/m). OBSERVED.
- **Synthetic gut**: nylon with a solid core and wraps. Cheapest, all-round.
- **Multifilament**: hundreds or thousands of microfibres. Closest to gut for comfort and power.
- **Polyester / co-polyester**: stiffer, more control and spin, harsher, **loses tension faster**. "Co-poly" means a polyester with feel-enhancing additives.
- **Aramid (Kevlar)**: very stiff. Elongates only 1–2% at 28 kg, against about 4% for polyester and 7–15% for gut and nylon (Cross et al. 2000). OBSERVED.
- **Hybrid**: different strings on mains and crosses. A property of the job.

Densities (Cross 2006), used by the acoustic model, OBSERVED:
- nylon and Kevlar about 1.14 g/cm³;
- natural gut and polyester about 1.34 g/cm³.

---

## 6. Stringing machine types

The types below are summarised from secondary guides; tennis-uni and Wikipedia agree. OBSERVED. Spec details are from retailer pages. OBSERVED.
- **Drop-weight**: a weighted bar falls to horizontal. Constant pull, because the weight keeps pulling until the string is clamped. Cheap and low maintenance. Accuracy depends on setting the bar level.
- **Crank / lockout (spring)**: crank until the spring mechanism locks at the target. Faster, but **once locked it does not keep pulling as the string creeps**, so more tension is lost before clamping.
- **Electronic constant-pull**: a motor holds the target until clamped. Example: the Gamma 7900 ELS has constant pull, 10% or 20% pre-stretch "pull over tension", and a knot function. OBSERVED.
- **Electronic lockout**: a motor pulls to the target, then behaves like a lockout.
- The RacquetTune site says constant-pull machines usually hold the load longer than lockout machines. OBSERVED.

*Why log it (INFERRED):* the same dialled number on a lockout and a constant-pull machine gives different in-racket tension. A string journal that hides the machine type makes "52 lb" look comparable when it is not.

## 7. Pre-stretch, knots, one-piece and two-piece

- **Pre-stretch.**
  - Physical basis: once polymer bonds break they mostly stay broken. That is why a pre-stretched string loses tension more slowly afterwards (Cross & Bower 2001).
  - Holding the initial tension above 20 kg for about 30 s, or pre-stretching one or more times, reduces the rate of loss (Cross et al. 2000). OBSERVED.
  - Machine settings: Yonex Precision 5.2 offers 0/5/10/15/20%; Gamma 7900 ELS offers 10% or 20%; Gamma 9900 ELS 1–30% (search snippet); Wilson Baiardo up to 20% (search snippet). Partly OBSERVED.
  - Pre-stretch is either a machine percentage or a manual method (for example pulling a length of string around a pole). Store the method and the percentage separately. INFERRED.
  - One RacquetTune reviewer logs "pre-stretched 15 sec", a time-based manual variant. OBSERVED. So also allow a duration.
- **Knots.** The Parnell knot is described as one of the two most-used professional knots. OBSERVED, TennisGear guide citing Richard Parnell; one source. Store knot types as an open enum with free text.
- **One-piece vs two-piece.** Manufacturer instructions specify string lengths and hole maps for each (Wilson snippet, UNVERIFIED values). Around-the-world (ATW) is a common one-piece variant. UNVERIFIED as a formal term; widely used. Hybrids are normally two-piece. INFERRED.

---

## 8. Tension-loss behaviour, especially polyester

| Finding | Numbers | Source and label |
|---|---|---|
| Stress relaxation after clamping a single string | A string pulled to 28 kg typically drops to **~24 kg within 20 min** and **~20 kg after 24 h** at fixed length. One or two sets of play drop it another 1–2 kg. | Cross, Lindsey & Andruczyk 2000, *Sports Engineering* 3:219–230. OBSERVED |
| Shape of the curve | **Tension falls linearly with log(time) after the first ~100 s**, even over several days | Same paper and Cross & Bower 2001. OBSERVED |
| Material ranking | Natural gut has one of the lowest loss rates (some Kevlar is lower); **all polyester strings lose tension rapidly** | Cross et al. 2000. OBSERVED |
| Nylon sample, long run | 28 → 24.8 kg in 1000 s; 28 → 21.9 kg at 72 h; extrapolates to 19.1 kg after one year. 18 kg string: → 15.86 kg at 1000 s, → 14 kg at 72 h | Cross & Bower 2001. OBSERVED |
| Polyester sample | 1.30 mm polyester: 28 → 23.3 kg over 1000 s (a short sample) | Cross & Bower 2001. OBSERVED |
| In-racket vs pull tension | Right after stringing, in-racket tension is **about 30% lower than pull for nylon and about 40% lower for polyester**. Causes: stress relaxation, frame distortion, friction between strings, and pull angle with grommet friction (about 1–2 kg, ~7%). Crosses can be up to 10 kg lower than mains. | Cross & Bower 2001. OBSERVED |
| Impacts | 10 pendulum impacts (each ≈ 6 fast serves) cost a further 0.74 kg (18 kg string) or 0.90 kg (28 kg string). About half the loss came on the first impact. | Cross & Bower 2001. OBSERVED |
| During stringing (developer data) | Strings may lose 2–6 kg within 30 min. A 1 mm clamp slip can change tension by up to about 2 kg. Each 1 mm of frame deformation is about 2 kg. Cross friction costs 1–3 kg. | RacquetTune site. OBSERVED; developer-authored |
| Temperature | Raising 20 → 40 °C cuts stiffness by 1.2–14.6% depending on string. **Heating a strung string after it has settled adds 30–76% more tension loss** (for example a racket left in a hot car). | TWU, Lindsey & Cross, 2016-06-06. OBSERVED |
| Lab impact-test tension loss across polyesters | The TWU String Performance Database default view lists 439 polyester strings at 51 lb reference, fast swing. **Median "Tension Loss" 40.9%** (range 20.9–68.0%); stiffness median 200 lb/in (136–281). Examples: Solinco Hyper-G 16L 24.7%; Hyper-G 17 25.7%; Weiss Cannon Ultra Cable 17 47.7%; Weiss Cannon Silverstring 1.25 43.8%. | TWU database page, parsed. OBSERVED values. The exact test protocol behind "Tension Loss (%)" was not stated on the page: UNVERIFIED definition. Do not show these to users as hours of life. |
| String "going dead" | Large early losses; small measured changes in rebound performance even after thousands of impacts; inter-string friction rises with use | TWU, Lindsey, 2013-03-21 and 2013-04-17. OBSERVED |
| Field study | Loss over one hour of play depended on court surface, frame and the string's sheath. Least loss with an 18-main frame on a hard court. | Rogowski et al. 2008, *Proc IMechE Part P* 222:85–89 (abstract via Crossref). OBSERVED |
| User anecdote | A poly user reports losing up to 10% by the time the racket leaves the machine, and another 10% over 48 h | RacquetTune review, 2020. OBSERVED, anecdotal |

**Model implication (INFERRED):**
- If JOVRA ever plots a trend from the user's own pitch checks, the physically motivated fit is `T(t) ≈ a − b·log10(t)` for t > 100 s, with a separate step down per heavy session. It is **not** a straight line in calendar days.
- This is a *fit to the user's own measurements*, not a population prediction.
- It still conflicts with the reference screen's "no tension loss prediction". So: plot the measured points; never extrapolate a "due date" from it unless a later decision record allows it.

---

## 9. Restring interval rules of thumb (label all of them as rules of thumb)

| Rule | Who says it | Label |
|---|---|---|
| Restring **as many times per year as you play per week** | Tennis Warehouse Learning Center; HEAD (per a search snippet; head.com returned HTTP 429); tennis.com 2022 (no USRSA attribution there); attributed to the USRSA by TennisCompanion | OBSERVED (multiple secondary sources). The USRSA attribution is UNVERIFIED at USRSA itself. |
| Restring **when tension has dropped about 10%** (60 lb → 54 lb); average player at least once a year | Rod Cross 2006, "Measuring String Tension" | OBSERVED |
| Polyester: **every 20 hours of play** | Luxilon (luxilon.be news) | OBSERVED (manufacturer) |
| **Double** the times-per-week rule; restring at a 10–15 lb (≈30%) drop from baseline; strings can lose ~10% in the first 24 h | TennisCompanion (Jon Crim, USRSA MRT), updated 2020 | OBSERVED; conflicts with Cross's 10% |
| User threshold ~16–20% loss | A RacquetTune reviewer, 2013 | OBSERVED, anecdotal |
| Material defaults with "hours **or** age, whichever comes first" | RacketLog; StringSense time reminder at 3/6/9/12 months | OBSERVED (app behaviour) |

**JOVRA recommendation (INFERRED):**
- Ship **user-set thresholds**: hours, days, or both; optionally "% change from baseline" if pitch checks exist.
- Offer the rules above as presets in help text, each with its source.
- Wording: "Reminder you set", "Logged court time", never "Your strings are dead".

---

## 10. Acoustic string-bed tension: is an on-device estimate feasible?

### 10.1 Physics (OBSERVED)
- Cross & Bower (2001) model the string bed as a membrane. To within about 1%, the fundamental frequency is `f = (1/(2L))·√(T/μ)`, where:
  - T is the *average* string tension;
  - μ is mass per unit length;
  - L = √A, with A the strung area.
- The frequency depends mainly on **area**, not shape: elliptical against square differs by about 1%.
- Cross (2006) gives `μ = ρ·π·D²/4` and typical frequencies of **500–700 Hz**.
- Rearranged (INFERRED algebra): **`T = π·ρ·D²·A·f²`**, so `T ∝ f²`.
- A 10% tension drop gives a 5% frequency drop, for example 600 → 570 Hz (Cross 2006). OBSERVED.
- Worked check from Cross & Bower Table 1: 1.42 mm nylon (μ = 1.80 g/m), A = 630 cm², `T(kg) = 4.76×10⁻⁵·f²`. Pull 28.4 kg rang at 645 Hz, giving 19.8 kg in the racket. OBSERVED.
- Frame bending modes are far lower: 133 ± 2 Hz (Cross & Bower) and about 152 Hz (TWU). They are easy to exclude from a 350–1100 Hz search band. OBSERVED values; band choice INFERRED.
- Attached mass matters: a 2.2 g piezo plus adhesive lowered the bed frequency by **15.7%**. **A dampener must be removed** before a pitch check (TennisTension Pro gives the same instruction). OBSERVED.

### 10.2 Expected frequencies

Computed with `f = √(T/(π·ρ·D²·A))` for polyester, ρ = 1340 kg/m³, D = 1.25 mm. These are **in-racket** tensions, not machine settings. INFERRED.

| Head (in²) | 35 lbf | 40 lbf | 45 lbf | 50 lbf | 55 lbf |
|---|---|---|---|---|---|
| 85 | 657 Hz | 702 | 745 | 785 | 824 |
| 93 | 628 | 671 | 712 | 751 | 787 |
| 98 | 612 | 654 | 694 | 731 | 767 |
| 100 | 606 | 648 | 687 | 724 | 759 |
| 105 | 591 | 632 | 670 | 707 | 741 |

### 10.3 Error budget for an *absolute* estimate

Baseline: 98 in², poly 1.25 mm, 560 Hz ≈ 29.3 lbf. INFERRED calculation.

| Input error | Effect on estimated T |
|---|---|
| Frequency +1 Hz | +0.4% |
| Frequency +5 Hz | +1.8% |
| Diameter +0.03 mm (1.25 → 1.28) | **+4.9%** |
| Gauge mislabel 1.25 → 1.30 mm | **+8.2%** |
| Density 1340 → 1250 kg/m³ (polyester vs a lighter blend) | **−6.7%** |
| Area 98 → 100 in² | +2.0% |
| Area 98 → 95 in² (wrong Prestige variant) | −3.1% |
| Mains and crosses at different tension | Unknown. Cross & Bower say this "was not investigated in detail". UNVERIFIED |
| Machine reference vs in-racket | −30% (nylon) to −40% (poly) right after stringing (OBSERVED), then the log-time decay |

**Consequences (INFERRED):**
- Without per-racket calibration, an absolute estimate is credible to roughly **±10–15%** at best.
- It will always read well below the machine setting.
- This matches the review pattern in §2.
- RacquetTune's "string factor" and String Tension AI's "calibration against a known reference tension" are the vendors' answer. OBSERVED. In effect they fold D, ρ and the stringing loss into one fitted constant.

**The robust quantity (INFERRED):** for one racket and one string job, `T/T₀ = (f/f₀)²`. Diameter, density and area cancel. What remains:
- the frequency error, about 0.4% of tension per Hz;
- mode identification;
- temperature (§8);
- **changes in the bed itself**, such as strings moving, notching and friction. Users may experience these as "tension loss", which is fine.

### 10.4 Signal processing feasibility (INFERRED, synthetic simulation)

I simulated a decaying sinusoid at 600 Hz:
- 48 kHz sampling, 0.4 s window, Hann window, FFT zero-padded to 2¹⁷, parabolic peak interpolation;
- decay constants τ = 0.05–0.5 s;
- white noise at SNR 30, 15 and 5 dB.

Result: frequency standard deviation **≤ 0.36 Hz in the worst case** (τ = 0.05 s, SNR 5 dB), which is ≤ 0.12% in tension. **Frequency precision is not the bottleneck.**

The real failure modes are physical and environmental:
1. **Locking onto the wrong mode.** For a circular membrane the next modes sit at **1.593×** and **2.136×** the fundamental (Bessel-zero ratios, standard acoustics; Fletcher & Rossing via Cross & Bower). Locking onto the 1.59× mode inflates tension by **2.54×**, the same size as the "30 to 60 lb" review. Tapping at the **centre** favours the fundamental. Cross & Bower placed their sensor at the centre because the fundamental is largest there and several other modes are smallest. OBSERVED rationale.
2. **Hybrids and uneven main/cross tension.** In my simulation, with mains at 610 Hz and crosses at 580 Hz at equal strength, the estimator jumped between the two peaks. That is about a 10% tension flip between taps, matching the hybrid complaints. Real woven beds may couple into one mode; UNVERIFIED.
3. **Ambient noise and the iOS input pipeline.**
   - Use `AVAudioSession` mode **`.measurement`**. Apple documents that it minimises system-supplied signal processing and uses the primary microphone on multi-mic devices. OBSERVED.
   - On Android use `MediaRecorder.AudioSource.UNPROCESSED` (API 24+). Android documents that it "behaves like DEFAULT otherwise" when unsupported. OBSERVED.
4. **Hand damping, dampeners, tap tool, and the racket resting on a table.** From the reviews (§2).

### 10.5 Proposed algorithm (for a P2 feasibility spike; INFERRED design)
- **Capture.**
  - `AVAudioEngine` input tap at 48 kHz mono, category `.record`, mode `.measurement`, `NSMicrophoneUsageDescription` text.
  - Onset detector: energy more than 20 dB above a rolling noise floor. Capture 0.3–0.5 s after onset. Reject clipped buffers.
- **Spectrum.**
  - Accelerate `vDSP` DFT, Hann window, zero-pad, parabolic interpolation.
  - Search band set by the user's own inputs: predict f for 0.45–0.95 × the machine reference tension from §10.1, plus a margin.
  - **Reject** if the strongest peak lies near 1.59× or 2.14× a smaller in-band candidate (mode guard).
- **Multi-tap consensus.**
  - Require ≥ 5 accepted taps; report the median.
  - Pass only if the median absolute deviation is ≤ 2 Hz; otherwise show "Inconsistent — tap the centre, remove dampener, quieter room".
  - Store tap count, spread and SNR.
- **Store the raw measurement:** Hz plus quality metrics. Do not store audio by default. String Tension AI also states audio is processed on device and never saved. OBSERVED.
- **Show, in this order:**
  1. "**Change since baseline**: −8% (Estimated)", where the baseline is the first passing check within N hours of the string job's date.
  2. Optionally, "**Estimated in-racket tension** ≈ 39 lb (machine setting was 52 lb; in-racket tension is normally 30–40% lower)", with a range.
  - Never show more precision than the spread supports.
- **Calibration (optional):** the user enters a reference reading from a device such as an ERT/DT; store it as a separate `Measurement` with its own method. Never overwrite the physics inputs silently.

### 10.6 What must be labelled "Estimated" (INFERRED)
- Any tension, stringbed stiffness or "% loss" derived from sound.
- Any absolute tension shown next to a machine setting.
- Hours since restring derived from JOVRA sessions. Label it "Logged court time": play that was not recorded or logged is missing.
- Any reminder: "Reminder you set at 20 h".
- Never call it a "tension meter" or "sensor".
- Never claim arm or injury benefit. The brief forbids medical claims, and two competitors make them.

### 10.7 Validation gate before shipping (INFERRED)
Use the brief's evidence-gate style.
- **Bench set:**
  - at least 3 frames (for example 93, 98 and 100 in²);
  - at least 3 strings (poly 1.25, multi 1.30, a hybrid);
  - pull tensions 45/52/58 lb on a known machine;
  - iPhone models from at least 2 generations.
- **Reference:** a load-cell or ERT/DT device, as RacquetTune's developer did with strain gauges and a calibrated load cell, followed until the strings broke after about 35 days. OBSERVED.
- **Acceptance (proposed):**
  - test-retest median spread ≤ 1% in frequency;
  - relative-change error ≤ 3 percentage points against the reference trend over 2 weeks;
  - mode-error rate < 1% of accepted readings;
  - a hybrid either passes or is explicitly unsupported.
- **Regression:** re-run the microphone path on each iOS major/minor beta (cf. the iOS 26.4 break).

### 10.8 Patents and licensing (not legal advice; INFERRED unless marked)
- **The method is old and published.**
  - Frequency-to-tension for racket string beds: US 5,007,294 (priority 1987, granted 1991; Google Patents lists it "Expired – Fee Related", 2003). OBSERVED.
  - US 5,406,827 "Pitch/Tension Device" (granted 1995; expired, lapsed 1999). OBSERVED.
  - Cross & Bower (2001) published the membrane formula openly. OBSERVED.
- **Active patents I found are adjacent, not acoustic:**
  - US 11,607,589 B1 is a mechanical *stringbed stiffness* deflection device (Van Denend; active until 2041-06-05). It does not claim acoustic measurement. OBSERVED.
  - US 9,770,631 B2 is a dual-tension *stringing apparatus* (Tarrant; active until 2036). The frequency meter appears only in the description. OBSERVED.
  - US 7,335,120 (colour-coded tension marker) and US 7,600,437 (strain-gauge tester) are expired. OBSERVED.
- **Gap:** I did not search CN/EP/WO filings in depth. Badminton phone-tension tools are common in China. **This is not a freedom-to-operate opinion.** Have counsel run an FTO search before shipping a microphone feature. UNVERIFIED.
- **Data:**
  - Do **not** import RacquetTune's crowd "string factor" database, stringster's 600-string database, or the TWU String Performance Database without a licence. TWU pages carry no visible reuse licence (OBSERVED absence), so treat them as all rights reserved.
  - Build JOVRA's own catalog from user entries plus manufacturer-published nominal diameters, with source and date on each row.
- **Names:** avoid "Tune"/"RacquetTune"-like naming and third-party unit names such as "DT" (ERT) or "RDC" (Babolat) as JOVRA's own unit. Use "Stringbed pitch (Hz)" and "% change". For a sourced reading, store "ERT DT" only as an external measurement method.

**Bottom line (INFERRED):** this is technically feasible on iPhone as a **relative, estimated** pitch check. The scientific basis is public and decades old. Absolute tension is a weak, support-heavy promise. This matches the brief's choice to keep it off the reference screens. Recommend P2 at the earliest, behind the gate above, opt-in microphone (Settings already shows "Microphone · Optional · Off").

---

## 11. Recommended data model

Framework-independent, so it maps to Swift Codable and Kotlin. All entities have `id: UUID`, `createdAt`, `updatedAt` and `deletedAt?` (soft delete for sync/export). Monetary and physical values are stored with explicit units. **User-entered text is never replaced by catalog text.**

```text
FrameModel                      // "what kind of racket" — optional catalog or user-defined
  brand: String                 // free text (brief: text only, no logos)
  model: String                 // free text
  variant: String?              // e.g. "Tour", "MP", "Mid"
  year: Int?
  headSize: Area?               // {value, unit: in2|cm2}  (1 in2 = 6.4516 cm2)
  stringPattern: {mains: Int, crosses: Int}?
  length: Length?               // in|cm
  specsNominal: RacketSpecs?    // weight g, balance mm|ptsHL, swingweight kg·cm2, stiffnessRA, beamMm[]
  recommendedTension: {min: Tension, max: Tension}?
  stringingInstructions: {onePieceAllowed: Bool?, mainsSkip: [String], tieOffMains: [String],
                          startCrosses: String?, tieOffCrosses: [String], lengthOnePiece: Length?,
                          lengthMains: Length?, lengthCrosses: Length?}?
  source: {kind: userEntered|catalog|manufacturerDoc, ref: String?, retrievedAt: Date?}

Racket                          // a physical stick the player owns
  ownerPlayerId
  frameModelId?                 // nullable: "unknown frame" is allowed
  nickname: String              // "Match #1" — disambiguates identical frames
  serial: String?, gripSize: String? (e.g. "4 1/4" or "L2"), purchasedAt: Date?, price: Money?
  specsMeasured: [MeasuredSpec] // {kind: weight|balance|swingweight|ra, value, unit, measuredAt, strung: Bool}
  customization: [Customization]// {kind: leadTape|grip|overgrip|dampener|other, position: String?, grams: Double?, note}
  status: active|retired
  photos: [AssetRef]

StringProduct                   // catalog or user-defined
  brand: String, model: String, aliases: [String]       // "Tier One" / "Tru Pro T1"
  material: naturalGut|syntheticGut|multifilament|polyester|aramid|other
  materialSubtype: String?      // "co-poly"
  construction: round|shaped|textured|multifilament|solidCoreWrap|other
  shapeSides: Int?
  gaugeLabel: String?           // as printed: "16L", "17", "1.25"
  nominalDiameterMm: Decimal?   // the value the math uses
  densityKgM3: Double?          // default by material (gut/poly 1340, nylon/aramid 1140 — Cross 2006)
  color: String?
  source: {kind, ref, retrievedAt}

StringInventoryItem             // screen 18 "Add to inventory"
  stringProductId, form: set|halfSet|reel, initialLength: Length, remainingLength: Length,
  purchasedAt, cost: Money?, lot: String?

StringJob                       // one restring event
  racketId
  strungAt: Date (+ timeZone)
  strungBy: {kind: self|person|shop, displayName: String?}   // personal data → local only
  machine: {makeModel: String?, type: dropWeight|crankLockout|electronicConstantPull|electronicLockout|unknown}?
  layout: fullBed|hybrid
  mains:   StringSegment
  crosses: StringSegment        // == mains product when fullBed (still store tension separately)
  method: twoPiece|onePiece|onePieceATW|unknown
  knots: {mainsTieOff: String?, crossesTieOff: String?, startingKnot: String?}?
  tieOffBump: {percent: Double?} | {tension: Tension?}?
  clampType: fixed|flying|unknown
  durationMin: Int?, cost: Money?, notes: String?, photos: [AssetRef]
  inventoryConsumption: [{inventoryItemId, length: Length}]
  clonedFromJobId: UUID?        // "Log a restring" = clone last job, then edit
  endedAt: Date?, endReason: broke|cutOut|plannedRestring|retired|unknown?
  breakage: {segment: mains|crosses|unknown, location: center|offCenter|nearFrame|throat|top|unknown,
             sessionId: UUID?, videoTimeSec: Double?}?
  // invariant: at most one open (endedAt == nil) job per racket

StringSegment
  stringProductId?              // nullable: free-text-only entry allowed via productSnapshot
  productSnapshot: {brand, model, gaugeLabel, nominalDiameterMm}   // denormalized, survives catalog edits
  tension: Tension              // {value: Decimal, unit: lb|kg} AS ENTERED — never round-tripped
  prestretch: {method: none|machinePercent|manual|unknown, percent: Double?, durationSec: Int?}?
  measuredDiameterMm: Decimal?

Measurement                     // post-stringing checks (manual devices or JOVRA pitch check)
  stringJobId, racketId, takenAt
  method: jovraPitchCheck|ertDT|rdc|stringmeter|other
  raw: {value: Double, unit: "Hz"|"DT"|"RDC"|"kg"|"lb"|String}
  quality: {taps: Int, spreadHz: Double?, snrDb: Double?, accepted: Bool}?
  isBaseline: Bool
  derived: {estimatedTension: Tension?, rangeLow: Tension?, rangeHigh: Tension?,
            changeFromBaselinePct: Double?}?          // always labeled "Estimated" in UI
  inputsSnapshot: {headSizeCm2, diameterMm, densityKgM3, pattern}?  // reproducibility
  algorithmVersion: String, appVersion: String, deviceModel: String
  temperatureC: Double?

SetupRating                     // user feel, multiple per job
  stringJobId, ratedAt, loggedHoursAtRating: Double (snapshot)
  stage: fresh|mid|removal|other
  axes: {control, comfort, spin, power, feel, durability}: Int? (1–5 or 0–10)
  overall: Int?, note: String?

EquipmentUse                    // session ↔ setup link (the differentiator)
  sessionId                     // JOVRA recorded/imported/manual session
  racketId, stringJobId         // resolved at session time; immutable reference
  setupLabelSnapshot: String    // "Head Prestige · Hyper-G 52 / Ghost Wire 50 lb"
  activeMinutes: Double         // excludes paused time
  segment: {startSec: Double?, endSec: Double?}?   // racket swap mid-match
  source: recordedVideo|importedVideo|manualLog|healthKitWorkout
  externalRef: String?          // e.g. HKWorkout UUID, for dedupe
```

**Derived values (never stored as truth; INFERRED rules):**
- `loggedHoursSinceRestring(job)` = Σ `EquipmentUse.activeMinutes` for the job ÷ 60. Label: "Logged court time". Screen 18 shows "6h 42m since restring" as sample data. Compute it; never copy it.
- `daysSinceRestring(job)` = now − `strungAt`.
- `reminderState(job)` = compare against **user-set** thresholds `{hours?, days?, pctChangeFromBaseline?}`, with material-specific defaults the user can see and edit (RacketLog pattern). Never "predicted life".

**Linking sessions to setups (INFERRED rules):**
1. Session setup (screen 4, "Gear" row) defaults to the player's active racket and its single open `StringJob`. The user can change it before or after recording.
2. Every session stores `EquipmentUse` rows with `stringJobId` **and** a label snapshot, so history renders correctly even after edits.
3. If the user backdates a new string job before existing sessions on that racket, prompt to reassign sessions between the new date and the next job. Never move them silently.
4. "**String broke**" can be marked from live capture or replay at a video time. This closes the job (`endReason = broke`, `breakage.sessionId`, `videoTimeSec`) and offers a racket swap, which creates a second `EquipmentUse` segment.
5. Apple Health import is optional. HealthKit has `HKWorkoutActivityType.tennis` (iOS 8+; OBSERVED). Dedupe against JOVRA sessions by time overlap, and flag duplicates for review rather than auto-merging (String Tension AI pattern).
6. **Comparisons by setup** in Insights (for example first-serve %, depth, errors with Hyper-G 52 lb vs 48 lb):
   - show only for the same session type;
   - show sample sizes;
   - require a minimum count, for example at least 3 sessions and at least 100 points per setup;
   - label "Association in your sessions — not proof the strings caused it".

**Units module (INFERRED):**
- `Tension.toKg() = unit == .lb ? value × 0.45359237 : value`, with display rounding only.
- `Area.cm2 = in2 × 6.4516`.
- Gauge help table with its source; the diameter in mm is primary.
- Unit tests:
  - 52 lb shows 23.6 kg and still stores 52 lb;
  - conversion round-trips are never written back;
  - 98 in² converts to 632.3 cm².

**Export (INFERRED):** CSV and JSON of rackets, jobs, measurements and ratings in "Export my data" (screen 20). Competitors export (RacketLog JSON, StringSense CSV/JSON, RacquetTune spreadsheet email). Include `algorithmVersion` and the Hz values so estimates can be recomputed later.

---

## 12. Screen-level recommendations (INFERRED)

- **Racket Vault (17).**
  - Racket cards show nickname plus the free-text frame, the "Active setup" (open job: mains/crosses chips), logged hours, and days since restring.
  - "Log a restring" opens the form pre-filled from the last job.
  - Frame specs appear only if the user entered them or picked a sourced catalog row. **No invented specs.**
- **String Journal (18).**
  - Two-column mains/crosses card: product, gauge label plus mm, tension as entered.
  - Optional pre-stretch, method, knots and machine sit behind "Stringer details". Keep it collapsed for casual users; remember it expanded for the founder.
  - Feel sliders: three visible (Control, Comfort, Spin), with "+ more axes".
  - "Logged court time since restring" with a small per-session bar chart from `EquipmentUse`.
  - "Add to inventory" for reels.
  - "Save stringing note."
  - **No pitch check on this screen until the gate passes.**
- **Session setup (4).** The gear row shows the racket nickname and the setup snapshot. Tapping it switches racket or job. "+ Second racket" is used for swaps.
- **Settings (20).**
  - Units: lb/kg plus in²/cm².
  - Microphone stays "Optional · Off" unless pitch check ships. Its purpose string must name the pitch check explicitly.

---

## 13. Open questions

1. What machine does the founder use: make, model, and constant-pull or lockout? The machine-type enum and default should match it. Does he pre-stretch, and how (percentage or manual time)?
2. Does he want absolute in-racket estimates at all, or only "% change since I strung it"? The brief currently forbids a tension sensor.
3. Which Head Prestige variant and year? The head area differs by up to 6 in² across the line, which matters only for absolute estimates.
4. Should Apple Health tennis workouts count toward string hours? There is double-counting risk with recorded sessions.
5. A catalog strategy is needed: user-entered only in v1, versus a curated, sourced catalog of the founder's strings (Hyper-G, Ghost Wire / Tru Pro T1, Weiss Cannon lines) with aliases.
6. The patent FTO for CN/EP/WO acoustic methods is unresolved; it needs counsel if P2 proceeds.
7. The definition of the TWU "Tension Loss (%)" column (test protocol and number of impacts) is unconfirmed. Do not surface it until it is confirmed and licensed.

---

## Sources

All accessed 2026-10-07.

**Local inputs**
- `/Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md`: founder intent (record, analyse, equipment; iOS then Android).
- `/Users/IDC2.5/jv/design-reference/brief/research.md`, `product-brief.md`, `screens.json`, `implementation-states.md`, `docs/handoff/CLAUDE-BUILD-PROMPT.md`: screen 17/18 constraints ("no invented frame specs", "No automated tension sensor, tension loss prediction or medical claim"), the restring field list, and framework-independent schemas.

**App Store (public iTunes APIs and listings)**
- https://itunes.apple.com/search?term=<racquettune|string tension tennis|tennis stringing|racket stringer|restring|racquet string|string tension meter|tennis racket tension>&entity=software&country=us&limit=50: category census of 1a–1c (IDs, ratings, versions, dates).
- https://itunes.apple.com/lookup?id=365729342&country=us and https://apps.apple.com/us/app/racquettune-string-tension/id365729342: RacquetTune price $2.99, v7.7 (2026-04-02), 4.62/482, released 2010-04-07, feature list, 0.1 kg claim, "incomparable" note, iOS 26.4 fix in release notes.
- https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=365729342/sortby=mostrecent/json: 128 RacquetTune reviews (2010–2026): star mix, themes, quoted fragments.
- https://itunes.apple.com/lookup?id=6763697805&country=us (String Tension AI): calibration, on-device audio not saved, Apple Health import with duplicate flags, v2.34.
- https://itunes.apple.com/lookup?id=6444395925&country=us (String GOAT): racket and string fields, knots and pre-stretch, 6 feel axes, tiers, v1.6.9.
- https://itunes.apple.com/lookup?id=6758571944&country=us (StringSense): health model, pattern/head claims, setup rating and templates, v3.9.0.
- https://itunes.apple.com/lookup?id=6759014238&country=us (RacketLog): hours-or-age limits, statuses, job fields, JSON export.
- https://itunes.apple.com/lookup?id=6757102423&country=us (String Master): clone restring, feel tags, weather, specs, arm-strain claim.
- https://itunes.apple.com/lookup?id=6446997820&country=us plus RSS page 1 (stringster): database claims, arm claims, 1-star picker reviews.
- https://itunes.apple.com/lookup?id=6741165303&country=us (TennisTension Pro): pricing, 0.1 kg claim, remove-dampener instruction, 130+ strings.
- https://itunes.apple.com/lookup?id=6746103106 (RacketTune), 6755720177 (RacquetTuner), 6742414896 (SweetSpot) plus RSS, 6761807131 (StringTension), 6782812710 (String Tension Meter), 6670494565 (mystrings), 6757133258 (Tennis String Hub), 6760190408 (Tennis Strings): category feature claims and estimate disclaimers.
- https://itunes.apple.com/lookup?id=6444046878 (RacquetBuddy), 6757720720 (STRUNG), 6777587708 / 6777588537 (ServiceLine / Pro), 6757498723 (StringIt), 6761485044 (Racket Ready), 6810422031 (Stringer Map), 6769932123 (Stringlab): stringer and shop workflow fields.
- https://itunes.apple.com/lookup?id=989461317, 1505604446, 1490334045 (SwingVision, SevenSix, Onform): no string or racket features in listing text.

**Physics and lab evidence**
- https://www.physics.usyd.edu.au/~cross/StringTension.pdf (R. Cross, "Measuring String Tension", July 2006): f formula with L = √A, densities, 500–700 Hz, 10% tension ≈ 5% frequency, 10% restring rule, frequency charts.
- https://www.physics.usyd.edu.au/~cross/CrossBower.pdf (Cross & Bower 2001, *Sports Engineering* 4:165–175): membrane formula, area dependence, in-racket tension 30% (nylon) / 40% (poly) below pull, Table 1, relaxation data, impact losses, 15.7% piezo mass effect, frame frequency 133 Hz.
- https://www.physics.sydney.edu.au/~cross/PUBLICATIONS/14.%20StringTests.PDF (Cross, Lindsey & Andruczyk 2000, *Sports Engineering* 3:219–230): 28→24 kg in 20 min, ~20 kg at 24 h, log-time linearity, polyester loses fastest, prestretch effect, elongation by material, dynamic stiffness.
- https://www.physics.sydney.edu.au/~cross/String%20sounds/StringTension.htm: frequency examples (380–700 Hz, 1.25 mm nylon).
- https://doi.org/10.1243/17543371JSET19 (Crossref metadata and abstract; Rogowski et al. 2008, *Proc IMechE Part P* 222:85–89): field tension loss after 1 h depends on court, frame and sheath.
- https://twu.tennis-warehouse.com/learning_center/temperature.php (Lindsey & Cross, 2016-06-06): temperature effects on stiffness and tension loss.
- https://twu.tennis-warehouse.com/learning_center/deadstrings.php and https://twu.tennis-warehouse.com/learning_center/deadstringsPart2.php (Lindsey, 2013): string "going dead", early losses, small performance change, friction, energy return.
- https://twu.tennis-warehouse.com/learning_center/stringbeds.php (Lindsey, 2021-09-07): stringbed stiffness method; poly stiffer than nylon.
- https://twu.tennis-warehouse.com/learning_center/reporter2.php: TWU String Performance Database default polyester table (439 rows parsed); stiffness and tension-loss medians and examples; no visible reuse licence.
- https://appmaker.se/home/racquettune/string-machine-vs-racquet-tension/: developer's explanation of machine vs in-racket tension; clamp, frame and friction kg figures; constant pull vs lockout.
- https://appmaker.se/home/racquettune/tension-drop/: developer's load-cell validation until breakage at about 35 days.

**Units and standards**
- https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9: kgf = 9.806 65 N (exact, bold); lb → kg 4.535 924 E-01; lbf → N 4.448 222.
- https://en.wikipedia.org/wiki/Pound_(force): pound = 0.45359237 kg exactly (citing NIST SP 811); lbf = 4.4482216152605 N.
- https://tenniscompanion.org/tennis-string-gauge/: gauge-to-mm table 13–22, overlap note, prefers mm.
- https://www.tennis-warehouse.com/learning_center/gear_guides/tennis_string/material_gauge_tension_explained.html: material categories, the conflicting gauge table, times-per-week rule, poly loses tension faster.

**Rules of thumb and stringing practice**
- https://luxilon.be/news/common-stringing-mistakes-to-avoid: polyester restring every 20 hours.
- https://www.tennis.com/news/articles/keep-it-fresh-string-recommendations (2022-05-16): 1–2 times per week means 1–2 times per year; poly caveat.
- https://tenniscompanion.org/replacing-tennis-strings/: double the times-per-week rule; 10% in 24 h; 10–15 lb / 30% threshold; USRSA attribution.
- https://tennisgear.com.au/blogs/news/stringing-a-tennis-racquet-a-comprehensive-guide-tennisgear-com-au: Parnell knot; extra 20% tie-off pull.
- https://doittennis.com/products/stringing-machines-gamma-7900-els6pt-nonsc-quickmount-stringingmachine: Gamma 7900 ELS pre-stretch 10/20%, knot function, constant pull, 11–90 lb, 0.1 steps.
- https://joybadminton.com/products/precision-5-0-spr50w: Yonex Precision 5.2 pre-stretch 0/5/10/15/20%, tension increments.
- https://en.wikipedia.org/wiki/Stringing_machine and https://tennis-uni.com/en/tennis-stringing-machines/: drop-weight, lockout and electronic constant-pull descriptions.
- https://help.courtreserve.com/en/articles/6679771-stringing-setup: club stringing module fields and statuses.
- Wilson stringing instruction PDF (https://www.wilson.com/sites/default/files/UltraXP_125%20%281%29.pdf): instruction format (one-piece 40 ft; skips and tie-offs). Seen only as a search snippet; the download returned HTML, so the values are UNVERIFIED.
- https://tennisnerd.net/tennis-tools/the-ert-300-is-back/32054 (2023-09-18): ERT 300 DT definition (kp per 1 cm deflection).

**Products named by the founder**
- https://www.tennisnuts.com/tru-pro-t1-ghost-wire-16-1-27mm-tennis-string-set-white-1722494.html: "Tru Pro T1 Ghost Wire" naming, co-poly, 1.27 mm, 12.2 m set.
- Search results for Solinco Hyper-G gauges (Tennis Warehouse catalog page https://www.tennis-warehouse.com/Solinco_Hyper_G_Strings/catpage-HYPERG.html): 16/1.30 to 20/1.05 lineup. Via snippet; the page was not fetched.
- Search results for Head Prestige 2023 variants (https://tennisnerd.net/gear/racquets/head-prestige-2023-review/32124, https://racquetguys.com/products/head-prestige-pro-2023): head sizes and patterns differ across variants. Secondary.

**Platform APIs**
- https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement (and its JSON): measurement mode minimises system signal processing; primary microphone.
- https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:): input tap API.
- https://developer.apple.com/documentation/accelerate/vdsp/dft and https://developer.apple.com/documentation/accelerate/finding-the-component-frequencies-in-a-composite-sine-wave: on-device FFT.
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription: microphone purpose string.
- https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/tennis: tennis workout type (iOS 8.0+).
- https://developer.android.com/reference/android/media/MediaRecorder.AudioSource: UNPROCESSED (API 24), falls back to DEFAULT.

**Patents (Google Patents bibliographic pages)**
- https://patents.google.com/patent/US5007294: frequency-based racket tension method; expired.
- https://patents.google.com/patent/US5406827: pitch/tension device; expired.
- https://patents.google.com/patent/US11607589: mechanical stringbed stiffness device; active to 2041; not acoustic.
- https://patents.google.com/patent/US9770631: dual-tension stringing apparatus; active to 2036; not a measurement claim.
- https://patents.google.com/patent/US7335120: colour-coded tension marker; expired.
- https://patents.google.com/patent/US7600437: strain-gauge tension tester; expired.

**Computations by this researcher (INFERRED, reproducible)**
- Python scripts run in `/private/tmp/claude-502/-Users-IDC2-5-jv/stringing/`: the frequency-tension table, the error-sensitivity table, the FFT precision and hybrid-peak simulation, and the RacquetTune review keyword tally. The scratch JSON stays outside the repo.
