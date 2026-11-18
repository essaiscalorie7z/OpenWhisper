import Foundation

enum Settings {
    static let group = "group.fr.openwhisper.mobile"
    static func defaults(shared: Bool = true) -> UserDefaults {
        let store = shared ? UserDefaults(suiteName: group) ?? .standard : .standard
        store.register(defaults: ["suggestions": true, "correction": true, "haptique": true,
                                  "apparence": "Automatique", "ponctuation": true])
        return store
    }
}

struct Ticket: Codable {
    let text: String
    let created: Date
}

struct Inbox {
    let folder: URL
    private var pending: URL { folder.appendingPathComponent("dictee.json") }

    static func shared() throws -> Inbox {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.group)
        else { throw CocoaError(.fileNoSuchFile) }
        return Inbox(folder: folder)
    }

    func publish(_ text: String) throws {
        let data = try JSONEncoder().encode(Ticket(text: text, created: Date()))
        try data.write(to: pending, options: [.atomic, .completeFileProtection])
        var file = pending
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    // Rename first. Concurrent consumers cannot claim the same pending result.
    func consume() throws -> String? {
        let claim = folder.appendingPathComponent("lecture-" + UUID().uuidString)
        do { try FileManager.default.moveItem(at: pending, to: claim) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { return nil }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        defer { try? FileManager.default.removeItem(at: claim) }
        let ticket = try JSONDecoder().decode(Ticket.self, from: Data(contentsOf: claim))
        return Date().timeIntervalSince(ticket.created) < 600 ? ticket.text : nil
    }

    func discardExpired(now: Date = Date()) {
        let fm = FileManager.default
        // This maintenance path runs in the sole publisher (the foreground app).
        if let data = try? Data(contentsOf: pending),
           let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
           now.timeIntervalSince(ticket.created) >= 600 {
            try? fm.removeItem(at: pending)
        }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for claim in files where claim.lastPathComponent.hasPrefix("lecture-") {
            if let modified = try? claim.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) >= 600 { try? fm.removeItem(at: claim) }
        }
    }

    func clear() throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for url in files where url == pending || url.lastPathComponent.hasPrefix("lecture-") {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum French {
    static let letters = ["azertyuiop", "qsdfghjklm", "wxcvbn"]
    static let numbers = ["1234567890", "-/:;()€&@“", ".,?!’"]
    static let symbols = ["[]{}#%^*+=", "_\\|~<>$£¥•", ".,?!’"]
    static let accents = ["a":"àâäæ", "e":"éèêë", "i":"îï", "o":"ôöœ", "u":"ùûü", "y":"ÿ", "c":"ç"]
    static func fragment(_ text: String) -> String {
        String(text.reversed().prefix { $0.isLetter }.reversed())
    }
    static func following(_ before: String) -> [String] {
        switch before.lowercased().split(whereSeparator: { !$0.isLetter }).last {
        case "je": return ["suis", "vais"]
        case "nous": return ["sommes", "avons"]
        case "à": return ["la", "demain"]
        case "vous": return ["avez", "êtes"]
        case "très": return ["bien", "bon"]
        default: return before.isEmpty ? ["Bonjour", "Je"] : ["de", "la"]
        }
    }
}
