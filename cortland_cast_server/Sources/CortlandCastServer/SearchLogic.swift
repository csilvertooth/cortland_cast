import Foundation

enum SearchScope: String, Codable {
    case track
    case album
    case artist
    case all
}

func matchesQuery(_ query: String, in value: String) -> Bool {
    // Normalize: case/diacritic insensitive
    let normalizedValue = value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let normalizedQuery = query
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // "talk corners" -> ["talk", "corners"]
    let tokens = normalizedQuery
        .split(whereSeparator: { $0.isWhitespace })
        .map { String($0) }

    guard !tokens.isEmpty else { return false }

    // Every token must appear somewhere in the value
    for token in tokens {
        if !normalizedValue.contains(token) {
            return false
        }
    }
    return true
}

struct SearchResult: Codable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let type: String    // "track" | "album" | "artist"
}