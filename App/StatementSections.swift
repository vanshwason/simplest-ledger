import SwiftUI
import Charts
import LedgerCore

/// The month at a glance: one sentence and two numbers on top, then bars per category, people, and the entries.
struct StatementSections: View {
    let s: Statement.Summary

    var body: some View {
        Section {
            Text(s.sentence).font(.title3)
            if !s.entries.isEmpty {
                HStack(spacing: 10) {
                    tile("Spent", s.spent, .primary)
                    tile("Money in", s.moneyIn, .green)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
            }
        }
        if !s.needsInput.isEmpty {
            Section {
                Label("\(s.needsInput.count) \(s.needsInput.count == 1 ? "entry needs" : "entries need") input",
                      systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        if s.pace.count > 1 || s.previousPace.count > 1 {
            Section("Spending pace") { pace.frame(height: 160).padding(.vertical, 6) }
        }
        if s.history.contains(where: { $0.amount > 0 }) {
            Section("Last 6 months") { history.frame(height: 140).padding(.vertical, 6) }
        }
        bars("By category", s.categories)
        bars("Paid with", s.methods)
        if !s.recurring.isEmpty {
            Section {
                ForEach(s.recurring) { r in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.name)
                            Text("Next around " + r.next.formatted(.dateTime.day().month(.abbreviated).locale(english)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(r.amount)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: { Text("Recurring") } footer: { Text("Paid about once a month, the last 3 times.") }
        }
        if !s.trips.isEmpty {
            Section("Trips") { ForEach(s.trips) { row($0.name, $0.amount) } }
        }
        if !s.people.isEmpty {
            Section("People") {
                ForEach(s.people) { p in
                    HStack {
                        Text(p.amount > 0 ? "\(p.name) owes you" : "You owe \(p.name)")
                        Spacer()
                        Text(money(abs(p.amount))).monospacedDigit().foregroundStyle(p.amount > 0 ? .green : .orange)
                    }
                }
            }
        }
        if !s.entries.isEmpty {
            Section {
                DisclosureGroup("Entries (\(s.entries.count))") {
                    ForEach(s.entries) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.category.isEmpty ? e.kind.label : e.category)
                                Text(e.date.formatted(.dateTime.day().month(.abbreviated).locale(english)) + " · " + e.kind.label)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.amount.map(money) ?? "?").monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// Running total by day: this month against last month, so you can see if you're ahead of your usual pace.
    private var pace: some View {
        Chart {
            ForEach(Array(s.previousPace.enumerated()), id: \.offset) { item in
                LineMark(x: .value("Day", item.offset + 1), y: .value("Spent", double(item.element)),
                         series: .value("Month", s.previousMonth))
                    .foregroundStyle(by: .value("Month", s.previousMonth))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            ForEach(Array(s.pace.enumerated()), id: \.offset) { item in
                LineMark(x: .value("Day", item.offset + 1), y: .value("Spent", double(item.element)), series: .value("Month", s.month))
                    .foregroundStyle(by: .value("Month", s.month))
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartForegroundStyleScale([s.month: accent, s.previousMonth: Color.secondary])
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text(short(v.as(Double.self) ?? 0)) } } }
        .chartXAxisLabel("Day of the month")
    }

    private var history: some View {
        Chart(s.history) { line in
            BarMark(x: .value("Month", line.name), y: .value("Spent", double(line.amount)))
                .foregroundStyle(line.name == s.history.last?.name ? accent : Color.secondary.opacity(0.5))
                .cornerRadius(4)
        }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text(short(v.as(Double.self) ?? 0)) } } }
    }

    private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

    /// Axis labels: "12k" rather than "₹12,000".
    private func short(_ v: Double) -> String {
        v >= 1000 ? (v / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k" : v.formatted(.number.precision(.fractionLength(0)))
    }

    private func tile(_ label: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(money(value)).font(.title2.bold()).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func bars(_ title: String, _ lines: [Statement.Line]) -> some View {
        if !lines.isEmpty {
            let top = lines.map(\.amount).max() ?? 1
            Section(title) {
                ForEach(lines) { line in
                    VStack(spacing: 6) {
                        row(line.name, line.amount)
                        ProgressView(value: NSDecimalNumber(decimal: line.amount / max(top, 1)).doubleValue)
                            .tint(accent).accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func row(_ name: String, _ amount: Decimal) -> some View {
        HStack { Text(name); Spacer(); Text(money(amount)).monospacedDigit() }
    }
}

/// Share a month: pick the parts and the format. The choices are remembered for next time.
struct ShareStatementSheet: View {
    let month: Date
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shareAsCSV") private var asCSV = false
    /// Parts you turned off, so new parts added later start switched on.
    @AppStorage("shareHiddenParts") private var hidden = ""

    private var parts: Set<Statement.Part> {
        let off = Set(hidden.split(separator: ",").map(String.init))
        return Set(Statement.Part.allCases.filter { !off.contains($0.rawValue) })
    }
    private var monthName: String { month.formatted(.dateTime.month(.wide).year().locale(english)) }
    private var monthEntries: [Entry] { Statement.summary(for: month, entries: store.entries).entries }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Format", selection: $asCSV) {
                    Text("Text").tag(false)
                    Text("CSV").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if asCSV {
                    Section {
                        Text("\(monthEntries.count) entries from \(monthName), one row each. Opens in Numbers, Excel or Google Sheets.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Include") {
                        ForEach(Statement.Part.allCases) { part in
                            Toggle(part.rawValue, isOn: Binding(get: { parts.contains(part) }, set: { set(part, on: $0) }))
                        }
                    }
                }
            }
            .navigationTitle("Share \(monthName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if asCSV {
                        let name = "ledger-" + month.formatted(.iso8601.year().month()) + ".csv"
                        ShareLink(item: CSVExport(entries: monthEntries, name: name), preview: SharePreview(name)) { Text("Share") }
                    } else {
                        ShareLink(item: Statement.text(for: month, entries: store.entries, parts: parts)) { Text("Share") }
                            .disabled(parts.isEmpty)
                    }
                }
            }
        }
    }

    private func set(_ part: Statement.Part, on: Bool) {
        var off = Set(hidden.split(separator: ",").map(String.init))
        if on { off.remove(part.rawValue) } else { off.insert(part.rawValue) }
        hidden = off.sorted().joined(separator: ",")
    }
}
