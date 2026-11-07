import Foundation

/// schema.md: every file and field with unit and allowed values.
public enum SchemaDoc {
    public static func render() -> String {
        """
        # Health&I schema

        Reference for every file in this folder. See `README.md` for what each file is for.

        General rules:
        - Encoding: UTF-8 JSON, pretty-printed, keys sorted and snake_case.
        - Dates/times: ISO 8601 with offset, e.g. `2026-11-07T07:30:00Z`. Day keys: `YYYY-MM-DD`.
        - Ids: readable slugs (lowercase, hyphens), unique within their file, e.g. `ex-goblet-squat`.
          Other records refer to them by id.
        - Every field is optional except `id` and `name` (where present). Missing fields take the
          default shown; unknown keys are ignored, so you may add your own.
        - Catalogue files hold a JSON array of records unless stated otherwise.

        ## Shared values

        `source` (provenance of a measured value): `polar_h10`, `apple_watch`, `machine` (e.g. the
        rower console), `manual`, `health_kit`, `estimate` (computed by the app).

        ## catalogue/profile.json (one object)

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | height_cm | number, cm | |
        | date_of_birth | date | used for age-based max HR and energy estimates |
        | sex | string | `female`, `male`, `other` |
        | max_hr | integer, bpm | measured or stored maximum heart rate |
        | max_hr_formula | string | `220_minus_age` (Fox), `tanaka` (208 - 0.7 × age), `measured` (use max_hr) |
        | resting_hr | integer, bpm | |
        | units | string | `metric`, `imperial` (display only; files are always metric) |
        | time_zone | string | IANA name, e.g. `Europe/London`; used for local dates in exports |
        | body_mass_kg | number, kg | |

        ## catalogue/equipment.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id, name | string | required |
        | kind | string | `rower`, `bar`, `plate`, `collar`, `bench`, `dumbbell`, `band`, `other` (default) |
        | mass_kg | number, kg | mass of ONE item (bar, plate, collar, fixed dumbbell) |
        | quantity | integer | how many are owned |
        | limits | object of name → number | e.g. `dumbbell_max_kg`, `user_max_kg`, `max_kg` (kg), `per_sleeve_max` (plates per bar sleeve), `resistance_min`, `resistance_max` (machine levels) |
        | connection | object | `ble_name` (Bluetooth name), `protocol_name` (e.g. `ftms`), `hr_relay` (true if the machine relays a heart-rate strap) |
        | quirks | array of string | known machine behaviours the app should warn about |
        | notes | string | |
        | enabled | boolean | default true; false hides it without deleting |

        ## catalogue/exercises.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id, name | string | required |
        | pattern | string | free, e.g. `squat`, `hinge`, `push`, `pull`, `carry` |
        | unilateral | boolean | default false; true = sets logged per side (left/right) |
        | measure | string | `reps` (default), `time`, `distance`, `strokes` |
        | equipment_ids | array of equipment id | |
        | default_rest_seconds | integer, s | rest timer default |
        | target_rep_min, target_rep_max | integer, reps | target range; used by progression hints |
        | notes | string | |
        | enabled | boolean | default true |

        ## catalogue/zones.json (zone sets)

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id, name | string | required |
        | metric | string | `heart_rate` (bpm, default) or `power` (W) |
        | zones | array | each `{name, lower, upper}`; bounds inclusive, in the set's metric unit |

        ## catalogue/targets.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id | string | required |
        | metric | string | free; known: `minutes_in_zone` (min, from session summaries), `energy_kcal` (kcal), `protein_g` (g), any nutrient key from foods, any daily metric |
        | period | string | `day` (default) or `week` |
        | value | number | goal per period, in the metric's unit; met when reached or exceeded |
        | zone_set_id, zone_name | string | for `minutes_in_zone`: which zone counts |
        | enabled | boolean | default true |

        ## catalogue/foods.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id, name | string | required |
        | per_100g | object of nutrient → number | per 100 g of food; keys such as `energy_kcal` (kcal), `protein_g`, `fat_g`, `carbs_g`, `fibre_g` (g) |
        | servings | array | each `{name, grams}`, e.g. `{"name": "slice", "grams": 36}` |

        ## catalogue/settings.json (one object)

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | modules | object of module → boolean | modules: `rowing`, `weights`, `nutrition`, `body`, `health_kit_read`, `health_kit_write`, `export`, `advice`; extra flags such as `closed_loop` allowed. Absent = on for `weights` and `export`, off otherwise |
        | effort_scale | string | `rir` (reps in reserve, default) or `rpe` (rate of perceived exertion, 1-10) |
        | set_notation | string | display notation, default `reps@RIR` |
        | hud_tiles | array of string, ordered | `heart_rate`, `zone`, `stroke_rate`, `pace`, `distance`, `resistance`, `elapsed` |
        | progression | object | `enabled` (default true); `too_light_reps_above` (reps, default 3): flag "too light" when reps ≥ target_rep_max + this AND RIR ≥ `too_light_rir_at_least` (default 3); `under_warmed_rep_rise` (reps, default 2): flag "under-warmed" when reps rise by at least this between consecutive sets of one exercise and side |
        | zone_cues | boolean | haptic/audio cue when heart rate leaves the zone; default true |
        | energy_prefers_hr | boolean | prefer the HR-based energy estimate over the console figure; default true |

        ## sessions/YYYY/YYYY-MM-DD-HHMM-<type>.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id | string | required; matches the file name stem |
        | start, end | date-time | end may be absent |
        | type | string | free, e.g. `rowing`, `weights`, `other` |
        | notes | string | |
        | health_kit_workout_id | string | the linked Apple Health workout |
        | hr_source | source | which heart-rate sensor was used |
        | equipment_ids | array of equipment id | |
        | sets | array of set | see below |
        | intervals | array of series | sensor/machine time series, see below |
        | summary | object of name → number | `distance_m` (m), `avg_hr`, `max_hr` (bpm), `minutes_in_zone` (min), `avg_stroke_rate` (strokes/min), `avg_pace` (s per 500 m), `energy_kcal_hr` (kcal, HR estimate), `energy_kcal_console` (kcal, rower display); others allowed |

        Set:

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id | string | required |
        | exercise_id | exercise id | |
        | side | string | `both` (default), `left`, `right` |
        | reps | integer | |
        | seconds | number, s | for timed sets |
        | meters | number, m | for distance sets (e.g. carries) |
        | load | object | `parts`: array of `{equipment_id, count}` summed from equipment `mass_kg`; `fixed_kg` (kg) added on top or used alone; `per_hand` (default true: the load is per hand/implement); `label` (free) |
        | rir | number | reps in reserve, 0 = failure |
        | rpe | number | 1-10 |
        | rest_before_seconds | number, s | actual rest before this set |
        | rest_interrupted | boolean | rest was interrupted |
        | variant_tags | array of string | user-defined variations, e.g. `hand on wall` |
        | notes | string | |
        | timestamp | date-time | when the set was logged |

        Interval series:

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | metric | string | `heart_rate` (bpm), `stroke_rate` (strokes/min), `pace_s_per_500m` (s), `distance_m` (m), `resistance` (machine level), `power_w` (W), `energy_kcal` (kcal), `stroke_count` |
        | unit | string | unit of `v` |
        | source | source | |
        | samples | array | each `{t, v}`: `t` seconds from session start, `v` the value |

        ## sessions/YYYY/YYYY-MM-DD-HHMM-<type>.md

        Generated Markdown copy of the session JSON: header, sets grouped by exercise, rowing
        summary, per-minute means of each interval series. Read-only; regenerated from the JSON.

        ## daily/YYYY/YYYY-MM-DD.json (one object)

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | date | string | `YYYY-MM-DD` |
        | metrics | object of name → number | daily Apple Health values, e.g. `steps`, `resting_hr` (bpm), `hrv_ms` (ms), `active_energy_kcal` (kcal), `sleep_h` (h) |
        | intake | array | each `{id, food_id, grams, time}` |
        | totals | object of nutrient → number | intake summed from foods' `per_100g` |
        | targets | array | each `{target_id, value, target, met}` for daily targets |

        ## body/measures.json

        | Field | Type / unit | Allowed values / notes |
        |---|---|---|
        | id | string | required |
        | metric | string | e.g. `weight_kg` (kg), `body_fat_pct` (%), `waist_cm` (cm), `lean_mass_kg` (kg) |
        | value | number | in the metric's unit |
        | time | date-time | |
        | source | source | |

        ## advice/<YYYY-MM-DD>-<topic>.md

        Markdown written by Claude or a person; the file stem is the note's id. First `# ` heading =
        title; date from the file name. The app never modifies these files.

        ## advice/status.json (one object)

        `{"<file stem>": "open" | "done" | "rejected"}`. Written only by the app. Absent = open.

        ## log.csv

        RFC 4180 CSV (comma separated, CRLF line ends, fields with commas, quotes or line breaks
        quoted, quotes doubled). One row per set (`row_kind` = `set`) and one per rowing session
        (`row_kind` = `session_summary`).

        | Column | Unit / notes |
        |---|---|
        | session_id | session id |
        | date | local start, `YYYY-MM-DD HH:MM` |
        | type | session type |
        | exercise | exercise name (blank on summary rows) |
        | side | `both`, `left`, `right` |
        | reps | count |
        | seconds | s (session duration on summary rows) |
        | meters | m (distance on summary rows) |
        | load_kg | kg, total load (per hand when the load is per hand) |
        | rir, rpe | effort |
        | rest_s | s, rest before the set |
        | tags | variant tags joined by `;` |
        | notes | set notes (session notes on summary rows) |
        | exercise_id | exercise id |
        | row_kind | `set` or `session_summary` |
        | duration_s, distance_m, avg_hr, max_hr, minutes_in_zone, avg_stroke_rate, avg_pace, energy_kcal_hr, energy_kcal_console | session summary values, units as in session `summary`; blank on set rows |

        ## digest.md, README.md, schema.md

        Generated Markdown; regenerated by the app, so edits are overwritten.
        """ + "\n"
    }
}
