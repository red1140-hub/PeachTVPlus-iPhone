import Foundation

// DTOs Xtream. On utilise des `CodingKeys` **explicites** partout (pas de stratégie
// snake_case globale) car les panels Xtream mélangent les conventions de clés
// (`releasedate` vs `release_date`, etc.). Toutes les valeurs numériques-ou-chaînes
// passent par `FlexibleString`. Décodage tolérant : tout champ est optionnel.

// MARK: - Auth / compte

struct AuthResponseDTO: Decodable {
    let userInfo: UserInfoDTO?
    let serverInfo: ServerInfoDTO?
    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

struct UserInfoDTO: Decodable {
    let username: String?
    let auth: FlexibleString?
    let status: String?
    let expDate: FlexibleString?
    let isTrial: FlexibleString?
    let activeCons: FlexibleString?
    let maxConnections: FlexibleString?
    enum CodingKeys: String, CodingKey {
        case username
        case auth
        case status
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
    }
}

struct ServerInfoDTO: Decodable {
    let url: String?
    let serverProtocol: String?
    let timezone: String?
    enum CodingKeys: String, CodingKey {
        case url
        case serverProtocol = "server_protocol"
        case timezone
    }
}

// MARK: - Catégories & listes

struct CategoryDTO: Decodable {
    let categoryId: FlexibleString
    let categoryName: String?
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
    }
}

struct LiveStreamDTO: Decodable {
    let streamId: FlexibleString
    let name: String?
    let streamIcon: String?
    let categoryId: FlexibleString?
    let epgChannelId: String?
    let tvArchive: FlexibleString?
    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case epgChannelId = "epg_channel_id"
        case tvArchive = "tv_archive"
    }
}

struct MovieStreamDTO: Decodable {
    let streamId: FlexibleString
    let name: String?
    let streamIcon: String?
    let categoryId: FlexibleString?
    let containerExtension: String?
    let rating: FlexibleString?
    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case containerExtension = "container_extension"
        case rating
    }
}

struct SeriesStreamDTO: Decodable {
    let seriesId: FlexibleString
    let name: String?
    let cover: String?
    let categoryId: FlexibleString?
    let rating: FlexibleString?
    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name
        case cover
        case categoryId = "category_id"
        case rating
    }
}

// MARK: - Détail film

struct VodInfoResponseDTO: Decodable {
    let info: VodInfoDTO?
    let movieData: MovieDataDTO?
    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
}

struct VodInfoDTO: Decodable {
    let plot: String?
    let genre: String?
    let cast: String?
    let rating: FlexibleString?
    let releaseDate: String?
    let durationSecs: FlexibleString?
    let movieImage: String?
    enum CodingKeys: String, CodingKey {
        case plot, genre, cast, rating
        case releaseDate = "releasedate"
        case durationSecs = "duration_secs"
        case movieImage = "movie_image"
    }
}

struct MovieDataDTO: Decodable {
    let streamId: FlexibleString?
    let name: String?
    let containerExtension: String?
    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case containerExtension = "container_extension"
    }
}

// MARK: - Détail série

struct SeriesInfoResponseDTO: Decodable {
    let info: SeriesInfoDTO?
    let episodes: [String: [EpisodeDTO]]?
    // `seasons` est ignoré ici : on reconstruit les saisons depuis les clés d'`episodes`.
}

struct SeriesInfoDTO: Decodable {
    let name: String?
    let plot: String?
    let genre: String?
    let cast: String?
    let cover: String?
}

struct EpisodeDTO: Decodable {
    let id: FlexibleString
    let title: String?
    let containerExtension: String?
    let season: FlexibleString?
    let episodeNum: FlexibleString?
    let info: EpisodeInfoDTO?
    enum CodingKeys: String, CodingKey {
        case id, title, season, info
        case containerExtension = "container_extension"
        case episodeNum = "episode_num"
    }
}

struct EpisodeInfoDTO: Decodable {
    let durationSecs: FlexibleString?
    let movieImage: String?
    enum CodingKeys: String, CodingKey {
        case durationSecs = "duration_secs"
        case movieImage = "movie_image"
    }
}

// MARK: - EPG

struct ShortEpgResponseDTO: Decodable {
    let epgListings: [EpgItemDTO]?
    enum CodingKeys: String, CodingKey {
        case epgListings = "epg_listings"
    }
}

struct EpgItemDTO: Decodable {
    let id: FlexibleString?
    let title: String?          // Base64 sur la plupart des panels
    let description: String?    // Base64 idem
    let startTimestamp: FlexibleString?
    let stopTimestamp: FlexibleString?
    let hasArchive: FlexibleString?
    enum CodingKeys: String, CodingKey {
        case id, title, description
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
        case hasArchive = "has_archive"
    }
}
