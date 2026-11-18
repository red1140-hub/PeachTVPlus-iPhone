import SwiftUI

/// Grille **adaptative** de pochettes — ~3 colonnes en portrait téléphone, davantage en paysage
/// et sur iPad (colonnes calculées par largeur minimale, idiome `LazyVGrid`). Réutilisée par les
/// écrans Films et Séries pour un rendu identique.
enum PosterGrid {
    static let columns = [GridItem(.adaptive(minimum: 108), spacing: 10)]
}

/// Pochette + titre (films & séries). Affiche distante via `AsyncImage` (aucune dépendance image
/// ajoutée pour l'instant ; ATS autorise le HTTP des panels). Repli néon sur fond sombre si
/// l'affiche manque ou échoue.
struct PosterCard: View {
    let title: String
    let posterURL: String?
    var rating: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.12))
                if let url = posterURL.flatMap({ URL(string: $0) }) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .empty:   ProgressView()
                        case .failure: placeholder
                        @unknown default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
                if let rating, rating > 0 {
                    ratingBadge(rating)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholder: some View {
        Image(systemName: "film").font(.title).foregroundStyle(Theme.accent)
    }

    private func ratingBadge(_ rating: Double) -> some View {
        VStack {
            HStack {
                Spacer()
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.ratingStar)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(6)
            }
            Spacer()
        }
    }
}

/// Vignette d'affiche simple (fiche détail) : remplit un cadre fixe, repli néon.
struct PosterThumb: View {
    let posterURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.12))
            if let url = posterURL.flatMap({ URL(string: $0) }) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "film").font(.title).foregroundStyle(Theme.accent)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
