import Foundation

public enum Statement {
    public struct Line: Identifiable, Equatable, Sendable {
        public let name: String, amount: Decimal
        public var id: String { name }
    }

    /// One month, ready for the statement screen and for the shared text.
    public struct Summary {
        public var month = "", previousMonth = ""
        public var spent: Decimal = 0, previousSpent: Decimal = 0
        public var moneyIn: Decimal = 0, moneyOut: Decimal = 0
        public var byKind: [(kind: Kind, total: Decimal)] = []
        public var categories: [Line] = [], methods: [Line] = [], trips: [Line] = []
        /// Balance at month end: positive means they owe you.
        public var people: [Line] = []
        public var needsInput: [Entry] = [], entries: [Entry] = []
        /// Spending so far by day of the month (day 1 first), this month up to today and the whole previous month.
        public var pace: [Decimal] = [], previousPace: [Decimal] = []
        /// Spending in each of the last 6 months, oldest first ("Jun" … this month).
        public var history: [Line] = []
        public var recurring: [Recurring.Item] = []

        /// "You spent ₹18,450 in November, ₹2,100 less than October."
        public var sentence: String {
            guard !entries.isEmpty else { return "No entries in \(month)." }
            let base = "You spent \(money(spent)) in \(month)"
            guard previousSpent > 0, previousSpent != spent else { return base + "." }
            let diff = spent - previousSpent
            return base + ", \(money(abs(diff))) \(diff > 0 ? "more" : "less") than \(previousMonth)."
        }
    }

    public static func summary(for month: Date, entries: [Entry], calendar: Calendar = .current) -> Summary {
        var s = Summary()
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return s }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.calendar = calendar; fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "MMMM"
        s.month = fmt.string(from: month)
        func sum(_ list: [Entry]) -> Decimal { list.compactMap(\.amount).reduce(0, +) }
        func lines(_ list: [Entry], _ key: (Entry) -> String) -> [Line] {
            var sums: [String: Decimal] = [:]
            for e in list { if let a = e.amount { sums[key(e), default: 0] += a } }
            return sums.map { Line(name: $0.key, amount: $0.value) }
                .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
        }

        s.entries = entries.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        let expenses = s.entries.filter { $0.kind == .expense }
        s.spent = sum(expenses)
        if let prev = calendar.date(byAdding: .month, value: -1, to: month),
           let prevInterval = calendar.dateInterval(of: .month, for: prev) {
            s.previousMonth = fmt.string(from: prev)
            s.previousSpent = sum(entries.filter { $0.kind == .expense && prevInterval.contains($0.date) })
        }
        s.byKind = Kind.allCases.map { k in (k, sum(s.entries.filter { $0.kind == k })) }.filter { $0.total != 0 }
        s.moneyIn = sum(s.entries.filter(\.kind.isIn)); s.moneyOut = sum(s.entries.filter { !$0.kind.isIn })
        s.categories = lines(expenses) { $0.category }
        s.methods = lines(s.entries.filter { !$0.kind.isIn }) { $0.method.isEmpty ? "Not specified" : $0.method }
        s.trips = Set(s.entries.compactMap(\.trip)).sorted().map { Line(name: $0, amount: entries.spent(onTrip: $0)) }

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
        s.people = balance.filter { $0.value != 0 }.map { Line(name: $0.key, amount: $0.value) }.sorted { $0.name < $1.name }
        s.needsInput = s.entries.filter(\.needsInput)

        func running(_ interval: DateInterval, upTo day: Int?) -> [Decimal] {
            let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
            var daily = [Decimal](repeating: 0, count: min(day ?? days, days))
            for e in entries where e.kind == .expense && interval.contains(e.date) {
                let d = calendar.component(.day, from: e.date) - 1
                if d < daily.count { daily[d] += e.amount ?? 0 }
            }
            var total: Decimal = 0
            return daily.map { total += $0; return total }
        }
        let now = Date()
        s.pace = running(interval, upTo: interval.contains(now) ? calendar.component(.day, from: now) : nil)
        if let prev = calendar.date(byAdding: .month, value: -1, to: month), let p = calendar.dateInterval(of: .month, for: prev) {
            s.previousPace = running(p, upTo: nil)
        }
        fmt.dateFormat = "MMM"
        s.history = (-5...0).compactMap { offset in
            guard let m = calendar.date(byAdding: .month, value: offset, to: month),
                  let i = calendar.dateInterval(of: .month, for: m) else { return nil }
            return Line(name: fmt.string(from: m), amount: sum(entries.filter { $0.kind == .expense && i.contains($0.date) }))
        }
        s.recurring = Recurring.find(in: entries.filter { $0.date < interval.end })
        return s
    }

    /// The parts of a statement you can choose to share.
    public enum Part: String, CaseIterable, Identifiable, Sendable {
        case summary = "Summary", categories = "By category", methods = "Paid with", trips = "Trips",
             people = "People", recurring = "Recurring", needsInput = "Needs input", entries = "Entries"
        public var id: String { rawValue }
    }

    /// Plain-English monthly statement, ready to copy or share, with only the chosen parts.
    public static func text(for month: Date, entries: [Entry], parts: Set<Part> = Set(Part.allCases),
                            calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.calendar = calendar; fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "MMMM yyyy"
        var lines = ["STATEMENT: \(fmt.string(from: month))"]
        let s = summary(for: month, entries: entries, calendar: calendar)
        guard !s.entries.isEmpty else { return (lines + ["", "No entries this month."]).joined(separator: "\n") }

        func pad(_ s: String, _ n: Int = 12) -> String { s.count >= n ? s + " " : s.padding(toLength: n, withPad: " ", startingAt: 0) }
        func section(_ part: Part, _ title: String, _ list: [Line]) {
            guard parts.contains(part), !list.isEmpty else { return }
            lines += ["", title] + list.map { "  " + pad($0.name, 16) + money($0.amount) }
        }

        if parts.contains(.summary) {
            lines += ["", s.sentence, ""] + s.byKind.map { pad($0.kind.label) + money($0.total) }
            lines += ["", pad("Money in") + money(s.moneyIn), pad("Money out") + money(s.moneyOut),
                      pad("Net") + money(s.moneyIn - s.moneyOut)]
        }
        section(.categories, "SPENDING BY CATEGORY", s.categories)
        section(.methods, "MONEY OUT BY PAYMENT METHOD", s.methods)
        section(.trips, "TRIPS (your spending)", s.trips)
        if parts.contains(.people), !s.people.isEmpty {
            lines += ["", "PEOPLE (balance at month end)"]
            for p in s.people {
                lines.append(p.amount > 0 ? "  \(p.name) owes you \(money(p.amount))" : "  You owe \(p.name) \(money(-p.amount))")
            }
        }
        fmt.dateFormat = "dd MMM"
        if parts.contains(.recurring), !s.recurring.isEmpty {
            lines += ["", "RECURRING"]
            for r in s.recurring { lines.append("  " + pad(r.name, 16) + pad(money(r.amount), 11) + "next ~" + fmt.string(from: r.next)) }
        }
        if parts.contains(.needsInput), !s.needsInput.isEmpty {
            lines += ["", "NEEDS INPUT (\(s.needsInput.count))"]
            for e in s.needsInput { lines.append("  \"\(e.displayText)\": \(e.question)") }
        }
        guard parts.contains(.entries) else { return lines.joined(separator: "\n") }
        lines += ["", "ENTRIES"]
        for e in s.entries {
            let details = [e.category, e.method, e.person].filter { !$0.isEmpty }.joined(separator: ", ")
            lines.append("  \(fmt.string(from: e.date))  \(pad(e.kind.label, 10))\(pad(e.amount.map(money) ?? "?", 11))\(details)")
        }
        return lines.joined(separator: "\n")
    }
}
