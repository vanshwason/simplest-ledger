import Foundation
import Observation
import LedgerCore

/// Entries live in Documents/ledger.json on the phone. A CSV copy goes to your backup folder after every change.
@Observable @MainActor
final class Store {
    /// One store for the app and the Shortcuts action, so an SMS added in the background shows up live.
    static let shared = Store()

    var entries: [Entry] = []
    var error: String?
    private(set) var backupFolderName = UserDefaults.standard.string(forKey: "backupFolderName")

    private let file = URL.documentsDirectory.appending(path: "ledger.json")
    private let bookmarkKey = "backupBookmark"

    /// The ledger's one currency: the phone region's on first launch, then kept so a region change doesn't relabel it.
    /// A ledger from before currencies existed was always rupees, whatever the phone's region.
    var currency = UserDefaults.standard.string(forKey: "currency")
        ?? (FileManager.default.fileExists(atPath: URL.documentsDirectory.appending(path: "ledger.json").path) ? "INR" : nil)
        ?? Locale.current.currency?.identifier ?? "INR" {
        didSet { UserDefaults.standard.set(currency, forKey: "currency"); Currency.current = Currency(code: currency) }
    }

    init() {
        UserDefaults.standard.set(currency, forKey: "currency")
        Currency.current = Currency(code: currency)
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            // Keep the unreadable file so the next save can't wipe it.
            let copy = URL.documentsDirectory.appending(path: "ledger-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: file, to: copy)
            self.error = "Saved data could not be read. A copy was kept as \(copy.lastPathComponent)."
        }
    }

    /// While a trip is on, every new entry is tagged with it.
    var activeTrip: String? = UserDefaults.standard.string(forKey: "activeTrip") {
        didSet { UserDefaults.standard.set(activeTrip, forKey: "activeTrip") }
    }

    /// People you've dealt with, most recent first, for one-tap picking.
    var people: [String] {
        var seen = Set<String>()
        return entries.sorted { $0.date > $1.date }.map(\.person).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    func add(_ entry: Entry) {
        var entry = entry
        if entry.trip == nil { entry.trip = activeTrip }
        entries.append(entry); save()
    }

    /// Set by a tapped notification; the main screen opens this entry.
    var openEntry: UUID?

    /// When the automation last delivered a message, so the setup screen can say it's working.
    var lastMessageAt = UserDefaults.standard.object(forKey: "lastMessageAt") as? Date {
        didSet { UserDefaults.standard.set(lastMessageAt, forKey: "lastMessageAt") }
    }

    /// From the Shortcuts automation (a bank SMS, a shared WhatsApp message). The same text twice within a
    /// day is skipped, since automations can fire more than once for one message.
    func addFromMessage(_ text: String) async -> Entry? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, MessageFilter.ignoreReason(clean) == nil, // OTPs, failed or scheduled payments, offers…
              !entries.contains(where: { ($0.raw == clean && Date().timeIntervalSince($0.date) < 86_400)
                                         || $0.raw.hasSuffix("Refund: " + clean) }) else { return nil }
        var entry = await SmartParser.parse(clean)
        entry.source = "sms"
        lastMessageAt = Date()
        if Refund.isRefund(entry) {
            if let purchase = Refund.match(for: entry, in: entries) { applyRefund(entry, to: purchase); return nil }
            if !Refund.candidates(for: entry, in: entries).isEmpty { entry.question = Refund.question }
        }
        add(entry)
        return entry
    }

    /// A reply typed on a "needs input" notification: the shop for a refund, or what the money was for.
    func answer(_ id: UUID, with reply: String) async {
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty, let entry = entries.first(where: { $0.id == id }) else { return }
        if entry.question == Refund.question {
            let words = reply.lowercased().split(separator: " ").map(String.init)
            if let p = Refund.candidates(for: entry, in: entries).first(where: { c in
                words.contains { $0.count >= 3 && (c.raw + " " + c.note + " " + c.category).lowercased().contains($0) } }) {
                applyRefund(entry, to: p)
            }
            return
        }
        update(entry.answered(reply, info: await SmartParser.parse(reply)))
    }

    /// Takes a refund off its purchase, keeps the message under it, and drops the separate refund entry.
    func applyRefund(_ refund: Entry, to purchase: Entry) {
        entries.removeAll { $0.id == refund.id }
        guard let i = entries.firstIndex(where: { $0.id == purchase.id }) else { save(); return }
        entries[i] = Refund.apply(refund, to: entries[i]); save()
    }

    func update(_ entry: Entry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry; save()
    }

    func delete(ids: [UUID]) { entries.removeAll { ids.contains($0.id) }; save() }

    /// Splitting again replaces the earlier shares, so a later "it was 4 of us" edits instead of piling up.
    func applySplit(_ request: SplitRequest, to target: Entry) {
        let base = entries.first { $0.id == target.id } ?? target
        let (updated, owed) = Split.apply(request, to: base)
        entries.removeAll { $0.splitOf == base.id }
        if let i = entries.firstIndex(where: { $0.id == base.id }) { entries[i] = updated } else {
            var bill = updated; if bill.trip == nil { bill.trip = activeTrip }
            entries.append(bill)
        }
        entries += owed.map { var e = $0; e.trip = updated.trip ?? activeTrip; return e }
        save()
    }

    /// Adds new rows and overwrites rows with the same id.
    func importCSV(_ text: String) throws {
        for e in try CSV.decode(text) {
            if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        }
        save()
    }

    private var backupFileName: String { UserDefaults.standard.string(forKey: "backupFileName") ?? "ledger-backup.csv" }

    /// True if the folder already holds a backup (another install, a reinstall), so the app asks before replacing it.
    func hasBackup(in url: URL) -> Bool {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.appending(path: "ledger-backup.csv").path)
    }

    /// importExisting: merge the backup already in the folder, then keep backing up to it.
    /// Otherwise an existing backup is left untouched and a new file is written beside it.
    func setBackupFolder(_ url: URL, importExisting: Bool = false) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let existing = url.appending(path: "ledger-backup.csv")
        let hasExisting = FileManager.default.fileExists(atPath: existing.path)
        do {
            // Import first: if the file can't be read, nothing changes and it isn't overwritten.
            if hasExisting && importExisting { try importCSV(String(contentsOf: existing, encoding: .utf8)) }
            var name = "ledger-backup.csv"
            if hasExisting && !importExisting {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"
                name = "ledger-backup \(f.string(from: Date())).csv"
            }
            UserDefaults.standard.set(try url.bookmarkData(), forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: "backupFolderName")
            UserDefaults.standard.set(name, forKey: "backupFileName")
            backupFolderName = url.lastPathComponent
            backup()
        } catch {
            self.error = "Could not use that folder: \(error.localizedDescription)"
        }
    }

    private func save() {
        entries.sort { $0.date > $1.date }
        do {
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
        backup()
    }

    private func backup() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else {
            error = "Backup folder is not reachable. Pick it again from the menu."
            return
        }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let csv = CSV.encode(entries)
        var coordError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: folder.appending(path: backupFileName),
                                       options: .forReplacing, error: &coordError) { url in
            do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { error = "Backup failed: \(e.localizedDescription)" }
        if stale, let fresh = try? folder.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
    }
}
