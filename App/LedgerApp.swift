import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

@main
struct LedgerApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}

let english = Locale(identifier: "en_IN")

/// Teal from Chat Backup Browser's palette. Used only on the primary action (Liquid Glass color budget).
/// Light #008069 is ~5:1 on white; dark #00A884 matches that app's dark accent.
let accent = Color(UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0, green: 0xA8 / 255, blue: 0x84 / 255, alpha: 1)
    : UIColor(red: 0, green: 0x80 / 255, blue: 0x69 / 255, alpha: 1) })

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var input = ""
    @State private var busy = false
    @State private var onlyNeedsInput = false
    @State private var search = ""
    @State private var editing: Entry?
    @State private var showStatement = false
    @State private var picker: PickerMode?
    @State private var splitting: PendingSplit?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var confirmDelete = false
    // Haptic and symbol-bounce triggers.
    @State private var added = 0
    @State private var flagged = 0
    @State private var deleted = 0
    @FocusState private var inputFocused: Bool
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PickerMode: Identifiable { case csv, folder; var id: Self { self } }

    /// One motion style for the whole app: short and springy, or a plain fade with Reduce Motion on.
    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), change)
    }

    private var barTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var shown: [Entry] {
        store.entries.filter { e in
            (!onlyNeedsInput || e.needsInput) && (search.isEmpty
                || [e.raw, e.category, e.person, e.method, e.note].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Picker("Show", selection: $onlyNeedsInput.animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy)) {
                    Text("All").tag(false)
                    Text("Needs input (\(store.entries.filter(\.needsInput).count))").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                ForEach(shown) { e in
                    Group {
                        if editMode.isEditing { EntryRow(entry: e) } // tap selects while selecting
                        else { Button { editing = e } label: { EntryRow(entry: e) }.tint(.primary) }
                    }
                        .matchedTransitionSource(id: e.id, in: zoom) // the edit sheet zooms out of this row
                        .contextMenu { // long-press actions, as in Chat Backup Browser's mobile UI
                            Button { editing = e } label: { Label("Edit", systemImage: "pencil") }
                            Button { animate { selection = [e.id]; editMode = .active } } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                            if e.kind == .expense {
                                Button { splitting = PendingSplit(request: SplitRequest(), target: e) } label: {
                                    Label("Split…", systemImage: "person.2")
                                }
                            }
                            Button { UIPasteboard.general.string = e.raw } label: { Label("Copy Text", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { animate { store.delete(ids: [e.id]) }; deleted += 1 } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                // Swipe-to-delete off while selecting, so rows show only the checkmark.
                .onDelete(perform: editMode.isEditing ? nil : { offsets in store.delete(ids: offsets.map { shown[$0].id }) })
            }
            .environment(\.editMode, $editMode)
            .overlay {
                if store.entries.isEmpty {
                    ContentUnavailableView("No entries yet", systemImage: "text.bubble",
                        description: Text("Type what happened below, like “1500 spent on snacks”. One entry per line. Anything unclear goes to Needs input."))
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .sensoryFeedback(.warning, trigger: flagged)
            .sensoryFeedback(.impact(weight: .medium), trigger: deleted)
            .sensoryFeedback(.selection, trigger: selection)
            .scrollDismissesKeyboard(.interactively)
            // Search sits under the title so the bottom edge belongs to the input bar.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic))
            .safeAreaBar(edge: .bottom) { // safeAreaBar adds the scroll edge fade under the glass
                ZStack { // the input bar and delete bar slide past each other
                    if editMode.isEditing { deleteBar.transition(barTransition) } else { inputBar.transition(barTransition) }
                }
            }
            .onAppear { inputFocused = true }
            .onChange(of: showStatement || editing != nil || picker != nil || splitting != nil || editMode.isEditing) { _, open in
                if open { inputFocused = false }
            }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode.isEditing {
                        let allSelected = !shown.isEmpty && selection.count == shown.count
                        Button(allSelected ? "Deselect All" : "Select All") {
                            animate { selection = allSelected ? [] : Set(shown.map(\.id)) }
                        }
                    } else {
                        Button("Statement") { showStatement = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode.isEditing {
                        Button("Done") { animate { editMode = .inactive; selection = [] } }.bold()
                    } else {
                    Menu {
                        Button { animate { editMode = .active } } label: { Label("Select Entries", systemImage: "checkmark.circle") }
                        ShareLink(item: CSVExport(entries: store.entries), preview: SharePreview("ledger.csv")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button { picker = .csv } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                        Button { picker = .folder } label: {
                            Label(store.backupFolderName.map { "Backup folder: \($0)" } ?? "Choose backup folder",
                                  systemImage: "externaldrive")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(item: $editing) { EditView(entry: $0).navigationTransition(.zoom(sourceID: $0.id, in: zoom)) }
            .sheet(isPresented: $showStatement) { StatementView() }
            .sheet(item: $splitting) { SplitSheet(pending: $0) }
            .fileImporter(isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } }),
                          allowedContentTypes: picker == .folder ? [.folder] : [.commaSeparatedText, .plainText]) { result in
                let mode = picker
                guard case .success(let url) = result else { return }
                if mode == .folder { store.setBackupFolder(url); return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { try store.importCSV(String(contentsOf: url, encoding: .utf8)) } catch {
                    store.error = error.localizedDescription
                }
            }
            .alert("Problem", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") {}
            } message: { Text(store.error ?? "") }
            // ledger://add?text=... lets the iOS Shortcut (and WhatsApp's Share menu) send text straight in.
            .onOpenURL { url in
                guard url.host() == "add",
                      let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "text" })?.value else { return }
                input = text; add()
            }
            // Test hook for the CI simulator run: `-add "line1\nline2"` and `-statement`.
            .task {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-add"), i + 1 < args.count { input = args[i + 1]; add() }
                showStatement = args.contains("-statement")
            }
        }
    }

    /// The app's one custom glass surface: a floating input bar with the view's single prominent action.
    private var inputBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("e.g. 1500 spent on snacks", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                Button(action: add) {
                    if busy { ProgressView().transition(.scale.combined(with: .opacity)) } else {
                        Image(systemName: "arrow.up").font(.body.bold())
                            .symbolEffect(.bounce.up, value: added)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: busy)
                .buttonStyle(.glassProminent)
                .tint(accent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add entry")
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
    }

    /// Replaces the input bar while selecting. Deleting always asks first.
    private var deleteBar: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Text(selection.isEmpty ? "Select entries to delete"
                 : "Delete \(selection.count) \(selection.count == 1 ? "Entry" : "Entries")")
                .bold().frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(selection.isEmpty)
        .padding(.horizontal).padding(.bottom, 8)
        .confirmationDialog("Delete \(selection.count) \(selection.count == 1 ? "entry" : "entries")? This can't be undone.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                animate { store.delete(ids: Array(selection)); selection = []; editMode = .inactive }
                deleted += 1
            }
        }
    }

    private func add() {
        let lines = input.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        input = ""; busy = true
        Task {
            for line in lines {
                // "delete all test entries" only selects; you confirm with the Delete button.
                if let request = DeleteCommand.parse(line) {
                    let ids = DeleteCommand.matches(request, in: store.entries)
                    if ids.isEmpty { store.error = "No entries match “\(line)”." } else {
                        animate { onlyNeedsInput = false; search = ""; selection = Set(ids); editMode = .active }
                    }
                    continue
                }
                guard let request = Split.parse(line) else {
                    let entry = await SmartParser.parse(line)
                    animate { store.add(entry) } // new row slides in at the top
                    if entry.needsInput { flagged += 1 } else { added += 1 }
                    continue
                }
                // A split line edits an earlier expense, or adds the bill first when it names a new amount.
                if let target = Split.target(for: request, in: store.entries) {
                    splitting = PendingSplit(request: request, target: target)
                } else if request.amount != nil {
                    var bill = await SmartParser.parse(line)
                    bill.kind = .expense; bill.person = ""
                    if bill.category == "Loan" { bill.category = "Other" }
                    bill.question = bill.missingInfo()
                    animate { store.add(bill) }
                    splitting = PendingSplit(request: request, target: bill)
                } else {
                    store.error = "There's no expense to split yet. Add the expense first, then split it."
                }
            }
            busy = false
        }
    }
}

struct PendingSplit: Identifiable {
    let id = UUID()
    var request: SplitRequest
    var target: Entry
}

/// Confirms a split before anything changes, since it rewrites an existing entry.
struct SplitSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: Entry
    @State private var request: SplitRequest
    @State private var namesText: String

    init(pending: PendingSplit) {
        target = pending.target
        _request = State(initialValue: pending.request)
        _namesText = State(initialValue: pending.request.names.joined(separator: ", "))
    }

    private var current: SplitRequest {
        var r = request
        r.names = namesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        r.others = max(r.others, r.names.count)
        return r
    }

    var body: some View {
        let result = Split.apply(current, to: target)
        NavigationStack {
            Form {
                Section("Expense") { EntryRow(entry: target) }
                Section("Result") {
                    LabeledContent("Total bill", value: rupees(result.updated.splitTotal ?? 0))
                    LabeledContent("Your share", value: rupees(result.updated.amount ?? 0))
                    if !current.alreadyPaid {
                        LabeledContent("Each person owes you", value: rupees(result.owed.first?.amount ?? 0))
                    }
                }
                .contentTransition(.numericText()) // shares roll as you change the number of people
                .animation(.snappy, value: current)
                Section {
                    Stepper("Split with \(current.others) other\(current.others == 1 ? "" : "s")", value: $request.others, in: 1...20)
                    TextField("Names (optional), e.g. Rahul, Amit", text: $namesText)
                    Toggle("They already paid their share", isOn: $request.alreadyPaid)
                } footer: {
                    Text(request.alreadyPaid ? "Only your share stays as spending."
                         : "Each person gets a Lent entry, so the statement shows who owes you.")
                }
            }
            .navigationTitle("Split Expense")
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

struct EntryRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.kind.label + (entry.person.isEmpty ? "" : " · \(entry.person)")).font(.headline)
                Spacer()
                // "+" marks money in; system green text on white is ~2.2:1, below the 3:1 bold minimum.
                Text((entry.kind.isIn ? "+" : "") + (entry.amount.map(rupees) ?? "?")).font(.headline.monospacedDigit())
                    .contentTransition(.numericText()) // e.g. ₹1,200 rolls down to ₹300 after a split
            }
            Text([entry.category, entry.method, entry.date.formatted(.dateTime.day().month().year().locale(english))]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(entry.displayText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if entry.needsInput {
                Label { Text(entry.question) } icon: {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                }.font(.caption.weight(.medium))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct EditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entry: Entry
    @State private var amountText: String
    @State private var answer = ""
    @State private var busy = false

    init(entry: Entry) {
        _entry = State(initialValue: entry)
        _amountText = State(initialValue: entry.amount.map { "\($0)" } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if entry.needsInput {
                    Section("Needs input") {
                        Label { Text(entry.question) } icon: {
                            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                        }
                        TextField("Your answer", text: $answer)
                        Button(busy ? "Reading…" : "Use answer", action: useAnswer).disabled(answer.isEmpty || busy)
                    }
                }
                Section("Details") {
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    if let total = entry.splitTotal { LabeledContent("Your share of", value: rupees(total)) }
                    Picker("Type", selection: $entry.kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Category", selection: $entry.category) {
                        ForEach(Array(Set(RuleParser.categoryNames + [entry.category])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Payment method", text: $entry.method)
                    TextField("Person", text: $entry.person)
                    TextField("Note", text: $entry.note)
                    DatePicker("Date", selection: $entry.date, displayedComponents: .date)
                }
                Section("You typed") { Text(entry.raw) }
            }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    /// Re-reads what you typed plus your answer, keeping the original date and id.
    private func useAnswer() {
        // "Who was this with?" just needs the name; re-reading "Share of: …" text would turn it into a new expense.
        if entry.kind.needsPerson && entry.person.isEmpty && entry.amount != nil {
            entry.person = answer.trimmingCharacters(in: .whitespaces).capitalized
            entry.question = entry.missingInfo(checkCategory: false); answer = ""
            return
        }
        busy = true
        Task {
            var e = await SmartParser.parse(entry.raw + " " + answer)
            e.id = entry.id; e.date = entry.date; e.raw = entry.raw + " (" + answer + ")"
            e.splitTotal = entry.splitTotal; e.splitOf = entry.splitOf
            entry = e; amountText = e.amount.map { "\($0)" } ?? ""; answer = ""; busy = false
        }
    }

    private func save() {
        entry.amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
        entry.question = entry.missingInfo(checkCategory: false)
        withAnimation(.snappy) { store.update(entry) }
        dismiss()
    }
}

struct StatementView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: String { Statement.text(for: month, entries: store.entries) }

    var body: some View {
        NavigationStack {
            // Two-axis scroll keeps the plain-text columns aligned instead of wrapping.
            ScrollView([.vertical, .horizontal]) {
                Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .fixedSize().padding()
                    .id(month) // a new month pushes in from the side you tapped
                    .transition(reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading))
            }
            .sensoryFeedback(.selection, trigger: month)
            .navigationTitle(month.formatted(.dateTime.month(.wide).year().locale(english)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: text) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { shift(-1) } label: { Label("Previous month", systemImage: "chevron.left") }
                    Spacer()
                    Button { shift(1) } label: { Label("Next month", systemImage: "chevron.right") }
                }
            }
        }
    }

    private func shift(_ by: Int) {
        forward = by > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) {
            month = Calendar.current.date(byAdding: .month, value: by, to: month) ?? month
        }
    }
}

struct CSVExport: Transferable {
    let entries: [Entry]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let url = FileManager.default.temporaryDirectory.appending(path: "ledger.csv")
            try CSV.encode(item.entries).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
