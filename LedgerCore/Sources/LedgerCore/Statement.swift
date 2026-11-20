import Foundation

public enum Statement {
    /// Plain-English monthly statement, ready to copy or share.
    public static func text(for month: Date, entries: [Entry], calendar: Calendar = .current) -> String {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.calendar = calendar; fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "MMMM yyyy"
        var lines = ["STATEMENT: \(fmt.string(from: month))"]

        let inMonth = entries.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        guard !inMonth.isEmpty else { return (lines + ["", "No entries this month."]).joined(separator: "\n") }

        func pad(_ s: String, _ n: Int = 12) -> String { s.count >= n ? s + " " : s.padding(toLength: n, withPad: " ", startingAt: 0) }
        func sum(_ list: [Entry]) -> Decimal { list.compactMap(\.amount).reduce(0, +) }
        func breakdown(_ title: String, _ list: [Entry], _ key: (Entry) -> String) {
            var sums: [String: Decimal] = [:]
            for e in list { if let a = e.amount { sums[key(e), default: 0] += a } }
            guard !sums.isEmpty else { return }
            lines += ["", title]
            for (k, v) in sums.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
                lines.append("  " + pad(k, 16) + rupees(v))
            }
        }

        lines.append("")
        for kind in Kind.allCases {
            let total = sum(inMonth.filter { $0.kind == kind })
            if total != 0 { lines.append(pad(kind.label) + rupees(total)) }
        }
        let moneyIn = sum(inMonth.filter(\.kind.isIn)), moneyOut = sum(inMonth.filter { !$0.kind.isIn })
        lines += ["", pad("Money in") + rupees(moneyIn), pad("Money out") + rupees(moneyOut),
                  pad("Net") + rupees(moneyIn - moneyOut)]

        breakdown("SPENDING BY CATEGORY", inMonth.filter { $0.kind == .expense }) { $0.category }
        breakdown("MONEY OUT BY PAYMENT METHOD", inMonth.filter { !$0.kind.isIn }) { $0.method.isEmpty ? "Not specified" : $0.method }

        // Balances run across all history up to the end of this month.
        var balance: [String: Decimal] = [:]
        for e in entries where e.date < interval.end && !e.person.isEmpty {
            guard let a = e.amount else { continue }
            switch e.kind {
            case .lent, .repaidByMe: balance[e.person, default: 0] += a
            case .borrowed, .repaidToMe: balance[e.person, default: 0] -= a
            default: break
            }
        }
        let people = balance.filter { $0.value != 0 }.sorted { $0.key < $1.key }
        if !people.isEmpty {
            lines += ["", "PEOPLE (balance at month end)"]
            for (name, v) in people {
                lines.append(v > 0 ? "  \(name) owes you \(rupees(v))" : "  You owe \(name) \(rupees(-v))")
            }
        }

        let open = inMonth.filter(\.needsInput)
        if !open.isEmpty {
            lines += ["", "NEEDS INPUT (\(open.count))"]
            for e in open { lines.append("  \"\(e.displayText)\": \(e.question)") }
        }

        fmt.dateFormat = "dd MMM"
        lines += ["", "ENTRIES"]
        for e in inMonth {
            let details = [e.category, e.method, e.person].filter { !$0.isEmpty }.joined(separator: ", ")
            lines.append("  \(fmt.string(from: e.date))  \(pad(e.kind.label, 10))\(pad(e.amount.map(rupees) ?? "?", 11))\(details)")
        }
        return lines.joined(separator: "\n")
    }
}
