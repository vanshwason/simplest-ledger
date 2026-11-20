import Foundation
import Observation
import LedgerCore

/// Entries live in Documents/ledger.json on the phone. A CSV copy goes to your backup folder after every change.
@Observable @MainActor
final class Store {
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

    func add(_ entry: Entry) { entries.append(entry); save() }

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
        if let i = entries.firstIndex(where: { $0.id == base.id }) { entries[i] = updated } else { entries.append(updated) }
        entries += owed
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
