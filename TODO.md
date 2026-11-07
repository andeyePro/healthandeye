# TODO

## Open
- [ ] Hardware test: pair the WoodRower and Polar H10 on a real iPhone; check the FTMS feature flags in the Row debug sheet and whether HR relays via the rower.
- [ ] Hardware test: Watch app standalone (HR from the Watch sensor or a paired H10), live HUD mirroring, set logging round-trip.
- [ ] Today tab sums minutes-in-zone across all sessions without checking which zone each used; use the target's zone.
- [ ] Targets have no direction (ceiling vs floor): a 1,650 kcal/day limit currently counts as met when exceeded. Add `direction` to Target.
- [ ] Daily snapshot writer: nothing yet writes `daily/` once a day (HealthKit metrics + intake); Today reads HealthKit live instead.
- [ ] Nutrition UI (food library, intake, eating window): model and DayBuilder exist, no screens.
- [ ] Body metrics UI.
- [ ] Sleep minutes from HealthKit may double count when Watch and iPhone both record a night.
- [ ] Verify whether the Domyos WoodRower exposes the FTMS Control Point (nRF Connect service dump) before enabling closed-loop resistance.
- [ ] Training Log Google Sheet CSV: real column names (importer ships with a guessed mapping).
- [ ] CLA Assistant Lite workflow is staged; confirm the allowlist account name (Aqueum assumed from the commit identity) and add the CLAAssistant check to branch protection.
- [ ] Nutrition module UI (core model exists).
- [ ] Closed-loop resistance experiment (PI controller exists in core, unused).
