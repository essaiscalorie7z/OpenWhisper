import Foundation

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
