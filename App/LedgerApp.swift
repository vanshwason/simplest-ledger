import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import VisionKit
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
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var askTripName = false
    @State private var tripName = ""
    @State private var notice: String? // shown above the text box when a command found nothing
    @State private var noticeChips: [String] = []
    @State private var showHelp = false
    @State private var showScanner = false
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
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
    enum Filter { case all, needsInput, trip }

    /// One motion style for the whole app: short and springy, or a plain fade with Reduce Motion on.
    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.35), change)
    }

    private var barTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var shown: [Entry] {
        store.entries.filter { e in
            let inFilter = switch filter {
            case .all: true
            case .needsInput: e.needsInput
            case .trip: e.trip != nil && e.trip == store.activeTrip
            }
            return inFilter && (search.isEmpty
                || [e.raw, e.category, e.person, e.method, e.note, e.trip ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private func startTrip(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        animate { store.activeTrip = clean.isEmpty ? "Trip" : clean; filter = .trip }
    }

    private func endTrip() { animate { store.activeTrip = nil; if filter == .trip { filter = .all } } }

    /// "🧳 Goa · ₹12,400 · End": the running trip, always one tap away.
    @ViewBuilder private var tripBanner: some View {
        if let trip = store.activeTrip {
            HStack {
                Text("🧳").font(.title3)
                VStack(alignment: .leading) {
                    Text(trip).font(.headline)
                    Text("\(rupees(store.entries.spent(onTrip: trip))) spent · new entries go here")
                        .font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("End Trip", action: endTrip).buttonStyle(.bordered)
            }
            .transition(barTransition)
        }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                tripBanner
                Picker("Show", selection: $filter.animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy)) {
                    Text("All").tag(Filter.all)
                    Text("Needs input (\(store.entries.filter(\.needsInput).count))").tag(Filter.needsInput)
                    if store.activeTrip != nil { Text("🧳 Trip").tag(Filter.trip) }
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
                            Menu {
                                ForEach(RuleParser.categoryNames, id: \.self) { name in
                                    Button("\(RuleParser.emoji(for: name)) \(name)") {
                                        var changed = e; changed.category = name
                                        changed.question = changed.missingInfo(checkCategory: false)
                                        animate { store.update(changed) }
                                    }
                                }
                            } label: { Label("Category", systemImage: "tag") }
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
            .onChange(of: input) { if !input.isEmpty { notice = nil } } // typing replaces the fix-it hint
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
                        Button { showHelp = true } label: { Label("What Can I Type?", systemImage: "questionmark.circle") }
                        Button { animate { editMode = .active } } label: { Label("Select Entries", systemImage: "checkmark.circle") }
                        if store.activeTrip == nil {
                            Button { tripName = ""; askTripName = true } label: { Label("Start a Trip…", systemImage: "suitcase") }
                        } else {
                            Button(action: endTrip) { Label("End Trip", systemImage: "suitcase.fill") }
                        }
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
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in showScanner = false; readReceipt(images) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage {
                        readReceipt([image])
                    }
                    photoItem = nil
                }
            }
            .sheet(isPresented: $showHelp) { HelpSheet { input = $0; notice = nil; showHelp = false; inputFocused = true } }
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
            .alert("Start a Trip", isPresented: $askTripName) {
                TextField("Where? e.g. Goa", text: $tripName)
                Button("Start") { startTrip(tripName) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Everything you add until you end it is grouped under this trip.") }
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
                if args.contains("-edit-first") { editing = store.entries.first(where: \.needsInput) ?? store.entries.first }
            }
        }
    }

    /// The app's one custom glass surface: a floating input bar with the view's single prominent action.
    private var inputBar: some View {
        let suggestion = Suggest.forInput(input, entries: store.entries, activeTrip: store.activeTrip)
        let chips = notice != nil ? noticeChips : (inputFocused ? suggestion.chips : [])
        let label = notice ?? suggestion.didYouMean
        return GlassEffectContainer(spacing: 8) {
          VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label).font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
            }
            if !chips.isEmpty { // tap to fill the box; you still send it yourself
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Button(chip) { input = chip; notice = nil; inputFocused = true }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 4) {
                    TextField("e.g. 1500 spent on snacks", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .padding(.vertical, 12)
                    Menu {
                        if VNDocumentCameraViewController.isSupported {
                            Button { showScanner = true } label: { Label("Scan Receipt", systemImage: "doc.viewfinder") }
                        }
                        Button { showPhotos = true } label: { Label("Choose Photo or Screenshot", systemImage: "photo") }
                    } label: {
                        Image(systemName: "doc.viewfinder").font(.title3).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Scan receipt")
                }
                .padding(.leading, 16).padding(.trailing, 4)
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
          }
          .padding(.horizontal).padding(.bottom, 8)
          .animation(.snappy, value: chips)
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

    /// Reads the receipt on-device and puts a sentence in the box for you to check, then tap ↑.
    private func readReceipt(_ images: [CGImage]) {
        guard !images.isEmpty else { return }
        busy = true
        Task {
            if let sentence = await ReceiptText.sentence(from: images) {
                input = sentence; inputFocused = true
            } else {
                notice = "Couldn't find a total on that receipt. Type it instead, like “540 dominos”."
                noticeChips = []
            }
            busy = false
        }
    }

    private func add() {
        let lines = input.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        input = ""; busy = true
        Task {
            for line in lines {
                switch TripCommand.parse(line) {
                case .start(let name)?: startTrip(name); continue
                case .end?: endTrip(); continue
                case nil: break
                }
                // "delete all test entries" only selects; you confirm with the Delete button.
                if let request = DeleteCommand.parse(line) {
                    let ids = DeleteCommand.matches(request, in: store.entries)
                    if ids.isEmpty {
                        notice = "No entries match “\(line)”. Try one of these:"
                        noticeChips = Suggest.fixes(forFailed: line, entries: store.entries)
                    } else {
                        animate { filter = .all; search = ""; selection = Set(ids); editMode = .active }
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
                    // Saved only if you tap Split (applySplit adds it); Cancel leaves no stray entry.
                    splitting = PendingSplit(request: request, target: bill)
                } else {
                    notice = "There's no expense to split yet. Try one of these:"
                    noticeChips = Suggest.fixes(forFailed: line, entries: store.entries)
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

struct EntryRow: View {
    let entry: Entry
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
        Text(RuleParser.emoji(for: entry.category)) // category icon; the category name is in the text below
            .font(.title3)
            .frame(width: 40, height: 40)
            .background(.fill.tertiary, in: .rect(cornerRadius: 10))
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.kind.label + (entry.person.isEmpty ? "" : " · \(entry.person)")).font(.headline)
                Spacer()
                // "+" marks money in; system green text on white is ~2.2:1, below the 3:1 bold minimum.
                Text((entry.kind.isIn ? "+" : "") + (entry.amount.map(rupees) ?? "?")).font(.headline.monospacedDigit())
                    .contentTransition(.numericText()) // e.g. ₹1,200 rolls down to ₹300 after a split
            }
            Text([entry.category, entry.method, entry.trip.map { "🧳 \($0)" } ?? "",
                  entry.date.formatted(.dateTime.day().month().year().locale(english))]
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
