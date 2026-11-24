import SwiftUI
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
        bars("By category", s.categories)
        bars("Paid with", s.methods)
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
