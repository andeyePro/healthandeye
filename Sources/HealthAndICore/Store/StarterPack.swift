import Foundation

/// Optional seed data describing kit (never a person): no profile values and no targets.
public enum StarterPack {
    /// Bundled `Resources/StarterPack/*.json` when available, else `catalogue`.
    public static func load() -> Catalogue {
        #if SWIFT_PACKAGE
        if let bundled = loadBundled() { return bundled }
        #endif
        return catalogue
    }

    #if SWIFT_PACKAGE
    static func loadBundled() -> Catalogue? {
        func read<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
            let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "StarterPack")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONCoding.decode(T.self, from: data)
        }
        guard let equipment = read("equipment", [Equipment].self),
              let exercises = read("exercises", [Exercise].self) else { return nil }
        return Catalogue(
            profile: read("profile", Profile.self) ?? Profile(),
            equipment: equipment,
            exercises: exercises,
            zoneSets: read("zones", [ZoneSet].self) ?? [],
            targets: read("targets", [Target].self) ?? [],
            foods: read("foods", [Food].self) ?? [],
            settings: read("settings", Settings.self) ?? Settings()
        )
    }
    #endif

    public static let dumbbellLoad = Load(
        parts: [
            LoadPart(equipmentId: "eq-dumbbell-bar", count: 1),
            LoadPart(equipmentId: "eq-plate-5-03", count: 1),
            LoadPart(equipmentId: "eq-plate-4-92", count: 1),
            LoadPart(equipmentId: "eq-collar-yibaijia", count: 2),
        ],
        perHand: true,
        label: "Bar + 5.03 + 4.92 + collars"
    )

    static let weightsKit = ["eq-dumbbell-bar", "eq-plate-5-03", "eq-plate-4-92", "eq-collar-yibaijia"]

    public static let catalogue = Catalogue(
        equipment: [
            Equipment(
                id: "eq-woodrower", name: "Domyos Row 0214 WoodRower", kind: "rower",
                limits: ["resistance_min": 1, "resistance_max": 15, "dumbbell_max_kg": 25,
                         "static_max_kg": 900, "user_max_kg": 130],
                connection: Connection(protocolName: "ftms", hrRelay: true),
                quirks: [
                    "Console kcal comes from distance/pace, not work: higher resistance reports fewer kcal.",
                    "Console logs only resistance changes made mid-session, so a level set before starting records as 1.",
                ],
                notes: "Folds to a bench; FTMS + HRM over Bluetooth."
            ),
            Equipment(id: "eq-polar-h10", name: "Polar H10", kind: "other",
                      connection: Connection(bleName: "Polar H10"), notes: "max 2 Bluetooth connections"),
            Equipment(id: "eq-dumbbell-bar", name: "1\" smooth dumbbell bar", kind: "bar", massKg: 1.47, quantity: 2,
                      notes: "14 in, 11 cm loadable sleeves"),
            Equipment(id: "eq-plate-5-03", name: "Everlast cement plate 5.03 kg", kind: "plate", massKg: 5.03, quantity: 2,
                      limits: ["per_sleeve_max": 1], notes: "50 mm thick"),
            Equipment(id: "eq-plate-4-92", name: "Everlast cement plate 4.92 kg", kind: "plate", massKg: 4.92, quantity: 2,
                      limits: ["per_sleeve_max": 1], notes: "50 mm thick"),
            Equipment(id: "eq-collar-yibaijia", name: "Yibaijia 25 mm cam-lock collar", kind: "collar", massKg: 0.0531,
                      quantity: 4),
            Equipment(id: "eq-hex-5kg", name: "Songmics 5 kg hex dumbbell", kind: "dumbbell", massKg: 5, quantity: 2),
            Equipment(id: "eq-pullup-bar", name: "Sportneer doorway pull-up bar", kind: "other",
                      notes: "Stored, not yet in use", enabled: false),
            Equipment(id: "eq-band-green", name: "PROIRON assist band (green)", kind: "band", enabled: false),
            Equipment(id: "eq-band-yellow", name: "PROIRON assist band (yellow)", kind: "band", enabled: false),
            Equipment(id: "eq-band-purple", name: "PROIRON assist band (purple)", kind: "band", enabled: false),
        ],
        exercises: [
            Exercise(id: "ex-single-arm-row", name: "Single-arm row", pattern: "pull", unilateral: true,
                     equipmentIds: weightsKit + ["eq-woodrower"]),
            Exercise(id: "ex-single-arm-floor-press", name: "Single-arm floor press", pattern: "push", unilateral: true,
                     equipmentIds: weightsKit),
            Exercise(id: "ex-press-up", name: "Press-up", pattern: "push"),
            Exercise(id: "ex-goblet-squat", name: "Goblet squat", pattern: "squat", equipmentIds: weightsKit),
            Exercise(id: "ex-split-squat", name: "Split squat", pattern: "squat", unilateral: true, equipmentIds: weightsKit),
            Exercise(id: "ex-single-leg-rdl", name: "Single-leg RDL", pattern: "hinge", unilateral: true,
                     equipmentIds: weightsKit),
            Exercise(id: "ex-suitcase-carry", name: "Suitcase carry", pattern: "carry", unilateral: true, measure: .time,
                     equipmentIds: weightsKit),
            Exercise(id: "ex-bicep-curl", name: "Bicep curl", pattern: "pull", equipmentIds: weightsKit),
            Exercise(id: "ex-row", name: "Row", pattern: "cardio", measure: .distance, equipmentIds: ["eq-woodrower"],
                     notes: "Strokes and distance come from the rower over FTMS."),
        ],
        zoneSets: [
            ZoneSet(id: "zs-heart-rate", name: "Heart rate (example)", metric: .heartRate,
                    zones: [Zone(name: "Zone 2", lower: 110, upper: 120)]),
        ]
    )
}
