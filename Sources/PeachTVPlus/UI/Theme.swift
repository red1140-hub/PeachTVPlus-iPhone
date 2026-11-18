import SwiftUI

/// Palette **néon** de PeachTV+ (jaune → orange → rouge sur **noir OLED**), jumelle du thème
/// Android (mode sombre forcé, reprise du logo pêche). Tokens **sémantiques** réutilisés par
/// tous les écrans — on ne met **jamais** une couleur en dur ailleurs, on passe par `Theme`.
enum Theme {

    /// Fond OLED noir pur.
    static let background = Color.black

    // Néons de la marque (teintes du logo).
    static let neonYellow = Color(red: 1.00, green: 0.80, blue: 0.00)   // #FFCC00
    static let neonOrange = Color(red: 1.00, green: 0.47, blue: 0.00)   // #FF7800
    static let neonRed    = Color(red: 0.95, green: 0.16, blue: 0.16)   // #F22A2A

    /// Accent principal (onglet actif, boutons) = orange néon.
    static let accent = neonOrange

    // Tokens sémantiques.
    static let liveNow      = neonRed       // pastille « en direct »
    static let ratingStar   = neonYellow    // étoiles de note
    static let downloadDone  = neonYellow   // téléchargement terminé
    static let archiveBadge  = neonOrange   // badge rattrapage disponible

    /// Dégradé de marque (titres, bandeaux, accents).
    static let brandGradient = LinearGradient(
        colors: [neonYellow, neonOrange, neonRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
