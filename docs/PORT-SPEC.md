# PeachTV+ iOS — Spécification de portage (Android → iOS/iPadOS)

> Portage **natif Swift/SwiftUI** de l'app Android `../mytv-player` (**PeachTV+**), un
> client IPTV Xtream Codes avec téléchargement hors-ligne. Cible : **iPhone + iPad**,
> usage **personnel** (TestFlight), **iOS 17.0+**.
>
> **Source de vérité** du portage : récupère le contrat de l'app Android (features, data,
> sécurité, fiabilité, design) et fixe l'équivalent iOS de chaque brique. Toute l'équipe
> travaille à partir d'ici.
>
> **⚠️ `../mytv-player` est une référence EN LECTURE SEULE** — jamais modifiée.
> Dernière synchro sur l'état PeachTV+ v1.04 : **2026-11-12**.

---

## 0. Contraintes de pilotage

| Contrainte | Conséquence |
|---|---|
| **Développement sous Windows, aucun Mac** | On ne compile/exécute pas Xcode localement. Builds + tests sur **Mac cloud en CI** (GitHub Actions `macos-14`). Code **buildable sans intervention** : projet généré par XcodeGen depuis `project.yml`, dépendances SPM. |
| **Distribution personnelle (TestFlight)** | Pas de revue App Store (pour l'instant). TestFlight → **compte Apple Developer (99 $/an)** + **appareil physique** de l'utilisateur. Dépendances humaines signalées au bon moment. Archi tenue **App-Store-ready** pour un futur passage public. |
| **Pas de simulateur sous la main** | Vérification visuelle par **snapshot tests** et captures CI, pas par œil humain continu. |
| **Lecture MPEG-TS** | `AVPlayer` ne lit **pas** le MPEG-TS brut (`.ts` sans HLS). On embarque **MobileVLCKit** pour le TS et les codecs exotiques (HEVC/AC3). **Double moteur** `VideoEngine`. |
| **Monorepo sans remote** | Le dossier `PeachTV+_iPhone/` doit être poussé comme **dépôt GitHub autonome** (racine = ce dossier) pour activer la CI. Le `.github/workflows/ci.yml` n'a donc **pas** de `working-directory`. |
| **Nom avec « + »** | Dossier = `PeachTV+_iPhone` (demandé). Identifiant Xcode interne **sanitisé** : cible/scheme `PeachTVPlus`, bundle `com.peachtvplus.app`. Nom **affiché** = « PeachTV+ ». |

---

## 1. Périmètre fonctionnel — **parité complète** avec PeachTV+ Android v1.04

Tout ce qui suit est livré côté Android et doit être porté :

- **Connexion Xtream** : serveur + user + pass, normalisation d'URL, test réel contre
  `player_api.php`, HTTPS-first + **consentement** avant HTTP, champ URL vide au départ.
- **Listes de lecture MULTIPLES** : plusieurs abonnements Xtream, une liste **active**,
  ajouter/retirer/basculer. Changer de liste active = **vider le cache catalogue** mais
  **garder favoris + chaînes masquées** (isolés par liste). Voir §4.
- **Catalogue** : Live / Films / Séries, catégories, affiches, cache local, recherche globale
  (titre **et** acteur), favoris. Catégories par défaut : **« À l'affiche »** (Films/Séries),
  **« Québec »** (Direct), **« Favoris »** synthétique en tête du Direct.
- **EPG** : guide now/next + grille journalière façon téléviseur (colonne figée, timeline 12 h,
  en-têtes collants), barre de progression, détails de case + lien IMDb par titre.
- **Lecture** : lecteur Live (direct + rattrapage, pas de scrub libre en direct) et VOD
  (scrub, recul 1 min / avance 10 s, reprise), plein écran, **gestes** (volume/luminosité ;
  chaîne ± en Direct), sélecteur **langue audio / sous-titres** (VOD), badge logo+nom de
  chaîne 5 s au changement (Direct).
- **Détail film/série** : saisons → épisodes, métadonnées (`get_vod_info`/`get_series_info`).
- **Rattrapage (catch-up)** : timeshift depuis l'EPG (programmes avec archive) ; « revenir au
  début de la diffusion » / « revenir au direct ».
- **Téléchargement hors-ligne ⭐** (fonction phare) : films + épisodes, bouton **6 états**,
  écran « Disponible hors ligne » (sections Films / Séries), lecture 100 % locale, gestion de
  l'espace, bascule **« Wi-Fi uniquement »**. Voir §6.
- **Chaînes cachées** : appui long → cacher ; restauration (tout/individuel) dans Réglages.
- **Réglages** : liste de lecture (multi), **donut/barre de stockage**, identifiants (mot de
  passe révélé à la demande, auto-masqué), chaînes cachées, rafraîchir, **test de vitesse**
  (verdicts ton québécois), se déconnecter (= retirer la liste ; dernière liste = tout
  effacer, loi 25), journal de diagnostic.
- **Favoris** : sections **Direct → Films → Séries**.
- **Cast (Chromecast)** : Android l'a (Media3 CastPlayer + picker MediaRouter maison). iOS :
  **AirPlay natif d'abord** (couvre l'essentiel du besoin Apple), **Google Cast iOS SDK**
  ajouté ensuite (post-v1). Caster la version **HLS**, jamais le `.ts` brut.
- **Splash** : logo plein écran ~1 s au démarrage (via SwiftUI, éviter le double-splash).

Hors scope (comme Android) : sources MAC / portail Stalker (**Xtream uniquement**) ;
**Apple TV / tvOS** (téléphone + tablette seulement — envisageable plus tard, l'archi SwiftUI
le permet).

---

## 2. Choix techniques iOS (équivalences de stack)

| Besoin | Android (source) | iOS (cible) | Notes |
|---|---|---|---|
| Langage / UI | Kotlin + Compose + Material 3 | **Swift 5.10 + SwiftUI** (iOS 17) | `@Observable`, `NavigationStack`, `NavigationSplitView` (iPad) |
| Archi | MVVM + Repository, Hilt, Coroutines/Flow | **MVVM + Repository**, DI par composition (`AppContainer`), `async/await` + `AsyncStream` | Pas de framework DI lourd |
| Lecture | Media3 / ExoPlayer | **AVPlayer** (HLS/mp4) **+ MobileVLCKit** (TS/HEVC/AC3) | Abstraction `VideoEngine` qui route selon le format |
| Téléchargement | Media3 `DownloadManager`/`Service` | **`URLSession` `.background`** + reprise `resumeData` (HTTP Range) | Fichiers progressifs mp4/mkv/ts |
| Réseau | Retrofit + OkHttp + kotlinx.serialization | **`URLSession` + async/await + `Codable`** | Décodeur `FlexibleString` (int\|string) |
| Cache catalogue | Room + index | **GRDB.swift (SQLite) + FTS5** | Batch inserts, pagination, recherche FTS — mappe Room ~1:1 |
| Identifiants | Tink (AES-GCM) + AndroidKeyStore | **Keychain** (`...AfterFirstUnlockThisDeviceOnly`, non iCloud) | Chiffré au repos via Secure Enclave |
| Images | Coil | **Nuke** (`LazyImage`) | Downsampling, cache mémoire plafonné, cache négatif |
| Projet | Gradle | **XcodeGen** (`project.yml`) + **SPM** | `.xcodeproj` généré sur CI, 100 % texte sous Windows |
| CI | GitHub Actions (Linux, Android) | **GitHub Actions `macos-14`** + règles sécurité Linux ; TestFlight via Fastlane (M7) | |

### Dépendances SPM (par jalon)
- **M2** : `GRDB.swift` (cache SQLite + FTS5).
- **M3** : `MobileVLCKit` (TS/HEVC/AC3) + `Nuke`/`NukeUI` (images).
- **M6** : `swift-snapshot-testing` (tests visuels).
- **Post-v1** : `google-cast-sdk` (Chromecast). `Fastlane` = outil (pas SPM) pour TestFlight.

M0/M1 restent **sans dépendance externe** pour un premier CI vert fiable.

---

## 3. Contrat réseau Xtream (porté tel quel)

Endpoint unique `player_api.php` piloté par `action`. Serveur saisi à l'exécution →
**chaque appel construit une URL absolue** (`XtreamURLFactory`).

### 3.1 URLs
- `apiBase` = `{server}/player_api.php?username={enc}&password={enc}`
- `auth` = `apiBase` (sans `action`) → authentification + infos compte.
- `action(a, categoryId?)` = `apiBase&action={a}[&category_id={enc}]`.
- Actions : `get_live_categories`, `get_live_streams`, `get_vod_categories`,
  `get_vod_streams`, `get_series_categories`, `get_series`.
- Détail : `get_vod_info&vod_id=`, `get_series_info&series_id=`.
- EPG : `get_short_epg&stream_id=&limit=4`, `get_simple_data_table&stream_id=`.
- **Lecture** : Live `{server}/live/{user}/{pass}/{id}.ts` (ou `.m3u8` pour AirPlay/Cast) ;
  VOD `{server}/movie/{user}/{pass}/{id}.{ext}` ; série `{server}/series/{user}/{pass}/{epId}.{ext}`.
- **Catch-up** : `{server}/timeshift/{user}/{pass}/{durationMin}/{yyyy-MM-dd:HH-mm}/{id}.ts`
  (début en **fuseau local**).
- **Téléchargement** : variantes **sans identifiants** avec marqueur `__cred__` ; vrais
  identifiants **réinjectés à la volée** → l'URL persistée (et la clé de cache) **ne contient
  aucun secret**. Côté iOS : la tâche `URLSession` reçoit l'URL réelle en mémoire ; on
  **persiste** la forme `__cred__` et on réinjecte au (re)lancement. Voir §6.
- **Garde-fou d'hôte** (leçon v1.03) : un téléchargement d'une autre liste ne doit **jamais**
  recevoir les identifiants de la liste active (sinon fuite vers le mauvais serveur). Réinjecter
  uniquement si l'hôte de l'URL correspond à la liste propriétaire du téléchargement.

### 3.2 DTOs (`XtreamDTOs`, détail, EPG)
- Clés numériques-ou-chaînes (`stream_id`, `category_id`, timestamps…) → **`FlexibleString`**
  (`Decodable` acceptant `Int`/`Double`/`String`/absent → `""`). Non négociable (panels
  incohérents).
- `Codable` ignore les clés inconnues par défaut → OK. Décodage **tolérant** : chaque parse
  en `do/catch`, dégradation propre (catégorie vide, item ignoré), **jamais** de crash.
- EPG : `title`/`description` en **Base64** sur la plupart des panels (repli texte brut) ;
  timestamps epoch **secondes**. Pas de distribution/acteurs dans l'EPG → lien **IMDb par
  titre**.

### 3.3 Logique de login (`XtreamRepository.login`)
- `auth == 0` ou `userInfo == null` → **identifiants invalides**.
- `status != "Active"` → **expiré**.
- sinon → **succès**, persister (Keychain) ; distinguer « serveur injoignable » de
  « identifiants refusés ».

### 3.4 `XtreamCredentials`
- `serverUrl` normalisé en `scheme://host[:port]` (pas de slash/path final).
- `normalize(raw, user, pass)` : accepte `serveur.com:8080`, `http://serveur.com:8080/`, une
  URL `player_api.php` complète → réduit à l'origine ; `nil` si aucun host.
- `isSecure` = `https://`. `description` **ne divulgue jamais** le mot de passe.

---

## 4. Persistance & cache (Room → GRDB) + multi-listes

Tables (mappent `Entities.kt` d'Android), clés/index identiques :

| Room | GRDB table | Clé primaire | Index |
|---|---|---|---|
| `categories` | `categories` | (`contentType`, `categoryId`) | — |
| `live_channels` | `live_channels` | `streamId` | `categoryId`, FTS `name` |
| `movies` | `movies` | `streamId` | `categoryId`, FTS `name` |
| `series` | `series` | `seriesId` | `categoryId`, FTS `name` |
| `playback_positions` | `playback_positions` | `contentKey` (`movie:123`/`episode:456`) | `updatedAt` |
| `favorites` | `favorites` | (`playlistId`, `contentType`, `itemId`) | `addedAt` |
| `cast_index` | `cast_index` | `itemKey` | colonne **`castNames`** (pas `cast`) |
| `hidden_channels` | `hidden_channels` | (`playlistId`, `streamId`) | — |

- `ContentType` = `live` \| `vod` \| `series`. Champs dénormalisés conservés (favoris &
  positions affichent titre/affiche sans le cache catalogue).
- **Multi-listes** : un store chiffré (Keychain) des listes `{activeId, items[{id,serverUrl,
  username,password}]}`. Changer de liste active = **vider le cache catalogue** (categories/
  channels/movies/series/positions/cast_index) + incrémenter un **epoch** ; les `refresh*`
  capturent l'epoch et **abandonnent** l'écriture si la liste a changé (anti-données-fantômes).
  **Favoris + chaînes masquées restent** (scopés `playlistId`). Retirer une liste purge ses
  favoris/masquées ; retirer la **dernière** efface toutes les données locales (loi 25).
- **Migrations GRDB** : `DatabaseMigrator` avec étapes **additives** (jamais de drop&recreate —
  perte favoris/reprises). Équivalent des `Migration` Room non destructives.
- **Catalogues énormes (10k–50k)** : parse en **streaming**, insert par **batch**
  (transactions ~500 lignes), recherche **FTS5** (jamais un filtre mémoire), **pagination**
  (`ValueObservation` + requêtes paginées). Objectif : fluide sur iPhone à faible RAM.

---

## 5. Sécurité (port de `../mytv-player/docs/security.md` + `security-audit-2026-10.md`)

Posture et checklist Android reprises, traduites en API iOS. **MUST avant toute release :**

| Exigence Android | Équivalent iOS |
|---|---|
| Identifiants chiffrés au repos, jamais en clair | **Keychain** (`...ThisDeviceOnly`, `kSecAttrSynchronizable=false`). Jamais `UserDefaults`/fichier clair. |
| Aucun secret ni URL d'auth dans les logs ; redaction centralisée | `RedactingLogger` : masque `username=`/`password=` + segments `/live//movie//series//timeshift/{user}/{pass}/`. **Aucun `print` d'URL brute.** Règle CI `grep` qui fait échouer la build. |
| HTTPS par défaut ; consentement **par serveur** avant HTTP ; indicateur « non sécurisé » | ATS : clair **non** autorisé globalement ; garde-fou applicatif qui bloque l'envoi des identifiants en HTTP tant que l'utilisateur n'a pas consenti (décision persistée **par serveur**, révocable). Badge persistant. |
| TLS vérifié ; **aucun** `TrustAll`/hostname permissif | Validation standard `URLSession`. **Interdiction** d'un `URLSessionDelegate` qui accepte tout cert (règle CI). Pas de pinning (serveurs tiers). |
| Validation des URLs flux/images : schéma `http/https` only | Allowlist de schéma avant lecture/téléchargement ; rejet de `file:`/`data:`/autres. |
| Garde-fou d'hôte sur réinjection d'identifiants | Ne réinjecter `__cred__` que si l'hôte de l'URL = la liste propriétaire (anti-fuite cross-serveur). |
| Anti path-traversal sur noms de fichiers DL | **Nom généré localement** (UUID/hash de `streamId`), titre « joli » en métadonnée. Vérifier `canonicalPath` sous le dossier cible. |
| Parsing JSON/EPG défensif | `do/catch` systématique ; pas de parseur XML à DTD active. |
| Permissions minimales ; stockage privé | Fichiers dans `Application Support`/`Caches` (sandbox) ; **exclus de la sauvegarde iCloud** (`isExcludedFromBackup=true`). |
| `allowBackup=false` (secrets + médias hors sauvegarde) | Keychain `ThisDeviceOnly` + `isExcludedFromBackup` sur le dossier DL + la base GRDB. |
| **SHOULD** : `FLAG_SECURE` sur login/compte | Pas d'équivalent direct fiable ; **masquer le contenu sensible** au passage en arrière-plan (overlay sur `scenePhase == .inactive`) ; éviter le mot de passe dans l'aperçu multitâche. |
| SHOULD : métadonnées DL chiffrées | Ne persister que la forme `__cred__` + réinjection (pas de secret sur disque — **préféré**) ; sinon CryptoKit AES-GCM, clé Keychain. |
| Déconnexion = effacement (loi 25) | Retirer une liste purge ses données ; retirer la dernière vide **toute** la base + le Keychain. |
| NICE : biométrie pour révéler les identifiants | `LocalAuthentication` (Face ID/Touch ID), option réglages. |

Contenu serveur (EPG, titres, images) = **données hostiles** : affiché en `Text`, jamais
interprété ; images via Nuke (placeholder/erreur, cache négatif, bornes taille/timeout).

---

## 6. Téléchargement hors-ligne ⭐ (fonction phare)

Pièce la plus délicate (iOS n'a pas d'équivalent direct de Media3 `DownloadManager`).

- **`URLSession` config `.background(withIdentifier:)`** → les DL continuent app en arrière-plan
  / tuée ; le système relance l'app (`handleEventsForBackgroundURLSession`).
- **File d'attente** maison (max 3 parallèles, FIFO réordonnable) persistée en GRDB (table
  `downloads`) : état (`queued`/`downloading`/`paused`/`completed`/`failed`/`removing`), %,
  octets, `streamId`, titre, URL `__cred__`, chemin local, `resumeData`.
- **Reprise** : conserver `resumeData` (HTTP Range) à la pause/coupure → reprise sans
  re-télécharger. Au lancement, recharger la file et relancer ce qui était en cours.
- **Wi-Fi uniquement** (défaut ON) : `allowsCellularAccess = false` + `NWPathMonitor` (pause
  auto sur perte Wi-Fi, reprise au retour).
- **Disque plein** : vérifier l'espace libre vs taille estimée (`Content-Length` via HEAD,
  sinon bitrate×durée) **avant** ; refuser sous un seuil. Pendant : erreur « Stockage
  insuffisant », **pas** de retry en boucle.
- **Abonnement expiré** : DL en cours → 401/403 → `failed` « Abonnement expiré » (pas de
  retry). DL **terminé** → reste lisible hors-ligne (fichier local, **aucun** contact serveur).
- **Nettoyage orphelins** : au démarrage, croiser fichiers vs table ; supprimer les fragments
  non référencés. Suppression réelle du fichier à la suppression d'un DL.
- **Notifications** : `UNUserNotificationCenter` (permission au moment pertinent ; si refusée,
  les DL marchent quand même sans notif).
- **Bouton 6 états** (port de `DownloadButton`/`DownloadUiState`) : non téléchargé / en file /
  en cours (% anneau) / en pause / terminé / erreur — couleur + icône + forme + label
  d'accessibilité dynamique.

État UI : `DownloadUiState { id, title, uri, status, percent }`, agrégé en
`[streamId: DownloadUiState]`, rafraîchi en continu pendant l'activité.

---

## 7. Lecture (port de `reliability-and-qa.md`)

### 7.1 Double moteur `VideoEngine`
- **HLS (`.m3u8`) / mp4** → `AVPlayer` (natif, AirPlay, PiP, pistes audio/sous-titres).
- **MPEG-TS (`.ts` ou sans extension) / HEVC / AC3** → **MobileVLCKit** (`VLCMediaPlayer`).
- **Détection sans se fier à l'extension** (URLs Live Xtream souvent sans extension) : tenter
  TS→VLC ; si échec conteneur, **basculer** vers l'autre format (même chaîne souvent en `.ts`
  **et** `.m3u8` : construire l'URL alternative et relancer).

### 7.2 Résilience (Live vs VOD)
- Buffers : Live faible latence (re-démarrage rapide), VOD large. Réglage **« Faible latence /
  Équilibré / Anti-coupure »** (pas des millisecondes).
- Timeouts tolérants (connect ~10 s, read ~15 s) ; suivre redirections **cross-protocol**
  http↔https (fréquent Xtream) ; **User-Agent configurable** (certains panels filtrent par UA
  → 403).
- **Retry back-off exponentiel** plafonné (1→2→4→8 s), **plus** de retries en Live ; **pas**
  de retry sur 401/403/404 (abo expiré / flux retiré) → erreur claire immédiate.
- **Reconnexion applicative** : `NWPathMonitor` ; au retour réseau, re-préparer sans action
  utilisateur. Compteur de retry remis à zéro dès lecture stable.
- `BEHIND_LIVE_WINDOW` (retour avant-plan sur un Live) → re-seek au direct + relance.
- Fallback décodeur matériel→logiciel (VLC gère nativement beaucoup de codecs qu'AVPlayer
  refuse — leçon Dolby/DTS côté Android qui exigeait l'extension FFmpeg).
- **Reprise VOD** : position en GRDB (`playback_positions`), proposée à la réouverture.

### 7.3 Gestes & contrôles du lecteur
- **Un seul gestionnaire de gestes** (leçon Android : empiler plusieurs reconnaisseurs tue les
  gestes). Route : tap → afficher/masquer contrôles ; drag vertical **droite = volume /
  gauche = luminosité** (actif masqué **ou** affiché) ; drag horizontal → **chaîne ±**
  (Direct seulement).
- Contrôles **maison** (pas le contrôleur système) : auto-masquage ~7 s (suspendu pendant un
  drag de barre ou le sélecteur de pistes). VOD : scrub + recul 1 min / avance 10 s + sélecteur
  **langue/sous-titres**. Direct : barre rattrapage (« revenir au début » / « au direct »),
  **badge logo+nom de chaîne 5 s** au changement.

### 7.4 Messages d'erreur
Jamais de code brut/stacktrace. Chaque erreur → **titre court + cause probable + une action**
(Réessayer / Changer de qualité / Vérifier l'abonnement). Distinguer « *ce flux* est mort »
(serveur) de « *ta connexion* est coupée » (local). Overlay discret « Reconnexion… » tant que
les retries ne sont pas épuisés.

---

## 8. UI/UX (port de `design-system.md`, idiomes Apple)

- **Identité** : cinéma à la maison, **dark-first OLED** (noir), accent néon jaune→orange→rouge
  (palette Android). Logo PeachTV+ (pêche+tv, fourni par l'utilisateur) sur login + en-tête.
  **Ne pas générer de pêches néon IA** (rejetées côté Android).
- **Couleurs** : porter les tokens Material 3 en un `Theme` SwiftUI (couleurs sémantiques
  `download*`, `liveNow`, `ratingStar`, `success`/`warning`/`info` via `EnvironmentValues`).
  Le **lecteur reste toujours sombre**. Icône active **gris → jaune/orangé**.
- **Typo** : échelle de type mappée (display/headline/title/body/label), chiffres tabulaires
  pour minuteurs/%. Respecter **Dynamic Type**.
- **Responsive** : `NavigationSplitView` (liste+détail) sur iPad large (Expanded) ; `TabView` +
  pile sur iPhone (Compact). Grille d'affiches **adaptative** 2:3 : **3 colonnes portrait
  téléphone**, plus en paysage/iPad (`LazyVGrid .adaptive`). Marges 16 (iPhone) → 24 (iPad).
  **Plein écran lecteur** : masquer la nav ; sur iPhone bas (paysage) cacher le chrome.
- **Navigation 1er niveau (icônes, ≤ 5)** : Accueil (Direct/Films/Séries en onglets internes) ·
  Recherche · Favoris · Téléchargements (badge = nb en cours) · Réglages.
- **Composants** : `LiveChannelCard`, `PosterCard` (overlays qualité/hors-ligne/reprise),
  `DownloadButton` (6 états, §6), grille/guide EPG (colonne figée + timeline), `StorageDonut`/
  `StorageBar`, contrôles lecteur plein écran (§7.3), `AuthTextField`, `PlaylistForm`.
- **Accessibilité** : cibles ≥ 44 pt, VoiceOver (labels dynamiques : le bouton DL annonce état
  + %), contraste ≥ 4.5:1, « réduire animations », Dynamic Type.
- **États** : chargement = **skeleton/shimmer** aux dimensions finales (pas de spinner plein
  écran) ; vide = icône + titre + CTA ; erreur = message orienté solution + Réessayer.

**La spec par écran faisant autorité reste `../mytv-player/CLAUDE.md`** (section
« Spécification par écran ») — reproduite à l'identique, adaptée aux idiomes Apple.

---

## 9. Plan de tests / fiabilité (port de la matrice QA Android)

Priorité à automatiser ce qui peut l'être sans device :

- **Tests unitaires** (XCTest, CI simulateur, sans serveur réel) :
  - `FlexibleString` : int / double / string / absent / malformé.
  - `XtreamCredentials.normalize` : port non standard, caractères spéciaux (URL-encode).
  - `XtreamURLFactory` : toutes les formes d'URL, redaction (aucun secret logué), marqueur
    `__cred__`, garde-fou d'hôte.
  - Décodage EPG Base64 + repli ; timestamps epoch.
  - Mapping DTO → modèle (login invalide/expiré/succès, détail film/série, saisons/épisodes).
  - File de téléchargement (transitions d'état, Wi-Fi only, disque plein → pas de retry).
  - Multi-listes : bascule → epoch++ → `refresh*` abandonnés si liste changée ; favoris/masquées
    scopés `playlistId` survivent à la bascule.
  - Redaction (`RedactingLogger`) : aucune fuite.
- **Snapshot tests** (`swift-snapshot-testing`) : login, cartes, bouton DL 6 états, lecteur,
  grille EPG — vérification visuelle sans œil humain.
- **Tests manuels** (device + serveur Xtream réel) : lecture Live/VOD, catch-up, téléchargement
  réel, hors-ligne, longue durée. Fournis comme **checklist bêta**.
- **Règles CI** (grep/lint, sur Linux avant macOS) : échec si `TrustAll`/hostname permissif, si
  une URL brute atteint un logger, si identifiants en `UserDefaults`.

Critères de sortie (go/no-go) : zéro crash P0, aucune fuite d'identifiant dans logs/
diagnostics, tous les cas erreur → message clair, reprise DL après kill vérifiée, lecture
stable 2 h, bascule de liste sans perte de favoris.

---

## 10. Équipe & découpage du travail

Rôles (« chapeaux » du pilote, délégués à des sous-agents/sessions quand un module est
proprement isolable — **un seul écrivain par ensemble de fichiers**) :

| Spécialiste | Périmètre | Dossier |
|---|---|---|
| **Architecte iOS** | `project.yml`, `AppContainer` (DI), structure, CI | racine, `.github/` |
| **Réseau Xtream** | API, DTOs, URL factory, `FlexibleString`, repository, multi-listes | `Networking/`, `Model/` |
| **Stockage & cache** | GRDB (schéma, DAO, FTS, pagination), reprise, favoris, isolation liste | `Storage/` |
| **Sécurité** | Keychain, redaction, ATS, consentement HTTP, validation URL, garde-fou d'hôte | `Security/` |
| **Lecture vidéo** | `VideoEngine` (AVPlayer + VLCKit), résilience, EPG/catch-up, erreurs, gestes | `Player/` |
| **Téléchargement** ⭐ | file `URLSession` background, reprise, Wi-Fi only, espace, notifs | `Download/` |
| **UI/UX SwiftUI** | thème, composants, écrans, responsive iPhone/iPad, accessibilité | `UI/`, `Resources/` |
| **QA / CI / Déploiement** | XCTest, snapshots, règles CI, checklist bêta, Fastlane/TestFlight | `Tests/`, `.github/`, `fastlane/` |

Ordre (dépendances) : **Archi/CI → Réseau+Modèles → Stockage+Sécurité → Lecture +
Téléchargement (parallélisables) → UI → QA/TestFlight.**

---

## 11. Jalons (feuille de route)

- [x] **M0** — Scaffold : `project.yml` (XcodeGen), CI `macos-14` build+test à vide, règles de
  sécurité CI, app placeholder, test fumée. *(fait — 2026-11-12)*
- [x] **M1** — Réseau + modèles : `XtreamCredentials` (+normalize), DTOs + `FlexibleString`,
  `XtreamURLFactory` (URLs API/flux, `__cred__` + garde-fou d'hôte, timeshift), `XtreamAPI`
  (URLSession async), `XtreamMapping` (EPG Base64), `XtreamRepository` (login +
  **multi-listes** en mémoire + epoch + catalogue), `RedactingLogger`, + 6 suites de tests
  XCTest (mock `URLProtocol`). *(fait — 2026-11-12 ; à valider par la CI macos-14)*
- [x] **M2** — Stockage GRDB (`AppDatabase` migrator additif, records mappant Room, `CatalogStore` :
  upsert par lots, lectures paginées, recherche **FTS5**, favoris/masquées **scopés `playlistId`**,
  `clearCatalog`/`purgePlaylist`/`clearAll`) + Sécurité (`KeychainStore` + `KeychainPlaylistStore`
  remplaçant le store mémoire M1, `CleartextConsent` par serveur, `URLGuard`, exclusion backup) ;
  repository câblé (vidage cache à la bascule, purge au retrait, effacement total loi 25) ;
  tests XCTest (cache mémoire, Keychain, gardes). GRDB = 1re dépendance SPM.
  *(fait — 2026-11-12 ; à valider par la CI macos-14)*
- [~] **M3** — Lecture. **M3a fait (2026-11-12, sans dépendance, à valider par la CI)** :
  `Player/StreamFormat` (choix moteur + URL alternative TS↔HLS + `PlaybackFallbackGuard` une
  bascule), `VideoEngine` (protocole) + `BufferProfile` (3 crans) + `AVPlayerEngine`
  (AVFoundation), `PlaybackRetryPolicy`/`Controller` (back-off 1→2→4→8, no-retry 401/403/404,
  plus de tentatives en Live), `PlaybackError.classify` (titre+cause+action, serveur vs local),
  `PlayerGestureArbiter` (routeur unique), `EpgTimeline` (now/next/progression), `CatchUp`
  (timeshift depuis l'EPG) + tests XCTest (logique pure). **M3b à faire** : ajouter
  **MobileVLCKit** (SPM) + `VLCPlayerEngine` conforme à `VideoEngine`, câbler le coordinateur de
  bascule et les écrans lecteur Live/VOD — **idéalement après que le dépôt soit poussé** (la
  résolution SPM du binaire VLCKit ne peut être validée que par la CI macOS).
- [x] **M4** — Téléchargement hors-ligne ⭐ (cœur, sans dépendance — **2026-11-12, à valider
  par la CI**) : table GRDB `downloads` (migration **additive** v2) + `DownloadStore` ;
  `DownloadManager` (`URLSession` **background**, reprise `resumeData`, réinjection `__cred__`
  avec garde-fou d'hôte, anti-downgrade HTTPS→HTTP, nettoyage orphelins) ; politiques **pures
  testées** : `DownloadQueuePolicy` (max 3, FIFO), `DiskSpaceGuard`, `WiFiOnlyPolicy`,
  `DownloadError` (401/403 → expiré **sans retry**, disque plein **sans retry**, réseau →
  pause) ; `DownloadPaths` (nom local anti path-traversal + dossier hors backup) ;
  `DownloadStatus` + **bouton 6 états** + labels d'accessibilité ; tests (store mémoire +
  logique). **Reste M5** : écran « Disponible hors ligne », câblage runtime (`AppContainer`,
  `handleEventsForBackgroundURLSession`, purge des téléchargements au retrait d'une liste).
- [ ] **M5** — UI complète : thème PeachTV+, Accueil (Direct/Films/Séries), détail, recherche,
  favoris, chaînes cachées, réglages (multi-listes, donut, test de vitesse), responsive iPad.
- [ ] **M6** — QA : tests unitaires + snapshots verts en CI, règles de sécurité CI, checklist
  bêta.
- [ ] **M7** — Signature + **TestFlight** (dépend du compte Apple Developer de l'utilisateur) →
  install sur son iPhone/iPad, recette finale.

---

*Document maintenu par le pilote. Toute décision d'architecture PeachTV+ iOS est consignée ici.*
