# PeachTV+ iOS — Système de design SwiftUI

> Design system **actionnable** pour l'implémentation SwiftUI (jalon **M5**) de PeachTV+
> iOS/iPadOS. Porte le design system Android (`../mytv-player/docs/design-system.md`) et le
> comportement par écran faisant autorité (`../mytv-player/CLAUDE.md` § « Spécification par
> écran »), traduits en idiomes Apple.
>
> **Cible** : iOS/iPadOS **17.0+**, iPhone **et** iPad, TestFlight personnel.
> **Thème** : **sombre OLED forcé** (noir vrai), lecteur **toujours** sombre.
> **Langue** : **français exclusivement** (aucun sélecteur). Tout texte via
> `String(localized:)` / catalogue `.strings` (`fr`) — jamais de littéral en dur.
> **Identité** : cinéma à la maison, accent **néon jaune → orange → rouge sur noir**.
>
> ⚠️ `../mytv-player` est une **référence en lecture seule**. Ce document ne décrit que la
> cible iOS. Les extraits Swift sont des **contrats de composant** (signatures + états), pas
> du code de production figé.

Table des matières
1. Tokens de couleur sémantiques & `Theme` injecté
2. Typographie (échelle mappée, chiffres tabulaires, Dynamic Type)
3. Grille & layout responsive (iPhone Compact ↔ iPad Expanded)
4. Catalogue de composants (signatures SwiftUI)
5. Accessibilité (cibles, VoiceOver, contraste, mouvement réduit)
6. États (skeleton/shimmer, vide, erreur)
7. Annexe : espacement, rayons, motion, iconographie SF Symbols

---

## 0. Principes directeurs (portés d'Android)

1. **Le contenu d'abord.** Chrome minimal ; affiches et logos portent la couleur, l'UI reste
   neutre. Un seul accent fort par zone.
2. **Sombre-first, jamais noir plat sauf là où il faut.** Surfaces en gris très sombres
   étagés ; le **noir vrai** (`#000000`) est réservé au fond derrière les affiches et au
   **lecteur plein écran**.
3. **Un geste = un sens.** Le swipe horizontal n'est consommé que dans le lecteur Direct
   (chaîne ±). Jamais sur les listes.
4. **Adaptatif, pas étiré.** L'iPad n'est pas un iPhone zoomé : `NavigationSplitView` +
   grilles plus denses, pas un contenu dilaté.

**Anti-patterns** : spinner plein écran sur une liste, emoji en guise d'icône, retrait de
l'anneau de focus, texte blanc posé directement sur une affiche claire sans scrim, couleur
seule porteuse de sens.

---

## 1. Tokens de couleur sémantiques & `Theme` injecté

### 1.1 Palette de base (hex, portés depuis `darkColorScheme()` Android)

PeachTV+ remplace l'accent **rouge-lecture** d'Android par l'**accent néon de marque**
(dégradé jaune → orange → rouge), conformément à `PORT-SPEC.md §8` et aux conventions iOS.
L'accent est un **dégradé**, pas une couleur plate : on définit ses trois arrêts + une
couleur « accent solide » de repli (orange) pour les éléments trop petits pour un dégradé
(anneaux fins, icônes 1 pt de trait).

| Token sémantique | Hex (sombre) | Rôle |
|---|---|---|
| `background` | `#000000` | Fond global OLED (noir vrai) |
| `surface` | `#0B0B0D` | Fond d'écran sous le contenu scrollable |
| `surfaceLow` | `#161415` | Barre d'onglets, feuilles basses, cartes au repos |
| `surface` (carte) | `#1B1819` | Cartes au repos (niveau 2) |
| `surfaceHigh` | `#262223` | Carte pressée / sélectionnée / focus |
| `surfaceHighest` | `#312D2E` | Menus, dialogues, popovers |
| `onSurface` | `#E7E1E2` | Texte principal |
| `onSurfaceVariant` | `#D7C1C2` | Texte secondaire, labels, icônes inactives (**gris**) |
| `outline` | `#9F8C8D` | Bordures 1 pt, séparateurs forts |
| `outlineVariant` | `#524345` | Diviseurs discrets, contour de carte |
| `accentStart` | `#FFC24D` | Néon — arrêt **jaune** (haut du dégradé) |
| `accentMid` | `#FF7A2F` | Néon — arrêt **orange** (= accent solide de repli) |
| `accentEnd` | `#FF3B30` | Néon — arrêt **rouge** (bas du dégradé) |
| `onAccent` | `#1A0A00` | Texte/icône sur une surface accent |
| `scrim` | `#000000` | Fond modal / dégradés lecteur (à alpha) |

> **Icône active = gris → jaune/orangé.** L'état inactif d'un onglet utilise
> `onSurfaceVariant` ; l'état actif utilise l'accent (dégradé pour le glyphe si possible,
> sinon `accentMid`). C'est la règle non négociable de `CLAUDE.md` Android.

### 1.2 Tokens sémantiques custom (hors palette de base)

| Token | Hex (sombre) | Usage |
|---|---|---|
| `downloadIdle` | `#D7C1C2` | Bouton télécharger au repos (= onSurfaceVariant) |
| `downloadQueued` | `#FFB95C` | En file d'attente (ambre) |
| `downloadProgress` | `#5AA9FF` | Anneau/barre de progression (bleu, se distingue de l'accent) |
| `downloadPaused` | `#FFB95C` | En pause |
| `downloadDone` | `#67DD8F` | Terminé / disponible hors-ligne |
| `onDownloadDone` | `#00391C` | Glyphe sur pastille « terminé » |
| `downloadError` | `#FFB4AB` | Échec |
| `liveNow` | `#FF3B30` | Pastille « EN DIRECT » (= accentEnd) |
| `ratingStar` | `#FFC24D` | Étoiles de note (= accentStart) |
| `success` | `#67DD8F` | Confirmations |
| `warning` | `#FFB95C` | Data cellulaire, abonnement proche expiration |
| `info` | `#5AA9FF` | Bannières d'info |

> **Pourquoi `downloadProgress` en bleu et non en accent ?** L'accent néon code l'action
> principale (Lire, sélection) ; la progression de téléchargement doit se lire comme un
> canal distinct, sinon l'écran Téléchargements devient une mer orange illisible. Choix
> hérité d'Android (`downloadProgress = #5AA9FF`).

### 1.3 Le `Theme` : `Color` SwiftUI injecté via `EnvironmentValues`

On n'utilise **pas** un Asset Catalog avec variantes clair/sombre (le thème est forcé
sombre) : un `struct` de tokens injecté par `EnvironmentValues` reste testable, snapshotable
et explicite.

```swift
import SwiftUI

/// Jeton de couleur de marque. Toutes les couleurs de l'app passent par ici —
/// aucun `Color(.red)` / `Color(hex:)` en dur dans les vues.
struct PeachTheme: Sendable {
    // Surfaces
    let background: Color
    let surface: Color
    let surfaceLow: Color
    let surfaceCard: Color
    let surfaceHigh: Color
    let surfaceHighest: Color
    // Texte & lignes
    let onSurface: Color
    let onSurfaceVariant: Color
    let outline: Color
    let outlineVariant: Color
    // Accent néon (dégradé)
    let accentStart: Color   // jaune
    let accentMid: Color     // orange (repli solide)
    let accentEnd: Color     // rouge
    let onAccent: Color
    let scrim: Color
    // Sémantiques custom
    let downloadIdle, downloadQueued, downloadProgress: Color
    let downloadPaused, downloadDone, onDownloadDone, downloadError: Color
    let liveNow, ratingStar, success, warning, info: Color

    /// Dégradé néon de marque (coin haut → bas). L'ordre jaune→orange→rouge est fixe.
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentMid, accentEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static let darkOLED = PeachTheme(
        background: Color(hex: 0x000000), surface: Color(hex: 0x0B0B0D),
        surfaceLow: Color(hex: 0x161415), surfaceCard: Color(hex: 0x1B1819),
        surfaceHigh: Color(hex: 0x262223), surfaceHighest: Color(hex: 0x312D2E),
        onSurface: Color(hex: 0xE7E1E2), onSurfaceVariant: Color(hex: 0xD7C1C2),
        outline: Color(hex: 0x9F8C8D), outlineVariant: Color(hex: 0x524345),
        accentStart: Color(hex: 0xFFC24D), accentMid: Color(hex: 0xFF7A2F),
        accentEnd: Color(hex: 0xFF3B30), onAccent: Color(hex: 0x1A0A00),
        scrim: Color(hex: 0x000000),
        downloadIdle: Color(hex: 0xD7C1C2), downloadQueued: Color(hex: 0xFFB95C),
        downloadProgress: Color(hex: 0x5AA9FF), downloadPaused: Color(hex: 0xFFB95C),
        downloadDone: Color(hex: 0x67DD8F), onDownloadDone: Color(hex: 0x00391C),
        downloadError: Color(hex: 0xFFB4AB), liveNow: Color(hex: 0xFF3B30),
        ratingStar: Color(hex: 0xFFC24D), success: Color(hex: 0x67DD8F),
        warning: Color(hex: 0xFFB95C), info: Color(hex: 0x5AA9FF)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// Injection via EnvironmentValues (iOS 17 : @Entry simplifie, mais on reste explicite).
private struct PeachThemeKey: EnvironmentKey {
    static let defaultValue: PeachTheme = .darkOLED
}
extension EnvironmentValues {
    var theme: PeachTheme {
        get { self[PeachThemeKey.self] }
        set { self[PeachThemeKey.self] = newValue }
    }
}
```

**Forçage du sombre + lecteur toujours sombre.** À la racine de l'app :

```swift
@main
struct PeachTVPlusApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.theme, .darkOLED)
                .preferredColorScheme(.dark)        // dark forcé sur tout l'arbre
                .tint(PeachTheme.darkOLED.accentMid) // teinte système = orange de repli
                .background(PeachTheme.darkOLED.background.ignoresSafeArea())
        }
    }
}
```

> Le lecteur plein écran applique **en plus** `.colorScheme(.dark)` localement et pose son
> fond sur `theme.background` (noir vrai) : même si un futur mode clair était ajouté, la
> vidéo ne s'y adapterait jamais (règle Android).

**Dégradé scrim affiche → texte** (lisibilité du titre quel que soit le poster) :

```swift
extension LinearGradient {
    /// Scrim vertical posé sous un titre en overlay sur une affiche.
    static func posterScrim(_ scrim: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.40),
            .init(color: scrim.opacity(0.85), location: 1.0)
        ], startPoint: .top, endPoint: .bottom)
    }
}
```

---

## 2. Typographie

**Police** : **SF Pro** (système). On ne charge aucune police personnalisée — SF est premium,
dense et parfaitement lisible en petit corps sur fond noir ; elle hérite gratuitement de
**Dynamic Type**, du gras sémantique et de l'optimisation OLED. (Android utilisait Inter pour
les mêmes raisons ; SF est l'équivalent natif.)

**Chiffres tabulaires** obligatoires pour tout ce qui change au fil du temps ou s'aligne en
colonne : minuteurs lecteur (`12:34`), pourcentages (`47 %`), tailles (`1,2 Go`), timeline
EPG. On applique `.monospacedDigit()`.

### 2.1 Échelle de type mappée (rôle → `Font.TextStyle`)

On s'appuie sur les `TextStyle` natifs pour que **Dynamic Type** fonctionne sans table de
tailles figée. Le mapping depuis l'échelle Material d'Android :

| Rôle PeachTV+ | `Font` SwiftUI | ≈ taille défaut | Emploi |
|---|---|---|---|
| `displayMedium` | `.largeTitle` poids `.bold` | 34 pt | Titre hero iPad |
| `displaySmall` | `.title` poids `.bold` | 28 pt | Titre hero iPhone |
| `headlineLarge` | `.title` poids `.semibold` | 28 pt | Titre d'écran de détail (iPad) |
| `headlineMedium` | `.title2` poids `.semibold` | 22 pt | Titre de film/série (détail) |
| `headlineSmall` | `.title3` poids `.semibold` | 20 pt | Titres de section / rail |
| `titleLarge` | `.title3` | 20 pt | Barre de navigation, titres de dialogue |
| `titleMedium` | `.headline` | 17 pt | Titre de carte, nom de chaîne |
| `titleSmall` | `.subheadline` poids `.medium` | 15 pt | Libellés d'onglet, sous-titres de carte |
| `bodyLarge` | `.body` | 17 pt | Synopsis, corps de texte |
| `bodyMedium` | `.subheadline` | 15 pt | Description secondaire, EPG |
| `bodySmall` | `.footnote` | 13 pt | Méta (année · durée · qualité) — **plancher** |
| `labelLarge` | `.callout` poids `.semibold` | 16 pt | Texte de bouton |
| `labelMedium` | `.caption` poids `.semibold` | 12 pt | Chips, badges |
| `labelSmall` | `.caption2` poids `.semibold` | 11 pt | Micro-badges (HD/4K) **uniquement** |

```swift
extension Font {
    static let pDisplaySmall  = Font.title.weight(.bold)
    static let pHeadlineMedium = Font.title2.weight(.semibold)
    static let pHeadlineSmall = Font.title3.weight(.semibold)
    static let pTitleMedium   = Font.headline
    static let pTitleSmall    = Font.subheadline.weight(.medium)
    static let pBodyLarge     = Font.body
    static let pBodyMedium    = Font.subheadline
    static let pBodySmall     = Font.footnote
    static let pLabelLarge    = Font.callout.weight(.semibold)
    static let pLabelMedium   = Font.caption.weight(.semibold)
    static let pBadge         = Font.caption2.weight(.bold)
}

// Exemple : un minuteur de lecteur, chiffres tabulaires.
Text(elapsed.formattedHMS)
    .font(.pBodyMedium)
    .monospacedDigit()
    .foregroundStyle(theme.onSurface)
```

**Règles** : corps minimum 13 pt (footnote) pour la méta non essentielle ; `lineLimit(2)` +
`truncationMode(.tail)` sur les titres de carte ; **ne jamais** figer une taille en points
pour du texte lisible (laisser Dynamic Type agir) ; plafonner `dynamicTypeSize` à
`...DynamicTypeSize.accessibility3` **uniquement** dans le lecteur et les grilles denses pour
éviter que l'UI de contrôle n'explose (le corps de texte, lui, n'est jamais plafonné).

```swift
// Dans la grille d'affiches et les contrôles lecteur seulement :
.dynamicTypeSize(...DynamicTypeSize.accessibility3)
```

---

## 3. Grille & layout responsive

### 3.1 Classes de taille → structure de navigation

Le pivot est `horizontalSizeClass` (+ `verticalSizeClass` pour le cas iPhone paysage bas).

| Contexte | `horizontalSizeClass` | Navigation 1er niveau | Détail |
|---|---|---|---|
| **iPhone portrait / paysage** | `.compact` | `TabView` (barre du bas, icônes seules) + `NavigationStack` par onglet | Pile (push) |
| **iPad (plein écran, split 1/2)** | `.regular` | `NavigationSplitView` (sidebar + contenu + détail) | Volet détail |

```swift
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if hSize == .regular {
                PeachSplitView()          // iPad : sidebar + contenu + détail
            } else {
                PeachTabView()            // iPhone : barre d'onglets du bas
            }
        }
        .background(theme.background.ignoresSafeArea())
    }
}
```

**iPhone — `TabView` (icônes seules, actif en accent).** Cinq destinations
(`PORT-SPEC.md §8`) : Accueil (Direct/Films/Séries en onglets internes), Recherche, Favoris,
Téléchargements (badge = nb en cours), Réglages.

```swift
struct PeachTabView: View {
    @Environment(\.theme) private var theme
    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeScreen() }
                .tabItem { Label("Accueil", systemImage: "house.fill") }.tag(Tab.home)
            NavigationStack { SearchScreen() }
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }.tag(Tab.search)
            NavigationStack { FavoritesScreen() }
                .tabItem { Label("Favoris", systemImage: "star.fill") }.tag(Tab.favorites)
            NavigationStack { DownloadsScreen() }
                .tabItem { Label("Téléchargements", systemImage: "arrow.down.circle.fill") }
                .badge(activeDownloads)          // nb en cours
                .tag(Tab.downloads)
            NavigationStack { SettingsScreen() }
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }.tag(Tab.settings)
        }
        .tint(theme.accentMid)                   // onglet actif = orange (icône + label)
    }
}
```

> **Label des onglets** : SwiftUI exige un titre sur `tabItem` (lu par VoiceOver). Pour
> respecter « icônes seules » visuellement sur iPhone, on garde le `Label` complet — iOS
> affiche icône **et** petit titre sous la barre ; c'est l'idiome Apple et c'est accessible.
> (La spec Android « tout en icônes » visait à ne pas surcharger ; sur iOS la barre système
> est déjà fine et le titre minuscule est attendu par l'utilisateur.)

**iPad — `NavigationSplitView`.** Sidebar = destinations 1er niveau ; colonne contenu =
liste (catégorie / grille) ; colonne détail = fiche film ou lecteur.

```swift
struct PeachSplitView: View {
    @State private var dest: Tab? = .home
    @State private var selectedItem: CatalogItem?

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $dest) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationTitle("PeachTV+")
        } content: {
            CatalogColumn(dest: dest, selection: $selectedItem)   // grille / liste
        } detail: {
            if let item = selectedItem { DetailScreen(item: item) }
            else { EmptyDetailPlaceholder() }                     // état vide du volet
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

### 3.2 Grille d'affiches adaptative (2:3)

Règle produit (`CLAUDE.md` Android /Films-Séries) : **3 pochettes de large en portrait
téléphone**, **plus** en paysage/iPad, proportionnel à la largeur. On n'utilise pas un nombre
de colonnes figé : on calcule dans un `GeometryReader` / `containerRelativeFrame`, avec les
seuils d'Android (`CatalogContent`).

```swift
/// Colonnes d'affiches selon la largeur disponible (porté de CatalogContent Android) :
/// < 600 → 3, < 840 → 4, sinon largeur/170 borné à 5…8.
func posterColumns(for width: CGFloat) -> Int {
    switch width {
    case ..<600:  return 3
    case ..<840:  return 4
    default:      return min(8, max(5, Int(width / 170)))
    }
}

struct PosterGrid: View {
    let items: [CatalogItem]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let cols = posterColumns(for: geo.size.width)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: cols)
            ScrollView {
                // « Reprendre la lecture » en tête, défile AVEC la grille (règle Android).
                LazyVGrid(columns: columns, spacing: 12) {
                    Section { ForEach(items) { PosterCard(item: $0) } }
                }
                .padding(.horizontal, hMargin(geo.size.width))   // 16 → 24
            }
        }
    }
}
```

- **Aspect-ratio canonique** : affiche **2:3**, vignette VOD large **16:9**, logo chaîne
  **1:1** (`ContentScale.Fit`), backdrop/hero **16:9** (21:9 recadré en hero iPad).
- Gouttière : **8 pt** (grilles denses d'affiches), **12 pt** (listes Live).

### 3.3 Marges & largeur de contenu lisible

```swift
func hMargin(_ width: CGFloat) -> CGFloat { width < 600 ? 16 : 24 }   // iPhone 16, iPad 24
```

- Marge latérale : **16 pt** (iPhone) → **24 pt** (iPad) → jusqu'à **32 pt** en très grand.
- **Largeur de contenu plafonnée** (formulaires, synopsis) même sur iPad : `frame(maxWidth:
  640)` pour Réglages/listes/login, `maxWidth: 840` pour les fiches (équivalent du
  `boundedContentWidth` Android). Un champ de login ne s'étire **jamais** sur toute la largeur
  d'un iPad.

```swift
extension View {
    func boundedContentWidth(_ max: CGFloat) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)   // centré, borné
    }
}
```

### 3.4 Masquage du chrome en plein écran

Règle Android `MainScreen` : **iPhone paysage bas** (hauteur < 480 dp) → barre du bas **et**
nav du haut disparaissent après ~600 ms ; **iPad** (reste haut en paysage) → nav **toujours
visible**. Équivalent iOS fondé sur `verticalSizeClass` (compact = iPhone paysage) :

```swift
struct ChromeVisibility: ViewModifier {
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.horizontalSizeClass) private var hSize
    let isPlaying: Bool

    /// iPhone en paysage (vSize == .compact ET hSize == .compact) = fenêtre basse → on cache.
    var autoHideChrome: Bool { vSize == .compact && hSize == .compact }

    func body(content: Content) -> some View {
        content
            .toolbar(autoHideChrome || isPlaying ? .hidden : .visible, for: .tabBar)
            .statusBarHidden(isPlaying)
            .persistentSystemOverlays(isPlaying ? .hidden : .automatic)
    }
}
```

Le **lecteur plein écran** présente en `fullScreenCover`, masque la barre d'onglets, le status
bar et les overlays système ; gère la zone sûre (encoche, Dynamic Island) via `safeAreaInset`
pour que les contrôles ne passent jamais sous l'encoche.

---

## 4. Catalogue de composants (signatures SwiftUI)

Chaque composant liste sa structure et ses **états** (repos / pressé / sélectionné /
désactivé / chargement / erreur) et son contrat d'accessibilité.

### 4.1 `LiveChannelCard`

Rangée horizontale : logo 1:1 (56 pt) + colonne texte + pastille à droite + barre de
progression du programme en cours.

```
[ logo 56 ]  N° · Nom de la chaîne              [EN DIRECT]
             ▸ 20:00  Le programme en cours      ──────── 62 %
             20:00–20:45 · Prochain : Journal
```

```swift
struct LiveChannelCard: View {
    let channel: LiveChannel
    let nowNext: EpgNowNext?
    var isPlaying: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(url: channel.logoURL, fallbackInitials: channel.initials)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(channel.number).font(.pBodySmall).foregroundStyle(theme.onSurfaceVariant)
                    Text(channel.name).font(.pTitleMedium).foregroundStyle(theme.onSurface)
                        .lineLimit(1)
                    Spacer()
                    if nowNext != nil { LiveBadge() }
                }
                if let n = nowNext {
                    Text(n.currentTitle).font(.pBodyMedium).lineLimit(1)
                        .foregroundStyle(theme.onSurface)
                    ProgramProgressBar(fraction: n.progress)       // 2 pt, accent
                    Text(n.scheduleLine).font(.pBodySmall)
                        .foregroundStyle(theme.onSurfaceVariant).lineLimit(1)
                } else {
                    Text("Programme indisponible").font(.pBodyMedium)
                        .foregroundStyle(theme.onSurfaceVariant)
                }
            }
        }
        .frame(minHeight: 72)                                     // cible tactile confortable
        .padding(12)
        .background(theme.surfaceLow, in: .rect(cornerRadius: 12))
        .overlay(alignment: .leading) {
            if isPlaying { theme.accentGradient.frame(width: 3) } // marqueur « en lecture »
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var s = "Chaîne \(channel.name)"
        if let n = nowNext { s += ", en cours : \(n.currentTitle)" }
        return s
    }
}
```

- **Nom de chaîne qui défile** (règle Direct) : sur la colonne de gauche de la grille EPG, on
  remplace `lineLimit(1)` par un marquee maison (`MarqueeText`) — voir §4.5.
- États : repos `surfaceLow` ; pressé → `surfaceHigh` + léger `scaleEffect(0.98)` ; en lecture
  → barre d'accent 3 pt à gauche + (optionnel) équaliseur 3 barres ; logo en chargement →
  shimmer sur le carré.

### 4.2 `PosterCard` (overlays qualité / hors-ligne / reprise)

Affiche 2:3, rayon 12 pt, titre **sous** l'affiche (ou en overlay sur scrim pour « à la
une »). Overlays : badge qualité haut-droit, coche hors-ligne bas-droit, barre de reprise en
bas.

```swift
struct PosterCard: View {
    let item: CatalogItem          // titre, affiche, qualité, isDownloaded, resumeFraction
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.posterURL)                     // Nuke LazyImage, 2:3
                .aspectRatio(2/3, contentMode: .fill)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) { QualityBadge(item.quality) }     // HD/4K
                .overlay(alignment: .bottomTrailing) {
                    if item.isDownloaded { OfflineCheck() }      // downloadDone
                }
                .overlay(alignment: .bottom) {
                    if let f = item.resumeFraction { ResumeBar(fraction: f) }        // accent
                }
            Text(item.title).font(.pTitleSmall).foregroundStyle(theme.onSurface)
                .lineLimit(2).frame(height: 36, alignment: .top)  // 2 lignes réservées = pas de CLS
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(.isButton)
    }

    private var a11y: String {
        var s = item.title
        if let q = item.quality { s += ", \(q)" }
        if item.isDownloaded { s += ", disponible hors-ligne" }
        if item.resumeFraction != nil { s += ", reprise possible" }
        return s
    }
}
```

- États : repos ; pressé → `scaleEffect(0.97)` + overlay léger ; **sélectionné** (sélection
  multiple de téléchargement) → bordure accent 2 pt + coche ; chargement → placeholder 2:3
  shimmer ; image cassée → fond `surfaceCard` + icône `film` + titre (cache négatif Nuke).

### 4.3 `DownloadButton` — composant phare, 6 états

Cible **44×44 pt** (glyphe ~24), un seul composant qui transite entre tous les états, label
VoiceOver dynamique. Modélise `DownloadUiState` du port (`PORT-SPEC.md §6`).

```swift
enum DownloadState: Equatable {
    case notDownloaded
    case queued
    case downloading(progress: Double)   // 0…1
    case paused(progress: Double)
    case completed
    case failed
}

struct DownloadButton: View {
    let state: DownloadState
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) { glyph }
            .frame(width: 44, height: 44)                 // cible tactile
            .contentShape(.rect)
            .accessibilityLabel(a11yLabel)
            .accessibilityValue(a11yValue)                // % annoncé séparément
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(theme.downloadIdle)
        case .queued:
            Image(systemName: "hourglass.circle")
                .foregroundStyle(theme.downloadQueued)
        case .downloading(let p):
            ZStack {
                Circle().stroke(theme.outlineVariant, lineWidth: 3)
                Circle().trim(from: 0, to: p)             // anneau DÉTERMINÉ
                    .stroke(theme.downloadProgress, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: p)
                RoundedRectangle(cornerRadius: 2)         // carré « stop/pause »
                    .fill(theme.downloadProgress).frame(width: 10, height: 10)
            }.padding(8)
        case .paused(let p):
            ZStack {
                Circle().trim(from: 0, to: p)
                    .stroke(theme.downloadPaused, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "play.fill").font(.caption).foregroundStyle(theme.downloadPaused)
            }.padding(8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.onDownloadDone, theme.downloadDone)   // glyphe / cercle
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.downloadError)
        }
    }
    // ... a11yLabel / a11yValue : voir tableau ci-dessous.
}
```

| État | Couleur | Icône / indicateur | Forme | Label VoiceOver | Valeur VoiceOver | Tap |
|---|---|---|---|---|---|---|
| **Non téléchargé** | `downloadIdle` | `arrow.down.circle` (contour) | cercle contour | « Télécharger {titre} » | — | lance / met en file |
| **En file** | `downloadQueued` | `hourglass.circle` | cercle + sablier | « En file d'attente, {titre} » | — | ouvrir file / annuler |
| **En cours** | `downloadProgress` | anneau **déterminé** + carré stop | anneau + carré 10 pt | « Téléchargement de {titre} » | « {pct} pour cent » | met en pause |
| **En pause** | `downloadPaused` | anneau figé + `play.fill` | anneau partiel + triangle | « En pause, {titre} » | « {pct} pour cent » | reprend |
| **Terminé** | `downloadDone` / `onDownloadDone` | `checkmark.circle.fill` | cercle plein + coche | « Téléchargé, disponible hors-ligne » | — | menu (lire / supprimer) |
| **Erreur** | `downloadError` | `exclamationmark.triangle.fill` | triangle | « Échec du téléchargement de {titre} » | — | réessaie |

- Phase « connexion » (avant le 1er octet) = anneau **indéterminé** bref, puis bascule en
  déterminé dès que le % est connu.
- Transition 99 % → terminé : petit « pop » de la coche (`scaleEffect` 0.8 → 1.0, **désactivé
  si `reduceMotion`**).
- **Variante longue** (écran détail) : `DownloadBarButton` plein largeur « Télécharger
  (1,2 Go) » qui, en cours, devient une **barre de progression linéaire** (% + taille + bouton
  pause/annuler), et en terminé « Téléchargé · Supprimer ».
- **Niveau série** : « Télécharger la saison » (file groupée) en tête ; chaque épisode garde
  son propre `DownloadButton`.

### 4.4 Grille / guide EPG (`LiveEpgGrid`)

Grille façon téléviseur : **colonne de chaînes figée** à gauche + **timeline 12 h**
scrollable horizontalement, **en-têtes collants** (jour + heures), barre « maintenant ».
Clic sur une case → détails complets + lien IMDb.

```swift
struct LiveEpgGrid: View {
    let channels: [LiveChannel]
    let programmes: [ChannelID: [EpgProgramme]]
    let onSlotTap: (EpgProgramme) -> Void
    @Environment(\.theme) private var theme

    private let pxPerMinute: CGFloat = 4           // 12 h = 2880 pt de large
    private let rowHeight: CGFloat = 64
    private let channelColWidth: CGFloat = 96

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            // En-tête d'heures collant en haut + colonne chaînes collante à gauche :
            // on superpose deux ScrollView synchronisées, ou on utilise pinnedViews.
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(channels) { ch in
                        HStack(spacing: 0) {
                            ChannelRowHeader(channel: ch)       // figée (voir note)
                                .frame(width: channelColWidth, height: rowHeight)
                            ForEach(programmes[ch.id] ?? []) { prog in
                                EpgSlot(prog: prog, pxPerMinute: pxPerMinute)
                                    .onTapGesture { onSlotTap(prog) }
                            }
                        }
                    }
                } header: {
                    EpgTimeAxis(pxPerMinute: pxPerMinute)        // en-tête heures collant
                        .background(theme.surfaceLow)
                }
            }
            .overlay(alignment: .topLeading) { NowIndicator() }  // ligne « maintenant »
        }
    }
}
```

> **Figer la colonne + l'en-tête.** iOS 17 n'a pas de « frozen column » natif. Deux approches :
> (a) `pinnedViews: [.sectionHeaders]` pour l'axe temporel + une colonne chaînes posée en
> `overlay(alignment: .leading)` sur un `ScrollViewReader` dont on lit l'offset vertical pour
> la garder synchro ; (b) plus simple et robuste : deux `ScrollView` imbriquées dont on
> synchronise le `contentOffset` via `ScrollViewReader`/`onScrollGeometryChange` (iOS 18) ou un
> `GeometryReader` (iOS 17). On retient (b), testable par snapshot.

Le **guide du bas** dans `LivePlayerScreen` (en-tête de jour collant, clic case → mêmes
détails + IMDb) réutilise `EpgSlot` et `onSlotTap`.

### 4.5 `MarqueeText` (nom de chaîne qui défile)

```swift
/// Défilement horizontal doux d'un texte trop long (équivalent basicMarquee Android).
/// Respecte Réduire les animations : affiche alors le texte tronqué, sans défilement.
struct MarqueeText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // ... mesure la largeur, anime l'offset en boucle si texte > conteneur.
}
```

### 4.6 `StorageDonut` / `StorageBar`

Deux représentations du stockage (Réglages). `StorageBar` : barre pleine largeur, part
**utilisée en accent** (jaune-orangé), reste **libre en `surfaceVariant`** (règle Réglages
Android). `StorageDonut` : anneau, % au format `Locale(identifier: "fr_FR")`, centre vide.

```swift
struct StorageBar: View {
    let usedBytes: Int64, totalBytes: Int64
    @Environment(\.theme) private var theme
    private var fraction: Double { totalBytes > 0 ? Double(usedBytes)/Double(totalBytes) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.outlineVariant)                  // libre (foncé)
                    Capsule().fill(theme.accentGradient)                  // utilisé (accent)
                        .frame(width: geo.size.width * fraction)
                }
            }.frame(height: 12)
            HStack {
                Label(usedBytes.formattedFR, systemImage: "internaldrive").font(.pBodySmall)
                Spacer()
                Text("\(freeBytes.formattedFR) libre").font(.pBodySmall)
            }.foregroundStyle(theme.onSurfaceVariant)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stockage : \(usedBytes.formattedFR) utilisés sur \(totalBytes.formattedFR)")
    }
}

struct StorageDonut: View {
    let usedBytes: Int64, totalBytes: Int64
    @Environment(\.theme) private var theme
    private var fraction: Double { totalBytes > 0 ? Double(usedBytes)/Double(totalBytes) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(theme.outlineVariant, lineWidth: 14)
            Circle().trim(from: 0, to: fraction)
                .stroke(theme.accentGradient, style: .init(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.pHeadlineSmall).monospacedDigit().foregroundStyle(theme.onSurface)
        }
    }
}
```

### 4.7 Contrôles du lecteur plein écran (`PlayerControlsOverlay`)

Fond **toujours noir**, chrome en overlay sur dégradés scrim, **auto-masquage ~7 s** (suspendu
pendant un drag de barre ou quand le sélecteur de pistes est ouvert), réapparition au tap. **Un
seul** gestionnaire de gestes (leçon Android) : tap = bascule contrôles ; drag vertical
**droite = volume / gauche = luminosité** (actif masqué **ou** affiché) ; drag horizontal =
**chaîne ±** (Direct seulement).

```swift
struct PlayerControlsOverlay<Bottom: View>: View {
    let title: String
    let subtitle: String?               // chaîne / S01E04
    let isLive: Bool
    @Binding var isVisible: Bool
    @ViewBuilder let bottomBar: () -> Bottom   // barre propre à l'écran (scrub VOD / rattrapage Live)

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if isVisible {
                LinearGradient(colors: [theme.scrim.opacity(0.7), .clear],
                               startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
                VStack {
                    topBar                         // ← retour, titre, cast/AirPlay, CC, qualité
                    Spacer()
                    centerTransport                // VOD : −10s / play 64pt / +10s ; Live : EN DIRECT
                    Spacer()
                    bottomBar()
                }
                .padding()
                .transition(.opacity)
            }
        }
        .colorScheme(.dark)                        // lecteur toujours sombre
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}
```

Gestionnaire de gestes unique (arbitre), monté uniquement en plein écran :

```swift
struct PlayerGestures: ViewModifier {
    let onTap: () -> Void
    let onVolume: (CGFloat) -> Void        // drag vertical, moitié droite
    let onBrightness: (CGFloat) -> Void    // drag vertical, moitié gauche
    let onChannelSwipe: ((Int) -> Void)?   // drag horizontal, Direct seulement (nil sinon)

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(                       // UN SEUL gesture composite, pas d'empilement
                ExclusiveGesture(
                    DragGesture(minimumDistance: 10),
                    TapGesture()
                ) // ... route selon l'axe dominant et la moitié d'écran
            )
    }
}
```

- **Live vs VOD** : Live = bouton « EN DIRECT » + barre rattrapage (« revenir au début » /
  « au direct ») + **`ChannelBadge` logo+nom 5 s** au changement de chaîne ; VOD = scrub
  complet + recul 1 min / avance 10 s + sélecteur **langue/sous-titres** + reprise.
- États : buffering → spinner central + « Mise en mémoire tampon… » ; erreur de flux → carte
  centrale (titre court + cause + **une** action : Réessayer / Changer de qualité / Vérifier
  l'abonnement — `PORT-SPEC.md §7.4`) ; verrouillé → contrôles masqués sauf cadenas ; fin de
  VOD → « À suivre » (compte à rebours annulable).

### 4.8 `ChannelBadge` (logo + nom 5 s, Direct)

```swift
struct ChannelBadge: View {   // coin inférieur gauche, 5 s au changement de chaîne
    let logoURL: URL?, name: String
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            ChannelLogo(url: logoURL, fallbackInitials: name.initials).frame(width: 40, height: 40)
            Text(name).font(.pTitleMedium).foregroundStyle(.white).lineLimit(1)
        }
        .padding(10)
        .background(theme.scrim.opacity(0.6), in: .capsule)
        .transition(.opacity)
    }
}
```

### 4.9 `AuthTextField` & `PlaylistForm`

`AuthTextField` : champ de connexion avec label flottant visible, états repos/focus/erreur/
chargement, bascule œil pour le mot de passe.

```swift
struct AuthTextField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var error: String? = nil
    var keyboard: UIKeyboardType = .default
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.pLabelMedium)
                .foregroundStyle(error != nil ? theme.downloadError
                                 : focused ? theme.accentMid : theme.onSurfaceVariant)
            HStack {
                Group {
                    if isSecure && !reveal { SecureField("", text: $text) }
                    else { TextField("", text: $text) }
                }
                .focused($focused)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if isSecure {
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(reveal ? "Masquer le mot de passe" : "Afficher le mot de passe")
                }
            }
            .padding(12)
            .background(theme.surfaceCard, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(error != nil ? theme.downloadError
                        : focused ? theme.accentMid : theme.outline,
                        lineWidth: focused || error != nil ? 2 : 1))
            if let error { Text(error).font(.pBodySmall).foregroundStyle(theme.downloadError) }
        }
    }
}
```

`PlaylistForm` (formulaire partagé login + dialogue Réglages « ajouter une liste ») : trois
`AuthTextField` (serveur `.URL`, utilisateur, mot de passe), bouton « Se connecter » plein
accent, désactivé tant que les champs requis sont vides, helper « ex. http://mon-serveur:8080 »,
**consentement HTTP** (bascule explicite avant premier envoi d'identifiants en clair), masquage
d'aperçu au passage en arrière-plan (`redacted` sur `scenePhase == .inactive`).

### 4.10 Bouton d'action principal, chips, pastille Live

```swift
struct PeachPrimaryButton: View {   // « Lecture », « Se connecter »
    let title: String; let systemImage: String?; let action: () -> Void
    @Environment(\.theme) private var theme; @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack { if let s = systemImage { Image(systemName: s) }; Text(title).font(.pLabelLarge) }
                .frame(maxWidth: .infinity).frame(height: 52)
                .foregroundStyle(theme.onAccent)
                .background(enabled ? AnyShapeStyle(theme.accentGradient)
                                    : AnyShapeStyle(theme.surfaceHigh),
                            in: .rect(cornerRadius: 12))
        }
        .accessibilityAddTraits(.isButton)
    }
}

struct LiveBadge: View {            // pastille « EN DIRECT », point + texte (jamais le point seul)
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(theme.liveNow).frame(width: 6, height: 6)   // clignote sauf reduceMotion
            Text("EN DIRECT").font(.pBadge)
        }
        .foregroundStyle(theme.liveNow)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(theme.liveNow.opacity(0.15), in: .capsule)
    }
}
```

Chips de filtre/catégorie : `.capsule`, sélectionné = fond accent léger + texte accent ;
rangée scrollable collante sous la barre.

---

## 5. Accessibilité

**Cibles tactiles** : minimum **44×44 pt** (HIG) pour tout élément interactif, même quand le
glyphe fait 24 pt → `frame(width: 44, height: 44)` + `contentShape(.rect)`. Espacement ≥ 8 pt
entre cibles adjacentes.

**VoiceOver**
- `accessibilityLabel` sur toute icône porteuse de sens ; `accessibilityHidden(true)` sur le
  décoratif.
- **Groupement** des cartes : `accessibilityElement(children: .combine)` + label composé
  (`LiveChannelCard`, `PosterCard` ci-dessus).
- **`DownloadButton`** : label = l'action/état, **`accessibilityValue`** = le pourcentage,
  annoncé séparément et mis à jour en continu (table §4.3).
- **Live** : « Chaîne X, en cours : programme Y ». **Épisodes** : « Saison 1 épisode 4, titre,
  téléchargé / non téléchargé ».
- Ordre de lecture logique ; focus initial posé par écran (`@AccessibilityFocusState` : le
  champ de recherche à l'arrivée, play dans le lecteur).

**Contraste** : texte normal ≥ **4.5:1**, texte large/gras ≥ 3:1, éléments UI porteurs de sens
≥ 3:1. Les paires de tokens (`onSurface`/`surface`, `onAccent`/accent) respectent ces seuils.
Vérifier le texte sur affiches : **toujours** un scrim (`posterScrim`), jamais de blanc direct
sur image claire. **Jamais** de sens par la couleur seule (DL = couleur + icône + forme +
label ; Live = texte « EN DIRECT », pas qu'un point).

**Mouvement réduit** : `@Environment(\.accessibilityReduceMotion)` coupe le clignotement Live,
le « pop » de la coche DL, le marquee du nom de chaîne, le parallax du backdrop, l'auto-advance
« À suivre ».

**Dynamic Type** : tout en `TextStyle` natif ; plafond `accessibility3` **uniquement** dans le
lecteur et les grilles denses (§2). **Contenu serveur = données hostiles** : titres/EPG affichés
en `Text`, jamais interprétés ; images via Nuke bornées (taille/timeout/cache négatif).

**Masquage sensible en arrière-plan** (SHOULD sécurité) : overlay opaque sur les écrans login /
identifiants quand `scenePhase == .inactive` (évite le mot de passe dans l'aperçu multitâche).

---

## 6. États : chargement, vide, erreur

### 6.1 Skeleton / shimmer

Placeholders **aux dimensions finales** (réservent l'espace → pas de saut de layout), jamais un
spinner plein écran sur une liste.

```swift
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.08), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 2)
                    .offset(x: geo.size.width * phase)
            }
            .allowsHitTesting(false)
        )
        .onAppear { if !reduceMotion {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        } }
    }
}

struct PosterSkeleton: View {           // grille de placeholders 2:3
    @Environment(\.theme) private var theme
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(theme.surfaceCard)
            .aspectRatio(2/3, contentMode: .fit)
            .modifier(Shimmer())
            .accessibilityHidden(true)
    }
}
```

### 6.2 État vide

Icône monochrome (`onSurfaceVariant`) + titre (`titleMedium`) + sous-texte (`bodyMedium`) +
**CTA**. Composant unique réutilisable :

```swift
struct EmptyStateView: View {
    let symbol: String, title: String, message: String
    var ctaTitle: String? = nil, cta: (() -> Void)? = nil
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(theme.onSurfaceVariant)
            Text(title).font(.pTitleMedium).foregroundStyle(theme.onSurface)
            Text(message).font(.pBodyMedium).foregroundStyle(theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
            if let ctaTitle, let cta { PeachPrimaryButton(title: ctaTitle, systemImage: nil, action: cta)
                .frame(maxWidth: 280) }
        }
        .padding(32).boundedContentWidth(420)
    }
}
// Ex. Téléchargements vide :
// EmptyStateView(symbol: "arrow.down.circle", title: "Aucun téléchargement",
//   message: "Les films que vous téléchargez apparaîtront ici.",
//   ctaTitle: "Parcourir les films") { … }
```

### 6.3 État d'erreur (orienté solution)

Jamais de code brut/stacktrace. Titre court + cause probable + **une** action. Distinguer
hors-ligne (« Vous êtes hors-ligne — vos téléchargements restent disponibles ») de l'erreur
serveur (« Ce flux est indisponible »).

```swift
struct ErrorStateView: View {
    let title: String, cause: String, retryTitle: String, retry: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40))
                .foregroundStyle(theme.warning)
            Text(title).font(.pTitleMedium).foregroundStyle(theme.onSurface)
            Text(cause).font(.pBodyMedium).foregroundStyle(theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
            PeachPrimaryButton(title: retryTitle, systemImage: "arrow.clockwise", action: retry)
                .frame(maxWidth: 280)
        }
        .padding(32).boundedContentWidth(420)
    }
}
```

---

## 7. Annexe

### 7.1 Espacement, rayons, formes
- **Espacement** (base 4) : 4, 8, 12, 16, 24, 32, 48. Padding interne de carte = 12.
- **Rayons** : badge/chip 4 · bouton/champ 8 · carte (affiche, Live) 12 · feuille/dialogue 16 ·
  capsule (chips, pastille Live, avatar). Affiche = 12 pt ; hero full-bleed = 0.
- **Élévation par la surface, pas par l'ombre** (sombre-first) : repos `surfaceLow` →
  pressé/focus `surfaceHigh` → menus/dialogues `surfaceHighest`. Bordure 1 pt `outlineVariant`
  optionnelle sur les cartes.

### 7.2 Motion
- Micro-interactions 100–150 ms ; composant 200–300 ms ; transition d'écran 300–400 ms
  (sortie plus rapide que l'entrée). Contrôles lecteur : fade 200 ms.
- `matchedGeometryEffect` (affiche liste → détail) quand disponible, sinon fade.
- Tout respecte `accessibilityReduceMotion` (§5).

### 7.3 Iconographie — **SF Symbols** (jamais d'emoji)
`house.fill`, `magnifyingglass`, `star.fill`, `arrow.down.circle(.fill)`, `gearshape.fill`,
`play.fill`, `pause.fill`, `gobackward`, `goforward.10`, `livephoto`/`dot.radiowaves.left.and.right`,
`film`, `square.grid.2x2`, `airplayvideo`, `pip`, `captions.bubble`, `checkmark.circle.fill`,
`exclamationmark.triangle(.fill)`, `hourglass.circle`, `internaldrive`, `eye`/`eye.slash`,
`lock.fill`. Glyphes actifs = **accent** (dégradé si possible, sinon `accentMid`), inactifs =
`onSurfaceVariant`.

### 7.4 Récapitulatif d'implémentation SwiftUI
- `LazyVGrid` / `LazyVStack` / `List` (jamais `ScrollView` + `VStack` pour une liste longue) ;
  `id:` stable par item.
- Images : **Nuke** `LazyImage` avec downsampling à la taille cible, placeholder shimmer, cache
  négatif.
- Thème : `.environment(\.theme, .darkOLED)` + `.preferredColorScheme(.dark)` à la racine ; les
  vues lisent `@Environment(\.theme)`. **Aucune couleur en dur** hors `PeachTheme`.
- Lecteur : abstraction `VideoEngine` (AVPlayer HLS/mp4 + MobileVLCKit TS/HEVC/AC3) ; overlay
  et gestes = §4.7 ; fond `theme.background`, `.colorScheme(.dark)` local.
- Snapshotable : chaque composant se rend avec `.environment(\.theme, .darkOLED)` sans data
  réseau → `swift-snapshot-testing` (M6) couvre login, cartes, `DownloadButton` 6 états,
  lecteur, grille EPG.

---

*Fin de la spécification. Tokens, typographie, composants et patterns alignés sur le design
system Android (OLED cinéma, accent néon jaune→orange→rouge) et sur le comportement par écran
faisant autorité de `../mytv-player/CLAUDE.md`, traduits en idiomes SwiftUI/HIG (iOS 17+).*
