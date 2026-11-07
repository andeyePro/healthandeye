import SwiftUI
import HealthAndICore

struct OptionalTextField: View {
    let title: String
    @Binding var text: String?

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ))
            .multilineTextAlignment(.trailing)
        }
    }
}

struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        LabeledContent(title) {
            TextField("–", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        LabeledContent(title) {
            TextField("–", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Editor for a free-form `[String: Double]` map (limits, nutrients).
struct NumberMapEditor: View {
    let title: String
    @Binding var map: [String: Double]
    @State private var newKey = ""

    var body: some View {
        Section(title) {
            ForEach(map.keys.sorted(), id: \.self) { key in
                LabeledContent(key) {
                    TextField(key, value: Binding(
                        get: { map[key] ?? 0 },
                        set: { map[key] = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            }
            .onDelete { idx in
                let keys = map.keys.sorted()
                for i in idx { map[keys[i]] = nil }
            }
            HStack {
                TextField("new key (snake_case)", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    let k = newKey.trimmingCharacters(in: .whitespaces)
                    guard !k.isEmpty else { return }
                    map[k] = map[k] ?? 0
                    newKey = ""
                }
            }
        }
    }
}

/// Editor for a free-form list of strings (quirks, tags).
struct StringListEditor: View {
    let title: String
    @Binding var items: [String]
    @State private var newItem = ""

    var body: some View {
        Section(title) {
            ForEach(items.indices, id: \.self) { i in
                TextField(title, text: Binding(
                    get: { i < items.count ? items[i] : "" },
                    set: { if i < items.count { items[i] = $0 } }
                ), axis: .vertical)
            }
            .onDelete { items.remove(atOffsets: $0) }
            HStack {
                TextField("add…", text: $newItem)
                Button("Add") {
                    let s = newItem.trimmingCharacters(in: .whitespaces)
                    guard !s.isEmpty else { return }
                    items.append(s)
                    newItem = ""
                }
            }
        }
    }
}

enum Slug {
    static func make(prefix: String, name: String, existing: [String]) -> String {
        let base = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        var id = "\(prefix)-\(base.isEmpty ? "new" : base)"
        var n = 2
        let root = id
        while existing.contains(id) {
            id = "\(root)-\(n)"
            n += 1
        }
        return id
    }
}

enum Fmt {
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func number(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func summaryLine(_ s: Session) -> String {
        var parts: [String] = []
        if let d = s.summary["distance_m"] { parts.append("\(Int(d)) m") }
        if let hr = s.summary["avg_hr"] { parts.append("avg HR \(Int(hr))") }
        if let z = s.summary["minutes_in_zone"] { parts.append("\(number(z)) min in zone") }
        if !s.sets.isEmpty { parts.append("\(s.sets.count) sets") }
        if let end = s.end { parts.append(duration(end.timeIntervalSince(s.start))) }
        return parts.joined(separator: " · ")
    }
}
