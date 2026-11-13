import Foundation

/// Type de contenu, commun au catalogue, aux favoris et aux positions de lecture.
enum ContentType: String, Codable, Equatable {
    case live
    case vod
    case series
}

// MARK: - Catalogue

struct Category: Identifiable, Equatable, Hashable {
    let id: String          // category_id
    let name: String
    let contentType: ContentType
}

struct LiveChannel: Identifiable, Equatable, Hashable {
    let id: String          // stream_id
    let name: String
    let iconURL: String?
    let categoryId: String?
    let epgChannelId: String?
    let hasArchive: Bool    // tv_archive > 0 → rattrapage dispo
}

struct Movie: Identifiable, Equatable, Hashable {
    let id: String          // stream_id
    let name: String
    let posterURL: String?
    let categoryId: String?
    let containerExtension: String?   // mp4 / mkv / ts…
    let rating: Double?
}

struct Series: Identifiable, Equatable, Hashable {
    let id: String          // series_id
    let name: String
    let posterURL: String?
    let categoryId: String?
    let rating: Double?
}

// MARK: - Détail

struct Episode: Identifiable, Equatable, Hashable {
    let id: String          // episode id (flux)
    let title: String
    let seasonNumber: Int
    let episodeNumber: Int?
    let containerExtension: String?
    let durationSeconds: Int?
    let posterURL: String?
}

struct Season: Identifiable, Equatable, Hashable {
    let id: Int             // numéro de saison
    var number: Int { id }
    let episodes: [Episode]
}

struct MovieDetail: Equatable {
    let movie: Movie
    let plot: String?
    let durationSeconds: Int?
    let genre: String?
    let releaseDate: String?
    let cast: String?        // chaîne brute « acteur1, acteur2… » (pas d'index ici — M2)
}

struct SeriesDetail: Equatable {
    let series: Series
    let plot: String?
    let genre: String?
    let cast: String?
    let seasons: [Season]
}

// MARK: - EPG

struct EpgProgramme: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let description: String
    let start: Date?
    let end: Date?
    let hasArchive: Bool
}

// MARK: - Compte & login

struct AccountInfo: Equatable {
    let username: String
    let status: String
    let expirationDate: Date?
    let isTrial: Bool
    let activeConnections: Int
    let maxConnections: Int
}

/// Résultat d'une tentative de connexion (porté de `XtreamRepository.login` Android).
enum LoginResult: Equatable {
    case success(AccountInfo)
    case invalidCredentials
    case expired
    case networkError(String)
}
