import Foundation
import Observation
@preconcurrency import WatchConnectivity
import HealthAndICore

/// Live rowing HUD state, phone -> watch.
struct HUDSnapshot: Codable, Equatable, Sendable {
    var hr: Int?
    /// `ZoneState` raw value: below / inBand / above.
    var zoneState: String?
    var strokeRate: Double?
    /// Seconds per 500 m.
    var pace: Int?
    var distance: Double?
    var resistance: Int?
    var elapsed: Double?
    var sessionActive: Bool
    var sentAt: Date

    init(hr: Int? = nil, zoneState: String? = nil, strokeRate: Double? = nil, pace: Int? = nil, distance: Double? = nil,
         resistance: Int? = nil, elapsed: Double? = nil, sessionActive: Bool = false, sentAt: Date = .now) {
        self.hr = hr
        self.zoneState = zoneState
        self.strokeRate = strokeRate
        self.pace = pace
        self.distance = distance
        self.resistance = resistance
        self.elapsed = elapsed
        self.sessionActive = sessionActive
        self.sentAt = sentAt
    }
}

enum WatchCommand: String, Codable, Sendable {
    case startSession = "start_session"
    case stopSession = "stop_session"
}

/// Ties a weights message to one session. The phone owns the saved session; the watch tags every set and
/// command with the id, and the phone publishes its own current session the same way in the application
/// context, so both sides log into one id and merges line up by session id and set id.
struct WeightsLink: Codable, Equatable, Sendable {
    var sessionId: String
    var start: Date
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", start, active
    }
}

/// WatchConnectivity on both sides. Payloads are JSON `Data` under a single key so that only
/// Sendable values cross from WCSession's queue to the main actor.
@Observable @MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private enum Key {
        static let snapshot = "snapshot"
        static let set = "set"
        static let command = "command"
        static let catalogue = "catalogue"
        static let session = "session"
        static let weights = "weights"
    }

    var latestSnapshot: HUDSnapshot?
    var incomingSets: [SetEntry] = []
    var incomingCommands: [WatchCommand] = []
    var incomingSessions: [Session] = []
    var receivedCatalogue: Catalogue?
    /// The phone's current weights session, as last published in the application context.
    var weightsLink: WeightsLink?
    var isReachable = false
    var isActivated = false

    @ObservationIgnored var onSet: ((SetEntry, WeightsLink?) -> Void)?
    @ObservationIgnored var onCommand: ((WatchCommand, WeightsLink?) -> Void)?
    @ObservationIgnored var onSession: ((Session) -> Void)?
    @ObservationIgnored var onWeightsLink: ((WeightsLink) -> Void)?
    @ObservationIgnored private var lastContext: [String: Data] = [:]
    @ObservationIgnored private var activationRequested = false

    func activate() {
        guard WCSession.isSupported(), !activationRequested else { return }
        activationRequested = true
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    private var session: WCSession? {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return nil }
        return WCSession.default
    }

    // MARK: Phone -> watch

    #if os(iOS)
    /// Live HUD: sent as a message when the watch is reachable, otherwise kept as the latest context.
    func send(snapshot: HUDSnapshot) {
        latestSnapshot = snapshot
        guard let session, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONCoding.encode(snapshot) else { return }
        if session.isReachable {
            session.sendMessage([Key.snapshot: data], replyHandler: nil, errorHandler: nil)
        } else {
            updateContext(Key.snapshot, data)
        }
    }

    /// Hands the catalogue to the watch so it can log standalone. Large catalogues go as a file.
    func sendCatalogue(_ catalogue: Catalogue) {
        guard let session, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONCoding.encode(catalogue) else { return }
        if data.count < 48_000 {
            updateContext(Key.catalogue, data)
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalogue.json")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            session.transferFile(url, metadata: ["kind": Key.catalogue])
        }
    }

    /// Publishes the phone's weights session state so the watch joins (or leaves) the same session id.
    func send(weights link: WeightsLink) {
        guard let data = try? JSONCoding.encode(link) else { return }
        updateContext(Key.weights, data)
    }
    #endif

    // MARK: Watch -> phone

    #if os(watchOS)
    /// Queued reliably (transferUserInfo) so sets logged out of range still arrive.
    func send(set entry: SetEntry, link: WeightsLink) {
        guard let session, let data = try? JSONCoding.encode(entry),
              let linkData = try? JSONCoding.encode(link) else { return }
        session.transferUserInfo([Key.set: data, Key.weights: linkData])
    }

    /// Queued (transferUserInfo) rather than messaged: a stop must not be lost while out of range, and
    /// FIFO delivery keeps it ordered after the sets it closes.
    func send(command: WatchCommand, link: WeightsLink? = nil) {
        guard let session, let data = try? JSONCoding.encode(command) else { return }
        var payload = [Key.command: data]
        if let link, let linkData = try? JSONCoding.encode(link) { payload[Key.weights] = linkData }
        session.transferUserInfo(payload)
    }

    /// A whole weights session from the watch; the phone merges it by session id and set id.
    func send(session recorded: Session) {
        guard let session, let data = try? JSONCoding.encode(recorded) else { return }
        session.transferUserInfo([Key.session: data])
    }
    #endif

    /// Kept even before activation so the latest state goes out once the session activates.
    private func updateContext(_ key: String, _ data: Data) {
        lastContext[key] = data
        guard let session else { return }
        try? session.updateApplicationContext(lastContext)
    }

    // MARK: Inbound

    private func receive(_ payload: [String: Data]) {
        if let d = payload[Key.snapshot], let s = try? JSONCoding.decode(HUDSnapshot.self, from: d) {
            latestSnapshot = s
        }
        let link = payload[Key.weights].flatMap { try? JSONCoding.decode(WeightsLink.self, from: $0) }
        let isTag = payload[Key.set] != nil || payload[Key.command] != nil
        if let d = payload[Key.set], let e = try? JSONCoding.decode(SetEntry.self, from: d) {
            incomingSets.append(e)
            onSet?(e, link)
        }
        if let d = payload[Key.command], let c = try? JSONCoding.decode(WatchCommand.self, from: d) {
            incomingCommands.append(c)
            onCommand?(c, link)
        }
        if !isTag, let link {
            weightsLink = link
            onWeightsLink?(link)
        }
        if let d = payload[Key.session], let s = try? JSONCoding.decode(Session.self, from: d) {
            incomingSessions.append(s)
            onSession?(s)
        }
        if let d = payload[Key.catalogue], let c = try? JSONCoding.decode(Catalogue.self, from: d) {
            receivedCatalogue = c
            #if os(watchOS)
            StoreController.shared.applyCatalogue(c)
            #endif
        }
    }

    private nonisolated static func dataOnly(_ dict: [String: Any]) -> [String: Data] {
        dict.compactMapValues { $0 as? Data }
    }

    // MARK: WCSessionDelegate (called on a background queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let activated = activationState == .activated
        let reachable = session.isReachable
        let context = Self.dataOnly(session.receivedApplicationContext)
        Task { @MainActor in
            self.isActivated = activated
            self.isReachable = reachable
            if activated, !self.lastContext.isEmpty {
                try? self.session?.updateApplicationContext(self.lastContext)
            }
            self.receive(context)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = Self.dataOnly(message)
        Task { @MainActor in self.receive(payload) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = Self.dataOnly(applicationContext)
        Task { @MainActor in self.receive(payload) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = Self.dataOnly(userInfo)
        Task { @MainActor in self.receive(payload) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so read it now.
        guard (file.metadata?["kind"] as? String) == Key.catalogue,
              let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.receive([Key.catalogue: data]) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
