import Foundation

/// Calculs EPG « maintenant / ensuite » + progression, à partir des programmes déjà décodés
/// (`XtreamMapping.epgProgrammes`, Base64 géré en M1). Pure, testable avec des dates fixes.
/// La grille 12 h / en-têtes collants est de l'affichage (M5) ; ici, la logique temporelle.
struct EpgTimeline {
    let programmes: [EpgProgramme]

    init(_ programmes: [EpgProgramme]) {
        // Trié par début pour des recherches déterministes (programmes sans date relégués).
        self.programmes = programmes.sorted {
            ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture)
        }
    }

    /// Programme en cours à `date` (début ≤ date < fin).
    func current(at date: Date = Date()) -> EpgProgramme? {
        programmes.first { p in
            guard let start = p.start, let end = p.end else { return false }
            return start <= date && date < end
        }
    }

    /// Prochain programme à débuter strictement après `date`.
    func next(at date: Date = Date()) -> EpgProgramme? {
        programmes.first { ($0.start ?? .distantPast) > date }
    }

    /// Progression (0…1) du programme dans sa plage à `date`. `nil` si plage inconnue/nulle.
    func progress(of programme: EpgProgramme, at date: Date = Date()) -> Double? {
        guard let start = programme.start, let end = programme.end else { return nil }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return nil }
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }
}
