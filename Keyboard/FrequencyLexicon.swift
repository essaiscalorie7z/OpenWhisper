import Foundation

/// All keys are pre-sorted at build time. Substrings share the backing table.
final class FrequencyLexicon {
    private struct Entry {
        let key: Substring
        let word: Substring
        let rank: Int
    }
    private let entries: [Entry]
    static let bundled = FrequencyLexicon(file: Bundle(for: FrequencyLexicon.self).url(forResource: "fr", withExtension: "tsv"))

    init(file: URL?) {
        guard let file, let data = try? String(contentsOf: file, encoding: .utf8) else { entries = []; return }
        entries = data.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 3, let rank = Int(parts[2]) else { return nil }
            return Entry(key: parts[0], word: parts[1], rank: rank)
        }
    }

    func completions(_ fragment: String) -> [String] {
        guard !fragment.isEmpty else { return [] }
        let folded = fragment.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
        var low = 0
        var high = entries.count
        while low < high {
            let mid = low + (high - low) / 2
            if entries[mid].key < folded[...] { low = mid + 1 } else { high = mid }
        }
        let typed = fragment.lowercased()
        var best: [Entry] = []
        for e in entries[low...] {
            guard e.key.hasPrefix(folded) else { break }
            guard e.word != typed[...] else { continue }
            if best.count == 2 && e.rank >= best[1].rank { continue }
            if let first = best.first, e.rank >= first.rank { best.insert(e, at: 1) }
            else { best.insert(e, at: 0) }
            if best.count > 2 { best.removeLast() }
        }
        return best.map { fragment.first?.isUppercase == true ? $0.word.capitalized : String($0.word) }
    }
}
