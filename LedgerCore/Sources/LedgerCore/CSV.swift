import Foundation

/// Backup format. Opens in Google Sheets, Numbers and Excel.
public enum CSV {
    public struct BadRow: LocalizedError {
        public let line: Int, problem: String
        public var errorDescription: String? { "CSV line \(line): \(problem). Nothing was imported." }
    }

    static let header = ["id", "date", "amount", "kind", "category", "method", "person", "note", "question", "raw",
                         "split_total", "split_of", "trip", "source"]

    public static func encode(_ entries: [Entry]) -> String {
        let iso = ISO8601DateFormatter()
        var out = header.joined(separator: ",") + "\n"
        for e in entries {
            let text = [e.category, e.method, e.person, e.note, e.question, e.raw].map(defuse)
            let fields = [e.id.uuidString, iso.string(from: e.date), e.amount.map { "\($0)" } ?? "", e.kind.rawValue] + text
                + [e.splitTotal.map { "\($0)" } ?? "", e.splitOf?.uuidString ?? "", defuse(e.trip ?? ""), defuse(e.source ?? "")]
            out += fields.map(quote).joined(separator: ",") + "\n"
        }
        return out
    }

    public static func decode(_ text: String) throws -> [Entry] {
        let all = rows(text).filter { $0 != [""] }
        guard let head = all.first else { return [] }
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))
        let index = Dictionary(head.enumerated().map { ($1.trimmingCharacters(in: trim).lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })
        let iso = ISO8601DateFormatter()
        return try all.dropFirst().enumerated().map { n, row in
            func value(_ key: String) -> String { restore(index[key].flatMap { $0 < row.count ? row[$0] : nil } ?? "") }
            let line = n + 2
            guard let date = iso.date(from: value("date")) else { throw BadRow(line: line, problem: "bad date '\(value("date"))'") }
            guard let kind = Kind(rawValue: value("kind")) else { throw BadRow(line: line, problem: "bad kind '\(value("kind"))'") }
            let amountText = value("amount")
            let amount = amountText.isEmpty ? nil : Decimal(string: amountText)
            if !amountText.isEmpty && amount == nil { throw BadRow(line: line, problem: "bad amount '\(amountText)'") }
            var entry = Entry(id: UUID(uuidString: value("id")) ?? UUID(), date: date, raw: value("raw"), amount: amount,
                              kind: kind, category: value("category"), method: value("method"), person: value("person"),
                              note: value("note"), question: value("question"))
            entry.splitTotal = Decimal(string: value("split_total"))
            entry.splitOf = UUID(uuidString: value("split_of"))
            entry.trip = value("trip").isEmpty ? nil : value("trip")
            entry.source = value("source").isEmpty ? nil : value("source")
            return entry
        }
    }

    // An SMS like "=HYPERLINK(...)" would run as a formula when the backup is opened in Excel or Sheets.
    static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]
    static func defuse(_ s: String) -> String { s.first.map(formulaStarts.contains) == true ? "'" + s : s }
    static func restore(_ s: String) -> String {
        s.first == "'" && s.dropFirst().first.map(formulaStarts.contains) == true ? String(s.dropFirst()) : s
    }

    static func quote(_ s: String) -> String {
        s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
