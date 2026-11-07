# Changelog

## 2026-11-07

- [x] **Health&I v0.1 skeleton, built in one night** — Six parallel agents built against a binding core contract (`docs/core-api.md`), then integrated and verified in the iPhone and Watch simulators on the Mac build account.
  - Core package `HealthAndICore` (pure Swift, 49 XCTest tests green): data model with readable slug ids and snake_case JSON; file store whose folder is the export (catalogue JSON, per-session JSON + Markdown, daily snapshots, README/schema/digest/log.csv); load builder (bar + plates + collars, limit warnings); starter pack (kit only, no personal data); FTMS rower-data/feature/control-point parsers; HR measurement parser; zone engine with hysteresis and cue spacing; session recorder; Keytel energy estimate; PI resistance controller (unused); session Markdown, digest, CSV, schema and readme renderers; training-log CSV importer; progression hints driven by editable thresholds.
  - Shared services: store controller (iCloud Drive container or chosen folder, starter-pack choice, on-disk catalogue diff on foreground), CoreBluetooth manager for FTMS rowers and HR straps (control-point writes gated off), HealthKit read/write per module toggle, WatchConnectivity bridge, zone cues (haptic + voice), rest timer.
  - iOS app: Today, Log, Row (live HUD with reorderable tiles, device/HR-source/zone pickers, FTMS feature debug sheet), Weights (load builder, RIR/RPE, tags, rest timer, hints), Catalogue editors, Settings (modules, effort scale, HUD order, folder picker, rebuild export, starter pack).
  - watchOS app: Row (HKWorkoutSession HR, paged HUD mirrored from the phone, haptic cues), Weights (Crown reps, RIR, rest haptics), Recent.
  - Repo: AGPL-3.0, andeye CLA v1.0 + CLA Assistant workflow, XcodeGen `project.yml` (iOS 18 / watchOS 11, `com.andeye.health`), Mac build bridge `scripts/mac-test.sh`, gitignored `Martin/` for private data.
  - Verified: both targets build for the simulators; the iOS app launches, seeds the starter pack and writes the full export folder (README, schema, digest, log.csv, catalogue/*.json). Rowing and HealthKit are untested on hardware.
