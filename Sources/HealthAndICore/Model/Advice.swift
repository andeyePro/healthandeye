import Foundation

public struct AdviceNote: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// File stem of `advice/<id>.md`.
    public var id: String
    public var title: String
    public var body: String
    public var date: Date
    public var status: AdviceStatus

    public init(id: String, title: String? = nil, body: String = "", date: Date = Date(), status: AdviceStatus = .open) {
        self.id = id
        self.title = title ?? id
        self.body = body
        self.date = date
        self.status = status
    }

    enum CodingKeys: String, CodingKey { case id, title, body, date, status }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.val(.title, id)
        body = try c.val(.body, "")
        date = try c.val(.date, Date(timeIntervalSince1970: 0))
        status = try c.val(.status, .open)
    }
}
