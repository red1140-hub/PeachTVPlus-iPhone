import Foundation

/// Conversion DTO Xtream → modèles de domaine. Tolérante : ignore les items sans id,
/// décode l'EPG Base64 avec repli texte brut, convertit les timestamps epoch.
enum XtreamMapping {

    // MARK: - Compte

    static func accountInfo(from info: UserInfoDTO) -> AccountInfo {
        AccountInfo(
            username: info.username ?? "",
            status: info.status ?? "",
            expirationDate: info.expDate?.epochDate,
            isTrial: (info.isTrial?.value == "1"),
            activeConnections: info.activeCons?.intValue ?? 0,
            maxConnections: info.maxConnections?.intValue ?? 0
        )
    }

    // MARK: - Catalogue

    static func categories(from dtos: [CategoryDTO], type: ContentType) -> [Category] {
        dtos.compactMap { dto in
            guard !dto.categoryId.isEmpty else { return nil }
            return Category(id: dto.categoryId.value,
                            name: dto.categoryName ?? "",
                            contentType: type)
        }
    }

    static func liveChannels(from dtos: [LiveStreamDTO]) -> [LiveChannel] {
        dtos.compactMap { dto in
            guard !dto.streamId.isEmpty else { return nil }
            return LiveChannel(
                id: dto.streamId.value,
                name: dto.name ?? "",
                iconURL: nonEmpty(dto.streamIcon),
                categoryId: dto.categoryId?.value,
                epgChannelId: nonEmpty(dto.epgChannelId),
                hasArchive: (dto.tvArchive?.intValue ?? 0) > 0
            )
        }
    }

    static func movies(from dtos: [MovieStreamDTO]) -> [Movie] {
        dtos.compactMap { dto in
            guard !dto.streamId.isEmpty else { return nil }
            return Movie(
                id: dto.streamId.value,
                name: dto.name ?? "",
                posterURL: nonEmpty(dto.streamIcon),
                categoryId: dto.categoryId?.value,
                containerExtension: nonEmpty(dto.containerExtension),
                rating: dto.rating?.doubleValue
            )
        }
    }

    static func seriesList(from dtos: [SeriesStreamDTO]) -> [Series] {
        dtos.compactMap { dto in
            guard !dto.seriesId.isEmpty else { return nil }
            return Series(
                id: dto.seriesId.value,
                name: dto.name ?? "",
                posterURL: nonEmpty(dto.cover),
                categoryId: dto.categoryId?.value,
                rating: dto.rating?.doubleValue
            )
        }
    }

    // MARK: - Détail

    static func movieDetail(from dto: VodInfoResponseDTO, base: Movie) -> MovieDetail {
        let info = dto.info
        let ext = nonEmpty(dto.movieData?.containerExtension) ?? base.containerExtension
        let movie = Movie(
            id: base.id,
            name: nonEmpty(dto.movieData?.name) ?? base.name,
            posterURL: nonEmpty(info?.movieImage) ?? base.posterURL,
            categoryId: base.categoryId,
            containerExtension: ext,
            rating: info?.rating?.doubleValue ?? base.rating
        )
        return MovieDetail(
            movie: movie,
            plot: nonEmpty(info?.plot),
            durationSeconds: info?.durationSecs?.intValue,
            genre: nonEmpty(info?.genre),
            releaseDate: nonEmpty(info?.releaseDate),
            cast: nonEmpty(info?.cast)
        )
    }

    static func seriesDetail(from dto: SeriesInfoResponseDTO, base: Series) -> SeriesDetail {
        var seasons: [Season] = []
        if let episodesBySeason = dto.episodes {
            for key in episodesBySeason.keys.sorted(by: numericAscending) {
                let seasonNumber = Int(key) ?? 0
                let episodes = (episodesBySeason[key] ?? []).compactMap { ep -> Episode? in
                    guard !ep.id.isEmpty else { return nil }
                    return Episode(
                        id: ep.id.value,
                        title: ep.title ?? "",
                        seasonNumber: ep.season?.intValue ?? seasonNumber,
                        episodeNumber: ep.episodeNum?.intValue,
                        containerExtension: nonEmpty(ep.containerExtension),
                        durationSeconds: ep.info?.durationSecs?.intValue,
                        posterURL: nonEmpty(ep.info?.movieImage)
                    )
                }
                seasons.append(Season(id: seasonNumber, episodes: episodes))
            }
        }
        let series = Series(
            id: base.id,
            name: nonEmpty(dto.info?.name) ?? base.name,
            posterURL: nonEmpty(dto.info?.cover) ?? base.posterURL,
            categoryId: base.categoryId,
            rating: base.rating
        )
        return SeriesDetail(
            series: series,
            plot: nonEmpty(dto.info?.plot),
            genre: nonEmpty(dto.info?.genre),
            cast: nonEmpty(dto.info?.cast),
            seasons: seasons
        )
    }

    // MARK: - EPG

    static func epgProgrammes(from dto: ShortEpgResponseDTO) -> [EpgProgramme] {
        (dto.epgListings ?? []).map { item in
            EpgProgramme(
                id: item.id?.value ?? UUID().uuidString,
                title: decodeText(item.title),
                description: decodeText(item.description),
                start: item.startTimestamp?.epochDate,
                end: item.stopTimestamp?.epochDate,
                hasArchive: (item.hasArchive?.intValue ?? 0) > 0
            )
        }
    }

    /// Décode un texte EPG : Base64 → UTF-8, repli sur le texte brut si ce n'est pas du
    /// Base64 valide (ou pas de l'UTF-8 lisible).
    static func decodeText(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let data = Data(base64Encoded: trimmed),
           let decoded = String(data: data, encoding: .utf8),
           !decoded.isEmpty {
            return decoded
        }
        return raw
    }

    // MARK: - Helpers

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    /// Tri des clés de saison « 1, 2, 10 » numériquement (et non « 1, 10, 2 »).
    private static func numericAscending(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        default: return a < b
        }
    }
}
