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

    init() {
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

    /// From the Shortcuts automation (a bank SMS, a shared WhatsApp message). The same text twice within a
    /// day is skipped, since automations can fire more than once for one message.
    func addFromMessage(_ text: String) async -> Entry? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !entries.contains(where: { $0.raw == clean && Date().timeIntervalSince($0.date) < 86_400 }) else { return nil }
        let entry = await SmartParser.parse(clean)
        add(entry)
        return entry
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

    func setBackupFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            UserDefaults.standard.set(try url.bookmarkData(), forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: "backupFolderName")
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
        NSFileCoordinator().coordinate(writingItemAt: folder.appending(path: "ledger-backup.csv"),
                                       options: .forReplacing, error: &coordError) { url in
            do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { error = "Backup failed: \(e.localizedDescription)" }
        if stale, let fresh = try? folder.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
    }
}
