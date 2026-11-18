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
    private static let common = """
    bonjour bonne bonsoir beaucoup bien bientôt bienvenue bien sûr merci mercredi maison maintenant matin même message
    demain depuis dernier dernière déjà deux devoir désolé dimanche donc dossier dire dit disponible donner
    aujourd’hui aussi aucun aucune autre autres avant avec avoir avez allons aller alors après appeler arrive
    besoin bientôt bon bonne bureau bonjour billet bijoux blanc bleue
    cette cela certains chaque chez chose comment comme combien côté comprendre compte continuer contre courrier
    dans demande difficile directement droit droite durant écrire école encore ensemble entre essayer étant être étaient
    famille faire fait faut femme fenêtre fille fils finalement fois français française frère
    garde gare garçon gens grand grande groupe heure hier histoire ici idée important jamais jeudi journée jusqu’à juste
    laisser lequel laquelle leur libre longtemps lorsque lundi lumière magasin mais maintenant malgré maman manger manière mardi
    meilleur merci mettre mieux moins mois moment monde monsieur montrer mouvement
    nécessaire neuf niveau nom nombre notre nouvelle nous nuit oublier parce parfois parler partie partir passer
    pendant penser personne petit petite peut peut-être peux place plaisir plusieurs plutôt point porte possible pour pourquoi
    pouvoir prendre premier première préparer presque problème prochain prochaine projet puis puisque question quelque quelques
    raison recevoir regarder rendez-vous rentrer réponse répondre reste retrouver retour revenir rien route
    samedi savoir semaine semble seulement sinon soir sommes sont sortie souvent suite suivant surtout système
    tard téléphone temps tenir terminer toujours toute toutes travail travailler très trouver
    utiliser vacances vendredi venir vers ville visite voici voilà voir votre voudrais voulez vraiment
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    static func localCompletions(_ word: String) -> [String] {
        guard !word.isEmpty else { return [] }
        return common.lazy.filter { $0.hasPrefix(word.lowercased()) && $0 != word.lowercased() }
            .prefix(4).map { word.first?.isUppercase == true ? $0.capitalized : $0 }
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
