import XCTest
@testable import PeachTVPlus

final class XtreamMappingTests: XCTestCase {

    private let decoder = JSONDecoder()
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    func testLiveChannelMappingMixedIdTypesAndArchive() throws {
        let json = #"""
        [{"stream_id":1,"name":"TVA","stream_icon":"http://i/1.png","category_id":"5","epg_channel_id":"tva","tv_archive":1},
         {"stream_id":"2","name":"RDS","tv_archive":0}]
        """#
        let channels = XtreamMapping.liveChannels(from: try decode([LiveStreamDTO].self, json))
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].id, "1")
        XCTAssertTrue(channels[0].hasArchive)
        XCTAssertEqual(channels[0].iconURL, "http://i/1.png")
        XCTAssertEqual(channels[1].id, "2")
        XCTAssertFalse(channels[1].hasArchive)
        XCTAssertNil(channels[1].iconURL)
    }

    func testCategoryMappingSkipsEmptyId() throws {
        let json = #"[{"category_id":"5","category_name":"Québec"},{"category_id":"","category_name":"X"}]"#
        let cats = XtreamMapping.categories(from: try decode([CategoryDTO].self, json), type: .live)
        XCTAssertEqual(cats.count, 1)
        XCTAssertEqual(cats[0].name, "Québec")
        XCTAssertEqual(cats[0].contentType, .live)
    }

    func testEpgTextBase64AndFallback() {
        XCTAssertEqual(XtreamMapping.decodeText("SGVsbG8="), "Hello")  // Base64 → "Hello"
        XCTAssertEqual(XtreamMapping.decodeText("Direct"), "Direct")   // pas du Base64 → repli brut
        XCTAssertEqual(XtreamMapping.decodeText(nil), "")
        XCTAssertEqual(XtreamMapping.decodeText("   "), "")
    }

    func testSeriesSeasonsSortedNumerically() throws {
        let json = #"""
        {"info":{"name":"Show","plot":"p","cover":"c"},
         "episodes":{
           "2":[{"id":"20","title":"E2x1","container_extension":"mp4","season":"2","episode_num":"1","info":{"duration_secs":"1200","movie_image":"img"}}],
           "1":[{"id":"10","title":"E1x1"}],
           "10":[{"id":"100","title":"E10x1"}]
         }}
        """#
        let dto = try decode(SeriesInfoResponseDTO.self, json)
        let base = Series(id: "9", name: "old", posterURL: nil, categoryId: "c", rating: nil)
        let detail = XtreamMapping.seriesDetail(from: dto, base: base)
        XCTAssertEqual(detail.seasons.map { $0.number }, [1, 2, 10])
        let s2 = detail.seasons.first { $0.number == 2 }
        XCTAssertEqual(s2?.episodes.first?.durationSeconds, 1200)
        XCTAssertEqual(detail.series.name, "Show")
    }

    func testMovieDetailMergesWithBase() throws {
        let json = #"""
        {"info":{"plot":"plot","genre":"Action","releasedate":"2020-01-01","duration_secs":"5400","movie_image":"poster","rating":"7.8"},
         "movie_data":{"stream_id":"3","name":"Film","container_extension":"mkv"}}
        """#
        let dto = try decode(VodInfoResponseDTO.self, json)
        let base = Movie(id: "3", name: "old", posterURL: nil, categoryId: "c", containerExtension: "mp4", rating: nil)
        let detail = XtreamMapping.movieDetail(from: dto, base: base)
        XCTAssertEqual(detail.movie.containerExtension, "mkv")
        XCTAssertEqual(detail.movie.posterURL, "poster")
        XCTAssertEqual(detail.movie.rating, 7.8)
        XCTAssertEqual(detail.plot, "plot")
        XCTAssertEqual(detail.durationSeconds, 5400)
        XCTAssertEqual(detail.genre, "Action")
        XCTAssertEqual(detail.releaseDate, "2020-01-01")
    }

    func testAccountInfoMapping() throws {
        let json = #"{"auth":1,"status":"Active","username":"bob","exp_date":1700000000,"is_trial":"0","active_cons":"1","max_connections":"2"}"#
        let info = try decode(UserInfoDTO.self, json)
        let account = XtreamMapping.accountInfo(from: info)
        XCTAssertEqual(account.username, "bob")
        XCTAssertEqual(account.status, "Active")
        XCTAssertEqual(account.expirationDate, Date(timeIntervalSince1970: 1700000000))
        XCTAssertFalse(account.isTrial)
        XCTAssertEqual(account.activeConnections, 1)
        XCTAssertEqual(account.maxConnections, 2)
    }
}
