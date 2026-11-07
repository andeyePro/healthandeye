# Health&I spec v0.2 (repo copy)

Derived from the brain2 draft of 2026-11-07, with Martin's decisions applied the same night. Decisions: JSON not YAML; export folder = iCloud Drive (user-choosable); advice status in advice/status.json (the app never edits Claude's files); closed-loop resistance is a post-v1 experiment; rowing is built first; RIR default; iOS 18 / watchOS 11 minimum; bundle ids com.andeye.health and com.andeye.health.watchkitapp; AGPL-3.0 + andeye CLA; public from day one; Martin's own profile/targets live in the gitignored Martin/ folder, the public starter pack describes kit only.

## Brief (Martin, 2026-11-07)

1. Cover at least rowing on our machine and free weights with the weights we have.
2. Nothing hard-coded. Everything optional and easily editable.
3. iOS universal (iPhone and iPad) and Apple Watch as a minimum.
4. Claude must be able to read all relevant data easily, to give bespoke health, fitness and diet advice.

## Design principles

1. **Data, not code.** Every machine, weight, exercise, zone, target, unit, stopping rule and notation is a user-editable record. The app ships with an empty catalogue plus an optional *starter pack* that describes today's kit (below). Delete or change any of it and nothing breaks.
2. **Everything optional.** Each module (rowing, free weights, nutrition, body metrics, HealthKit read, HealthKit write, export, advice) has an on/off switch. A session can be logged with as little as an exercise name.
3. **Editable two ways.** In the app, and as plain files in the export folder. Edits to the files are re-imported, so Claude or Martin can change the catalogue without touching the UI.
4. **Local-first.** No server, no account. Data stays on device and in the folder Martin chooses. Nothing is sent anywhere else.
5. **One source of truth per number.** Each value records where it came from (H10, Watch, rower console, manual) so conflicting sources are visible, not silently merged.

## Platforms

- iOS universal (iPhone, iPad) and watchOS, Swift + SwiftUI. Minimum OS: current major release at build time (assumed iOS 26 / watchOS 26 `[D]`, Martin to confirm).
- Watch app works standalone during a session; syncs to the phone afterwards.
- Mac: not required. The Mac reads the export folder (see Advice interface).

## Data model (all user-editable)

| Entity | Holds | Notes |
|---|---|---|
| Profile | height, date of birth, sex, max HR, resting HR, units, time zone | every field optional; max HR can be measured or formula-derived, formula selectable |
| Equipment | name, type, limits, connection details, quirks | e.g. a rower, a bar, a plate, a collar, a band, a bench |
| Load component | mass, quantity, which equipment it fits | bar + plates + collars compose a load |
| Exercise | name, pattern, unilateral y/n, measured by (reps / time / distance / strokes), equipment it uses | user-defined; no built-in exercise list |
| Zone set | named HR or power bands | e.g. "Zone 2 = 110-120 bpm"; multiple sets allowed |
| Target | any metric, period, value, optional | e.g. 175 min/week in a zone, 130 g protein/day |
| Session | start, end, type, notes, linked HealthKit workout | container for sets and intervals |
| Set | exercise, side (L/R/both), reps or distance or time, load, RIR, rest before, notes | notation configurable, default `reps@RIR` |
| Interval | time series from a machine or sensor | rower data, HR, resistance level |
| Food | name, per-100 g nutrients, serving sizes | user-defined library |
| Intake | food, amount, time | optional module |
| Body measure | weight, body fat, waist, etc., source | manual or HealthKit |
| Advice note | text from Claude, date, status (open / done / rejected) | see Advice interface |

## Rowing module

1. Connect to any rower that speaks Bluetooth **FTMS** (Fitness Machine Service 0x1826): read Rower Data (0x2AD1), Training Status, Fitness Machine Status `[D]`.
2. HR source is selectable per session: Polar H10 direct, Apple Watch, or HR relayed by the rower. Record which was used.
3. Live HUD on iPhone/iPad and Watch: HR against the selected zone, stroke rate, pace, distance, resistance, elapsed time. Every tile optional and reorderable.
4. Zone guidance: haptic and audio cues when HR leaves the chosen band.
5. **Closed-loop resistance (optional, gated):** adjust resistance through the FTMS Control Point (0x2AD9) to hold HR in band. Ships disabled until the machine is proven to accept control-point writes. Model on EricBriscoe/heartdrive (PI controller on HR) `[D]`.
6. Machine quirks are equipment records, not code, so the app can warn about them. Starter pack carries the known Woodrower ones (below).
7. Energy: prefer HR-derived estimate; show the console's figure separately, labelled.

## Free weights module

1. **Load builder:** compose a per-hand load from components (bar + plates + collars). The app sums them, so changing a plate updates every future set. Show the total and the parts.
2. Equipment limits are checked against the load, e.g. a bench's dumbbell limit, and warn when exceeded.
3. Log sets as reps, time or distance; unilateral exercises log L and R separately.
4. RIR (or RPE, user's choice) per set. Default stopping rule and notation are editable settings.
5. Rest timer per exercise, editable; actual rest recorded, including interruptions.
6. Variant tags per set, user-defined (e.g. "same-side load", "hand on wall"), so variations can be compared without new exercises.
7. **Progression hints (optional):** flag when a load is too light (e.g. reps far above target range at low RIR) or when reps rose across sets (under-warmed). Rules are editable thresholds, not fixed logic.
8. Watch: log reps with the Digital Crown, start rest timer on tap, haptic at end of rest.

## Nutrition module (optional)

1. User-defined food library with per-100 g nutrients and named servings.
2. Daily targets for any nutrient, all optional.
3. Eating-window display optional, for any pattern including one meal a day.
4. Quick-add favourites (e.g. a usual meal) in one tap.
5. No built-in food database in v1.

## Apple Health (HealthKit)

Every permission is requested only when its module is switched on.

- **Read (optional each):** heart rate, resting HR, HRV, VO2 max, weight, body fat, lean mass, waist, sleep, steps, active energy, workouts from other apps.
- **Write (optional each):** workouts (rowing, traditional strength training, functional strength training), active energy, HR samples, distance, dietary energy and macros.
- Never overwrite another app's data.

## Advice interface (Claude-readable)

The point of the app. Claude reads plain files; it never needs the app, a server or an API.

1. **Export folder:** user-chosen; default iCloud Drive `Health&I/`. Written after every session and once a day.
2. **Layout:**
   - `README.md` - what each file is; written by the app so any reader can orient itself.
   - `schema.md` - every field, unit and allowed value.
   - `profile.json`, `equipment.json`, `exercises.json`, `zones.json`, `targets.json`, `foods.json` - the catalogue.
   - `sessions/YYYY/YYYY-MM-DD-HHMM-<type>.json` - one file per session, sets and intervals included.
   - `sessions/YYYY/YYYY-MM-DD-HHMM-<type>.md` - the same session as readable text.
   - `daily/YYYY/YYYY-MM-DD.json` - day snapshot: HealthKit metrics, intake, totals against targets.
   - `digest.md` - rolling summary: last 7 and 28 days against targets, trends, flags, open advice.
   - `log.csv` - flat table of all sets and sessions, for spreadsheets.
   - `advice/` - see 4.
3. **Round-trip:** edits to the catalogue YAML files are imported on next launch, with a confirmation listing what changed. Session files are read-only to the app.
4. **Advice back in:** Claude writes `advice/YYYY-MM-DD-<topic>.md`; the app shows each as a card Martin can mark done or reject. The status is written back to the file, so Claude can see what was acted on.
5. Units and provenance are in every record, so Claude never has to guess.
6. Privacy: the folder holds health data. It stays wherever Martin points it; the app never uploads it.

## Imports (optional)

- Training Log Google Sheet CSV (current log from 2026-09-04).
- Apple Health history (via HealthKit read, not a file).
- Polar Flow and EConnected: only if an export format exists; investigate, don't assume.

## Starter pack (seed data, deletable)

Today's kit as records, so the app is useful on day one. Source: [[Personal]] training notes and the Training Log sheet.

- Rower: Domyos Row 0214 WoodRower, folds to bench; FTMS + HRM over Bluetooth; resistance 1-15; bench dumbbell limit 25 kg; static 900 kg; user max 130 kg.
- Rower quirks: console kcal comes from distance/pace, not work (higher resistance reports fewer kcal); console logs only resistance changes made mid-session, so a level set before starting records as 1.
- HR strap: Polar H10, max 2 Bluetooth connections.
- Watch: Apple Watch Series 12.
- Bars: 1" smooth dumbbell bars, 1.47 kg, 14", 11 cm loadable sleeves.
- Plates: Everlast cement 5.03 kg and 4.92 kg (one per sleeve max, 50 mm thick).
- Collars: Yibaijia 25 mm cam-lock, 53.1 g each.
- Fixed: Songmics 5 kg hex dumbbells.
- Stored, not yet in use: Sportneer doorway pull-up bar; PROIRON assist bands (green, yellow, purple).
- Composed load: 11.53 kg per hand.
- Zone: "Zone 2" 110-120 bpm. Max HR 173 (age formula).
- Targets: 1,650 kcal/day, 130 g protein/day, 175 min/week in Zone 2. All editable.
- Exercises used so far: single-arm row, single-arm floor press, press-up, goblet squat, split squat, single-leg RDL, suitcase carry, bicep curl, row.

## Known constraints and unverified points

1. **Unverified:** whether the WoodRower accepts FTMS Control Point writes. Gates closed-loop resistance. Test first with a BLE scanner (e.g. nRF Connect).
2. H10's two-connection limit: if the rower and another app hold both, the app cannot also connect. Prefer reading HR via the app only.
3. Whether the Watch can take H10 HR while the phone holds the rower connection - test `[D]`.
4. FTMS characteristic support varies by machine; read the Fitness Machine Feature characteristic and adapt, never assume `[D]`.

## Out of scope for v1

Social features, coaching plans, a food database, Android, web app, a server or account.

## Open decisions for Martin

1. Minimum iOS/watchOS version.
2. Licence (siblings use AGPL-3.0) and whether it ever goes public.
3. Default export folder: iCloud Drive, or a folder on CurNAS01.
4. RIR or RPE as the default effort scale.

## Build order

1. Data model, catalogue editor, starter pack, export folder.
2. Free weights logging (iPhone + Watch).
3. Rowing: FTMS read, HR, HUD, zone cues.
4. HealthKit read/write.
5. Advice round-trip and digest.
6. Nutrition.
7. Closed-loop resistance (if the control-point test passes).

Related: [[andeye]] · [[Personal]]
