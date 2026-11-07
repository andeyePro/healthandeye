import Foundation
import Observation
import HealthAndICore
#if os(iOS)
import AVFoundation
#endif

/// Haptic (and on iOS spoken) cues when HR leaves or re-enters the chosen band.
@Observable @MainActor
final class ZoneCueService {
    static let shared = ZoneCueService()

    var enabled = true
    var speak = true
    var zoneSetId: String?
    var zoneName: String?
    var state: ZoneState?
    var lastCue: ZoneCue?

    @ObservationIgnored private var engine: ZoneEngine?
    #if os(iOS)
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    #endif

    /// Picks the zone from a heart-rate target (e.g. minutes in Zone 2), else the first HR zone.
    func configure(catalogue: Catalogue) {
        enabled = catalogue.settings.zoneCues
        let hrSets = catalogue.zoneSets.filter { $0.metric == .heartRate }
        let target = catalogue.targets.first { $0.enabled && $0.zoneSetId != nil && $0.zoneName != nil }
        if let target, let set = hrSets.first(where: { $0.id == target.zoneSetId }), let name = target.zoneName {
            configure(zoneSet: set, zoneName: name)
        } else if let set = hrSets.first, let zone = set.zones.first {
            configure(zoneSet: set, zoneName: zone.name)
        } else {
            engine = nil
            zoneSetId = nil
            zoneName = nil
        }
    }

    func configure(zoneSet: ZoneSet, zoneName: String) {
        engine = ZoneEngine(zoneSet: zoneSet, zoneName: zoneName)
        zoneSetId = zoneSet.id
        self.zoneName = zoneName
        state = nil
        lastCue = nil
    }

    /// Feed every HR reading. Returns the cue fired, if any.
    @discardableResult
    func update(hr: Int, at time: Date = .now) -> ZoneCue? {
        guard var engine else { return nil }
        let cue = engine.update(hr: Double(hr), at: time)
        self.engine = engine
        state = engine.currentState
        guard let cue else { return nil }
        lastCue = cue
        if enabled { play(cue) }
        return cue
    }

    private func play(_ cue: ZoneCue) {
        switch cue {
        case .goHarder: Haptics.play(.up)
        case .easeOff: Haptics.play(.down)
        case .backInBand: Haptics.play(.success)
        }
        #if os(iOS)
        guard speak else { return }
        let text: String
        switch cue {
        case .goHarder: text = "Heart rate low. Pick it up."
        case .easeOff: text = "Heart rate high. Ease off."
        case .backInBand: text = "Back in zone."
        }
        synthesizer.speak(AVSpeechUtterance(string: text))
        #endif
    }
}
