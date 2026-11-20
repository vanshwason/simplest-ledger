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

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var input = ""
    @State private var busy = false
    @State private var onlyNeedsInput = false
    @State private var search = ""
    @State private var editing: Entry?
    @State private var showStatement = false
    @State private var picker: PickerMode?
    @FocusState private var inputFocused: Bool

    enum PickerMode: Identifiable { case csv, folder; var id: Self { self } }

    private var shown: [Entry] {
        store.entries.filter { e in
            (!onlyNeedsInput || e.needsInput) && (search.isEmpty
                || [e.raw, e.category, e.person, e.method, e.note].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $onlyNeedsInput) {
                    Text("All").tag(false)
                    Text("Needs input (\(store.entries.filter(\.needsInput).count))").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                ForEach(shown) { e in
                    Button { editing = e } label: { EntryRow(entry: e) }.tint(.primary)
                }
                .onDelete { offsets in store.delete(ids: offsets.map { shown[$0].id }) }
            }
            .overlay {
                if store.entries.isEmpty {
                    ContentUnavailableView("No entries yet", systemImage: "text.bubble",
                        description: Text("Type what happened below, like “1500 spent on snacks”. One entry per line. Anything unclear goes to Needs input."))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Search sits under the title so the bottom edge belongs to the input bar.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic))
            .safeAreaBar(edge: .bottom) { inputBar } // safeAreaBar adds the scroll edge fade under the glass
            .onAppear { inputFocused = true }
            .onChange(of: showStatement || editing != nil || picker != nil) { _, open in if open { inputFocused = false } }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Statement") { showStatement = true } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
            .sheet(item: $editing) { EditView(entry: $0) }
            .sheet(isPresented: $showStatement) { StatementView() }
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
                    if busy { ProgressView() } else { Image(systemName: "arrow.up").font(.body.bold()) }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add entry")
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
    }

    private func add() {
        let lines = input.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        input = ""; busy = true
        Task {
            for line in lines { store.add(await SmartParser.parse(line)) }
            busy = false
        }
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
            }
            Text([entry.category, entry.method, entry.date.formatted(.dateTime.day().month().year().locale(english))]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(entry.raw).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if entry.needsInput {
                Label { Text(entry.question) } icon: {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                }.font(.caption.weight(.medium))
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
        busy = true
        Task {
            var e = await SmartParser.parse(entry.raw + " " + answer)
            e.id = entry.id; e.date = entry.date; e.raw = entry.raw + " (" + answer + ")"
            entry = e; amountText = e.amount.map { "\($0)" } ?? ""; answer = ""; busy = false
        }
    }

    private func save() {
        entry.amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
        entry.question = entry.missingInfo(checkCategory: false)
        store.update(entry)
        dismiss()
    }
}

struct StatementView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()

    private var text: String { Statement.text(for: month, entries: store.entries) }

    var body: some View {
        NavigationStack {
            // Two-axis scroll keeps the plain-text columns aligned instead of wrapping.
            ScrollView([.vertical, .horizontal]) {
                Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .fixedSize().padding()
            }
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

    private func shift(_ by: Int) { month = Calendar.current.date(byAdding: .month, value: by, to: month) ?? month }
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
