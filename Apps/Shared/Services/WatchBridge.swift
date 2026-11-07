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
    }

    var latestSnapshot: HUDSnapshot?
    var incomingSets: [SetEntry] = []
    var incomingCommands: [WatchCommand] = []
    var incomingSessions: [Session] = []
    var receivedCatalogue: Catalogue?
    var isReachable = false
    var isActivated = false

    @ObservationIgnored var onSet: ((SetEntry) -> Void)?
    @ObservationIgnored var onCommand: ((WatchCommand) -> Void)?
    @ObservationIgnored var onSession: ((Session) -> Void)?
    @ObservationIgnored private var lastContext: [String: Data] = [:]

    func activate() {
        guard WCSession.isSupported() else { return }
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
    #endif

    // MARK: Watch -> phone

    #if os(watchOS)
    /// Queued reliably (transferUserInfo) so sets logged out of range still arrive.
    func send(set entry: SetEntry) {
        guard let session, let data = try? JSONCoding.encode(entry) else { return }
        session.transferUserInfo([Key.set: data])
    }

    func send(command: WatchCommand) {
        guard let session, let data = try? JSONCoding.encode(command) else { return }
        if session.isReachable {
            session.sendMessage([Key.command: data], replyHandler: nil) { _ in
                Task { @MainActor in WatchBridge.shared.session?.transferUserInfo([Key.command: data]) }
            }
        } else {
            session.transferUserInfo([Key.command: data])
        }
    }

    /// A whole session recorded standalone on the watch.
    func send(session recorded: Session) {
        guard let session, let data = try? JSONCoding.encode(recorded) else { return }
        session.transferUserInfo([Key.session: data])
    }
    #endif

    private func updateContext(_ key: String, _ data: Data) {
        guard let session else { return }
        lastContext[key] = data
        try? session.updateApplicationContext(lastContext)
    }

    // MARK: Inbound

    private func receive(_ payload: [String: Data]) {
        if let d = payload[Key.snapshot], let s = try? JSONCoding.decode(HUDSnapshot.self, from: d) {
            latestSnapshot = s
        }
        if let d = payload[Key.set], let e = try? JSONCoding.decode(SetEntry.self, from: d) {
            incomingSets.append(e)
            onSet?(e)
        }
        if let d = payload[Key.command], let c = try? JSONCoding.decode(WatchCommand.self, from: d) {
            incomingCommands.append(c)
            onCommand?(c)
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
