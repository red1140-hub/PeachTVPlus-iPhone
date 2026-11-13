import Foundation

/// Rattrapage (timeshift) depuis l'EPG : construit l'URL `/timeshift/USER/PASS/DUREE/DEBUT/ID.ts`
/// à partir d'un programme archivé. La fabrique (`XtreamURLFactory`, M1) formate le **début en
/// fuseau local** et masque les identifiants dans les logs. Voir `docs/PORT-SPEC.md §3.1 / §7`.
enum CatchUp {

    /// URL de rattrapage pour `programme` sur la chaîne `streamId`. `nil` si le programme n'a
    /// pas d'archive ou une plage temporelle inconnue/non positive.
    static func timeshiftURL(for programme: EpgProgramme, streamId: String,
                             using factory: XtreamURLFactory,
                             timeZone: TimeZone = .current) -> URL? {
        guard programme.hasArchive,
              let start = programme.start,
              let end = programme.end else { return nil }

        let durationMinutes = Int(end.timeIntervalSince(start) / 60)
        guard durationMinutes > 0 else { return nil }

        return factory.timeshiftURL(streamId: streamId,
                                    durationMinutes: durationMinutes,
                                    start: start,
                                    timeZone: timeZone)
    }
}
