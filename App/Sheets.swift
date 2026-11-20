import SwiftUI
import LedgerCore

// Tap-to-pick building blocks: icons and chips instead of free-text fields.

let paymentMethods = ["UPI", "Cash", "Credit Card", "Debit Card", "Card", "Bank Transfer"]

/// Emoji tiles for every category; tap one to choose it.
struct CategoryGrid: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
            ForEach(RuleParser.categoryNames, id: \.self) { name in
                let on = selection == name
                Button { withAnimation(.snappy) { selection = name } } label: {
                    VStack(spacing: 4) {
                        Text(RuleParser.emoji(for: name)).font(.title2)
                        Text(name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(on ? AnyShapeStyle(accent.opacity(0.18)) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 12))
                    .overlay { if on { RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 2) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One-of-many chips (payment method, person). Tapping the chosen one clears it.
struct Chips: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let on = selection == option
                    Button(on ? "✓ \(option)" : option) { withAnimation(.snappy) { selection = on ? "" : option } }
                        .buttonStyle(.bordered)
                        .tint(on ? accent : .secondary)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Many-of-many chips (who shared a bill).
struct MultiChips: View {
    let options: [String]
    @Binding var selected: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let on = selected.contains(option)
                    Button(on ? "✓ \(option)" : option) {
                        withAnimation(.snappy) { if on { selected.removeAll { $0 == option } } else { selected.append(option) } }
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? accent : .secondary)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Everything you can type, one tappable example each. Tapping fills the text box.
struct HelpSheet: View {
    let use: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    static let sections: [(title: String, examples: [String])] = [
        ("Add money", ["1500 snacks via UPI", "uber 220 yesterday", "salary 50000 credited", "ordered pizza from zomato 450"]),
        ("Lend and borrow", ["lent 2000 to Rahul", "borrowed 1000 from Amit", "got 2000 back from Rahul"]),
        ("Split a bill", ["split the outing with 3 people", "split wifi, he paid 700", "roommate ne wifi ka aadha de diya",
                          "split 1200 dinner with Rahul and Amit"]),
        ("Trips", ["going on goa trip", "trip over"]),
        ("Delete", ["delete the latest entry", "delete today's entries", "all entries were test entries, please delete"]),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.examples, id: \.self) { example in
                            Button(example) { use(example) }.tint(.primary)
                        }
                    }
                }
                Section { Text("Several entries at once: put one per line. Deletes and splits always ask before changing anything.") }
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("What Can I Type?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Settings for reading bank SMS. iOS gives apps no SMS access, so this walks you through the one-time
/// Shortcuts automation that hands matching messages to the app, and lets you test a message first.
struct SMSSetupSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var sample = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        if let last = store.lastMessageAt {
                            Text("Working · last SMS added \(last.formatted(.relative(presentation: .named)))")
                        } else {
                            Text("Not set up yet")
                        }
                    } icon: {
                        Image(systemName: store.lastMessageAt == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .foregroundStyle(store.lastMessageAt == nil ? Color.secondary : accent)
                    }
                } footer: {
                    Text("iPhone doesn't let any app read your messages. A one-time Shortcuts automation sends bank SMS to Simplest Ledger instead, in the background.")
                }

                // One space matches every message: any bank, any currency. The app drops what isn't a transaction.
                // A ready-made shortcut can't be shared: its action is tied to each person's sideloaded app ID.
                Section {
                    step(1, "Shortcuts → + → Automation → Message.")
                    step(2, "Change Sender to Message contains. Type one space.")
                    screenshot("ShortcutTrigger")
                    step(3, "Search Ledger, add Add to Ledger. Message: the blue Message. Show When Run off.")
                    screenshot("ShortcutAction")
                    step(4, "Tap › next to where. Automation on, Confirm Before Run off.")
                    screenshot("ShortcutRun")
                    Button { openURL(URL(string: "shortcuts://")!) } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.glassProminent).tint(accent)
                } header: { Text("One-time setup, about a minute") } footer: {
                    Text("Chats and OTPs are ignored automatically. On iOS 26: Automation tab → + → Message, then Run Immediately.")
                }

                Section {
                    TextField("Paste a bank SMS", text: $sample, axis: .vertical).lineLimit(2...5)
                    if !sample.trimmingCharacters(in: .whitespaces).isEmpty {
                        if let reason = MessageFilter.ignoreReason(sample) {
                            Label("Would be skipped: looks like \(reason)", systemImage: "nosign").foregroundStyle(.secondary)
                        } else {
                            EntryRow(entry: RuleParser.parse(sample)) // preview only, nothing is saved
                        }
                    }
                } header: { Text("Try a message") } footer: {
                    Text("Shows what would be saved. Nothing is added from here.")
                }
            }
            .navigationTitle("Read Bank SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func screenshot(_ name: String) -> some View {
        Image(name).resizable().scaledToFit().clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true) // steps say it in words
    }

    private func step(_ n: Int, _ text: String) -> some View {
        Label { Text(text) } icon: { Text("\(n)").font(.footnote.bold()).frame(width: 22, height: 22).background(.fill.tertiary, in: .circle) }
    }
}

/// Edit an entry by tapping: amount, a category tile, a person chip, a payment chip. Extras hide under "More".
struct EditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entry: Entry
    @State private var amountText: String
    @State private var newPerson = ""
    @FocusState private var amountFocused: Bool

    init(entry: Entry) {
        _entry = State(initialValue: entry)
        _amountText = State(initialValue: entry.amount.map { "\($0)" } ?? "")
    }

    private var draft: Entry {
        var e = entry
        e.amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
        let typed = newPerson.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { e.person = typed.capitalized }
        return e
    }

    /// Live: the question disappears the moment you tap the answer.
    private var question: String { draft.missingInfo() }

    var body: some View {
        NavigationStack {
            Form {
                if !question.isEmpty {
                    Section {
                        Label { Text(question).font(.headline) } icon: {
                            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                        }
                    } footer: { Text("Tap an answer below.") }
                    .transition(.opacity)
                }
                Section {
                    HStack(spacing: 4) {
                        Text(Currency.current.symbol).font(.largeTitle.bold()).foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.largeTitle.bold()).keyboardType(.decimalPad).focused($amountFocused)
                            .accessibilityLabel("Amount")
                    }
                    Picker("Type", selection: $entry.kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if let total = entry.splitTotal { LabeledContent("Your share of", value: money(total)) }
                }
                Section("Category") { CategoryGrid(selection: $entry.category) }
                if entry.kind.needsPerson || !entry.person.isEmpty {
                    Section("Who") {
                        if !store.people.isEmpty { Chips(options: store.people, selection: $entry.person) }
                        TextField("Someone new", text: $newPerson).textInputAutocapitalization(.words)
                    }
                }
                Section("Paid with") { Chips(options: paymentMethods, selection: $entry.method) }
                Section {
                    DisclosureGroup("More") {
                        DatePicker("Date", selection: $entry.date, displayedComponents: .date)
                        TextField("Note", text: $entry.note)
                        LabeledContent("You typed", value: entry.raw)
                    }
                }
            }
            .animation(.snappy, value: question)
            .onAppear { if question == "How much was it?" { amountFocused = true } }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        var e = draft
        e.question = e.missingInfo(checkCategory: false) // a deliberate "Other" is fine once you've saved
        withAnimation(.snappy) { store.update(e) }
        dismiss()
    }
}

/// Confirms a split before anything changes. One choice up top, then only the fields that choice needs.
struct SplitSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: Entry
    enum Mode: Hashable { case equal, paidAmount }
    @State private var mode: Mode
    @State private var request: SplitRequest
    @State private var picked: [String]
    @State private var newName = ""
    @State private var paidText: String

    init(pending: PendingSplit) {
        target = pending.target
        _mode = State(initialValue: pending.request.contributed == nil ? .equal : .paidAmount)
        _request = State(initialValue: pending.request)
        _picked = State(initialValue: pending.request.names)
        _paidText = State(initialValue: pending.request.contributed.map { "\($0)" } ?? "")
    }

    private var current: SplitRequest {
        var r = request
        r.names = picked
        r.others = max(r.others, picked.count, 1)
        if mode == .paidAmount {
            r.contributed = Decimal(string: paidText.replacingOccurrences(of: ",", with: "")) ?? 0
            r.alreadyPaid = true
        } else {
            r.contributed = nil
        }
        return r
    }

    var body: some View {
        let result = Split.apply(current, to: target)
        NavigationStack {
            Form {
                Section { EntryRow(entry: target) }
                Section {
                    Picker("How", selection: $mode.animation(.snappy)) {
                        Text("Split equally").tag(Mode.equal)
                        Text("They paid \(Currency.current.symbol)…").tag(Mode.paidAmount)
                    }
                    .pickerStyle(.segmented)
                }
                if mode == .equal {
                    Section("With") {
                        Stepper("\(current.others) other\(current.others == 1 ? "" : "s")",
                                value: $request.others, in: max(1, picked.count)...20)
                        let options = (store.people + picked).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                        if !options.isEmpty { MultiChips(options: options, selected: $picked) }
                        TextField("Add a name", text: $newName)
                            .textInputAutocapitalization(.words)
                            .onSubmit {
                                let n = newName.trimmingCharacters(in: .whitespaces).capitalized
                                if !n.isEmpty && !picked.contains(n) { withAnimation(.snappy) { picked.append(n) } }
                                newName = ""
                            }
                        Toggle("They already paid me", isOn: $request.alreadyPaid)
                    }
                } else {
                    Section("They paid") {
                        HStack(spacing: 4) {
                            Text(Currency.current.symbol).font(.title2.bold()).foregroundStyle(.secondary)
                            TextField("0", text: $paidText).font(.title2.bold()).keyboardType(.decimalPad)
                                .accessibilityLabel("Amount they paid")
                        }
                    }
                }
                Section {
                    LabeledContent("Your share") {
                        Text(money(result.updated.amount ?? 0)).font(.title2.bold()).foregroundStyle(.primary)
                    }
                    if mode == .equal && !current.alreadyPaid {
                        LabeledContent("Each owes you", value: money(result.owed.first?.amount ?? 0))
                    }
                } footer: { Text("Total bill \(money(result.updated.splitTotal ?? 0))") }
                .contentTransition(.numericText()) // shares roll as you change the choices
                .animation(.snappy, value: current)
            }
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { withAnimation(.snappy) { store.applySplit(current, to: target) }; dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
