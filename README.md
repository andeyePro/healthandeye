# Health&I

Your health, training and diet, as plain files you own. iPhone, iPad and Apple Watch.

- Logs rowing (any Bluetooth FTMS machine) and free weights (a load builder that sums your bar, plates and collars).
- Nothing hard-coded: machines, weights, exercises, zones, targets and notation are records you edit.
- Every module is optional: rowing, weights, nutrition, body metrics, Apple Health read, Apple Health write, export, advice.
- Local-first: no server, no account. Your data lives in a folder you choose (iCloud Drive by default) as JSON, Markdown and CSV, so any AI assistant can read it and advise you, and you can edit the catalogue in a text editor.

Status: pre-alpha, built from 2026-11-07. Licence AGPL-3.0 (`LICENSE`); contributions under the andeye CLA (`CLA.md`).

## Build
`xcodegen generate` (XcodeGen 2.46+) then open `HealthAndI.xcodeproj` in Xcode 26+, or `swift test` for the core package. See `CLAUDE.md`.
