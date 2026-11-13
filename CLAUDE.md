# CLAUDE.md — PeachTV+ (iOS / iPadOS)

Guide faisant autorité pour Claude Code (claude.ai/code) travaillant dans ce dépôt.

## Projet

**PeachTV+ iOS** est l'app **jumelle iOS/iPadOS** du lecteur IPTV **Android** PeachTV+
(dossier source `../mytv-player`). Portage **natif Swift/SwiftUI**, iOS 17+, iPhone + iPad.
Source de contenu : abonnement **Xtream Codes** (Live / Films / Séries). Fonction phare :
**téléchargement hors-ligne** (regarder sans Wi-Fi). Reproduit aussi : EPG + rattrapage
(catch-up/timeshift), favoris, recherche, chaînes cachées, **listes de lecture multiples**,
Chromecast (via AirPlay natif d'abord, Google Cast ensuite), lecteur plein écran à gestes.

- **Dossier** : `PeachTV+_iPhone/` (dans le monorepo `git/`). **Nom affiché : PeachTV+**
  (`CFBundleDisplayName`). Nom de cible/scheme Xcode interne : **`PeachTVPlus`** (sanitisé,
  sans « + »). `PRODUCT_BUNDLE_IDENTIFIER` : `com.peachtvplus.app`.
- **Distribution** : **TestFlight (usage personnel)**. Pas de publication App Store publique
  pour l'instant — mais garder l'archi/les docs **App-Store-ready** (passage en public possible
  sans tout refaire). Décidé avec l'utilisateur le **2026-11-12**.
- **Build** : **aucun Mac** → tout build/test/archive tourne sur un **Mac cloud en CI**
  (GitHub Actions `macos-14`). On ne compile **jamais** sous Windows ni dans la session Claude.
- Client de standards ouverts : **aucun DRM contourné, aucune décompilation.**
- **⚠️ `../mytv-player` (Android) est une source de référence EN LECTURE SEULE** — ne jamais
  la modifier. Ce projet en reproduit le comportement ; on y lit le code et `docs/`.

## Build, test, exécution

> ⚠️ **Rien ne se compile depuis la session Claude Code ni sous Windows** : pas de Mac,
> pas de toolchain Xcode. Toute compilation/validation se fait sur le **Mac cloud en CI**.
> Ne jamais prétendre qu'un changement « compile » — dire qu'il est **à valider par la CI**.

- Projet **généré par XcodeGen** depuis `project.yml` (le `.xcodeproj` n'est **jamais**
  versionné). On ne versionne que du texte (Swift + YAML).
- Dépendances via **SPM**, réintroduites **à leur jalon** (M0/M1 volontairement sans
  dépendance externe pour un 1er CI vert fiable). Voir `project.yml` + `docs/PORT-SPEC.md §2`.
- CI `.github/workflows/ci.yml` : (1) règles de sécurité `grep` sur Linux (échec si TrustAll,
  URL/secret logué, identifiants en `UserDefaults`) → (2) `macos-14` : `xcodegen generate` +
  `xcodebuild build test` sur simulateur iPhone 15.
- **La CI suppose que ce dossier est poussé comme son PROPRE dépôt GitHub.** Le monorepo
  `git/` n'a pas de remote (voir `docs/PORT-SPEC.md §0`).

```bash
# Sur un Mac, ou tel que la CI le fait :
brew install xcodegen
xcodegen generate
xcodebuild -scheme PeachTVPlus -destination 'platform=iOS Simulator,name=iPhone 15' build test
```

## Stack (équivalences Android → iOS)

| Besoin | Android (source, lecture seule) | iOS (cible) |
|---|---|---|
| Langage / UI | Kotlin + Jetpack Compose + Material 3 | **Swift 5.10 + SwiftUI** (`@Observable`, `NavigationStack`, `NavigationSplitView` iPad) |
| Archi / DI | MVVM + Repository, Hilt | **MVVM + Repository**, DI par composition (`AppContainer`), `async/await` |
| Lecture | Media3 / ExoPlayer | **AVPlayer** (HLS/mp4) **+ MobileVLCKit** (MPEG-TS/HEVC/AC3) via une abstraction `VideoEngine` |
| Téléchargement | Media3 `DownloadManager` | **`URLSession` `.background`** + reprise `resumeData` (HTTP Range) |
| Réseau | Retrofit + OkHttp + kotlinx.serialization | **`URLSession` + `Codable`** (+ `FlexibleString`) |
| Cache catalogue | Room (+ FTS) | **GRDB.swift** (SQLite + FTS5) |
| Identifiants chiffrés | Tink + AndroidKeyStore | **Keychain** (`...ThisDeviceOnly`, non iCloud) |
| Images | Coil | **Nuke** / NukeUI |
| Projet / build | Gradle | **XcodeGen** (`project.yml`) + SPM + GitHub Actions `macos-14` |

## Conventions (IMPORTANT)

- **Langue UI : français EXCLUSIVEMENT.** Aucun choix de langue. Tout texte visible via
  des catalogues de chaînes `String(localized:)` / `.strings` (`fr`), **jamais** de littéral
  en dur. (Android a retiré es/en et le sélecteur — même posture ici.)
- **Mode sombre OLED forcé** (fond noir). Palette néon jaune→orange→rouge sur noir (reprise
  de l'Android). Logo fourni par l'utilisateur sur fond noir — **ne pas régénérer de pêches
  néon IA** (rejetées côté Android).
- **Messages de commit en français.** Terminer chaque commit par :
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Git : monorepo `git/` sur la branche **`master`**. **Ne stager que les fichiers de ce
  projet** (`PeachTV+_iPhone/…`) — la racine du monorepo a beaucoup de changements non liés.
- **Règle un-seul-écrivain** : quand plusieurs agents/sessions touchent du code, un seul
  écrit un même ensemble de fichiers à la fois (éviter les écrasements). Respecter le
  découpage par rôle (`docs/PORT-SPEC.md §10`).
- **Pas de `.xcodeproj` / `Package.resolved` / `DerivedData` versionnés** (voir `.gitignore`).
- Pour toute révision d'envergure, l'utilisateur veut une **équipe de revue** (analyste +
  bêta-testeur + critique) : leurs rapports sont des **sorties de modèle, pas une autorité**
  → trier, vérifier, puis appliquer.

## Pièges connus (appris côté Android — ne pas refaire)

- **Détection de format de flux** : les URLs Live Xtream sont **souvent sans extension**. Ne
  pas se fier à l'extension ; tenter TS→VLC, basculer AVPlayer↔VLC si échec conteneur (la même
  chaîne existe souvent en `.ts` **et** `.m3u8`).
- **Chromecast ne lit pas le `.ts` brut** → caster/AirPlay la version **HLS** (`.m3u8`).
- **Catch-up/timeshift** : URL `/timeshift/USER/PASS/DUREE/DEBUT/ID.ts`, **début formaté en
  fuseau local** (réserve si le serveur est dans un autre fuseau).
- **EPG Xtream** : `title`/`description` sont en **Base64** sur la plupart des panels (repli
  texte brut) ; timestamps = epoch **secondes**. L'EPG n'a **pas** la distribution/acteurs →
  côté Android, lien de recherche **IMDb par titre** (pas de vrais acteurs sans TMDb+clé).
- **DTOs Xtream incohérents** : clés numériques-ou-chaînes (`stream_id`, `category_id`…) →
  décodeur tolérant **`FlexibleString`** (Int|Double|String|absent). Parsing **défensif**
  (do/catch partout, jamais de crash sur JSON malformé).
- **Identifiants** : jamais en clair, jamais dans une URL persistée ni un log. Marqueur
  `__cred__` réinjecté à la volée (comme Android) ; secret au repos = **Keychain** seulement.
- **Migrations de schéma NON destructives** : ne jamais « drop & recreate » la base (perte
  favoris + reprises). GRDB `migrator` avec étapes additives (équivalent des `Migration`
  Room non destructives côté Android).
- **Isolation par liste de lecture** : favoris et chaînes masquées sont **scopés par
  `playlistId`** côté Android (plus perdus à la bascule de liste). Changer de liste active
  vide le **cache catalogue** (epoch++) mais garde favoris/masquées.
- **Gestes du lecteur** : ne pas empiler plusieurs reconnaisseurs concurrents (tap + drags).
  Côté Android, un **arbitre de gestes unique** règle tout — reproduire un seul gestionnaire
  qui route tap / drag vertical (volume/luminosité) / drag horizontal (chaîne, Direct seul).
- **Plein écran immersif** : côté Android, envelopper le contexte pour forcer la locale a
  **cassé** le plein écran immersif. Leçon iOS : garder le chemin fenêtre/orientation simple ;
  forcer la locale par ressources, pas par des bidouilles de contexte.

## Spécification produit par écran (comportement cible)

**La spec produit faisant autorité est le `CLAUDE.md` Android (`../mytv-player/CLAUDE.md`,
section « Spécification par écran »)** — on la reproduit à l'identique côté iOS, adaptée aux
idiomes Apple (`NavigationSplitView` iPad, Dynamic Type, VoiceOver, AirPlay/PiP). Le détail
du mapping et des écrans est dans `docs/PORT-SPEC.md`. Résumé des exigences non négociables :

- **Cadre / Accueil** : onglets « Direct / Films / Séries » en tête (place au logo à droite) ;
  barre d'onglets du bas **icônes seules** (Accueil, Recherche, Favoris, Téléchargements,
  Réglages) ; icône active **gris → jaune/orangé**. iPad large = `NavigationSplitView`.
- **Direct** : grille EPG façon téléviseur (colonne figée + timeline 12 h, en-têtes
  collants) ; appui long chaîne → favori / cacher ; clic sur case horaire → détails + lien
  IMDb ; nom de chaîne qui **défile** ; catégorie synthétique **« Favoris »** en tête.
- **Films/Séries** : grille **adaptative** (3 colonnes en portrait téléphone, plus en
  paysage/iPad) ; catégorie défaut **« À l'affiche »** (Direct : « Québec ») ; section
  **« Reprendre la lecture »** en tête qui défile ; fiches saisons/épisodes + téléchargement.
- **Recherche** : focus + clavier auto à l'arrivée ; **5 dernières recherches** ; bouton X ;
  recherche par **titre** (FTS) et par **acteur** (index paresseux — pas d'indexeur de fond).
- **Favoris** : sections **Direct → Films → Séries** (plus de chaînes seules côté v1.03).
- **Téléchargements** : sections **Films / Séries** ; clic titre → même pop-up d'info.
- **Réglages** : section **« Liste de lecture »** (multi-listes : ajouter/retirer/basculer,
  ajout sous masquage d'aperçu) ; **donut/barre de stockage** (utilisé jaune / libre foncé) ;
  identifiants (mot de passe **révélé à la demande**, auto-masqué) ; **chaînes cachées**
  (restaurer tout/individuel) ; rafraîchir ; **test de vitesse** (verdicts, ton québécois) ;
  se déconnecter = retirer la liste (dernière liste retirée = tout effacer, loi 25).
- **Lecteur plein écran** : contrôles maison (tap affiche/masque, auto-masquage ~7 s) ;
  drag vertical **droite = volume / gauche = luminosité** ; **Direct** : drag horizontal =
  chaîne ±, et **logo+nom de chaîne 5 s** au changement ; VOD : scrub, recul 1 min/avance 10 s,
  reprise de lecture, sélecteur **langue/sous-titres**.

## Sécurité (voir `docs/security.md`)

Keychain (`...ThisDeviceOnly`, non synchronisé iCloud) ; redaction centralisée
(`RedactingLogger`, **aucune URL brute loguée** — règle CI) ; ATS clair non autorisé
globalement, **consentement HTTP par serveur** dans le code ; **pas** de `TrustAll` (règle
CI) ; allowlist de schémas `http/https` ; anti path-traversal sur noms de fichiers DL
(nom local UUID) ; dossiers DL exclus de la sauvegarde iCloud ; contenu serveur (EPG, titres,
images) = **données hostiles** (affiché, jamais interprété). SHOULD : masquer le contenu
sensible au passage en arrière-plan (`scenePhase == .inactive`). NICE : Face ID/Touch ID pour
révéler les identifiants.

## Données & réseau

Xtream Codes via `XtreamAPI` + `XtreamURLFactory` (endpoint unique `player_api.php?action=`).
Flux Live `.ts` (HLS `.m3u8` pour AirPlay/Cast). Cache catalogue en **GRDB** (tables mappant
Room : categories / live_channels / movies / series / playback_positions / favorites +
cast_index + hidden_channels, favoris & masquées **scopés `playlistId`**). Catalogues énormes
(10k–50k) : parse en **streaming**, insert par **batch**, recherche **FTS5**, **pagination**.
Détail du contrat réseau et des DTOs : `docs/PORT-SPEC.md §3`.

## Rôles d'équipe (découpage)

Architecte iOS · Réseau Xtream · Stockage & cache · Sécurité · Lecture vidéo ·
Téléchargement ⭐ · UI/UX SwiftUI · QA/CI/TestFlight. Un seul écrivain par ensemble de
fichiers. Détail + dossiers dans `docs/PORT-SPEC.md §10`.

## Jalons

M0 scaffold (CI vert à vide) · M1 réseau+modèles · M2 stockage GRDB + sécurité ·
M3 lecture (VideoEngine, EPG, catch-up) · M4 téléchargement hors-ligne ⭐ · M5 UI complète
(responsive iPad) · M6 QA (tests+snapshots+règles CI) · M7 signature + **TestFlight**.
Détail : `docs/PORT-SPEC.md §11`. **Actuel : M0+M1+M2 + M3a + M4 (cœur) faits (à valider par la
CI). Restants : M3b (MobileVLCKit + VLCPlayerEngine + écrans lecteur), puis M5 (UI complète +
câblage runtime du téléchargement). M3b/M5 de préférence une fois le dépôt poussé.**

- **Téléchargement (M4, cœur sans dépendance)** : `Download/` — `DownloadManager` (`URLSession`
  **background**, reprise `resumeData`, réinjection `__cred__` + garde-fou d'hôte, anti-downgrade
  HTTPS→HTTP, orphelins) ; `DownloadStore` (table GRDB `downloads`, migration **additive v2**) ;
  politiques **pures testées** : `DownloadQueuePolicy` (max 3, FIFO), `DiskSpaceGuard`,
  `WiFiOnlyPolicy`, `DownloadError` (401/403 → expiré **sans retry**, disque plein **sans retry**) ;
  `DownloadPaths` (nom 100% local anti path-traversal, dossier hors backup) ; `DownloadStatus` +
  **bouton 6 états**. `DownloadManager` n'est pas testé (I/O, device requis). **M5** : écran
  Téléchargements, `AppContainer` (un seul writer GRDB partagé), `handleEventsForBackgroundURLSession`,
  purge des téléchargements + fichiers au retrait d'une liste (loi 25).

- **Lecture (M3a, sans dépendance)** : `Player/` — `VideoEngine` (protocole, 2 moteurs),
  `AVPlayerEngine` (AVFoundation), `BufferProfile` (faible latence / équilibré / anti-coupure),
  `StreamFormat` (choix moteur sans se fier à l'extension + URL alternative TS↔HLS +
  `PlaybackFallbackGuard` : **une** bascule par tentative), `PlaybackRetryPolicy`/`Controller`
  (back-off 1→2→4→8 s, **jamais** de retry sur 401/403/404, plus de tentatives en Live),
  `PlaybackError` (titre + cause + **une** action ; distingue flux mort (serveur) de connexion
  coupée (local)), `PlayerGestureArbiter` (**un seul** routeur : tap / drag vertical
  volume-droite·luminosité-gauche / drag horizontal chaîne± en Direct), `EpgTimeline`
  (now/next/progression), `CatchUp` (timeshift depuis l'EPG). **M3b** ajoutera `VLCPlayerEngine`
  + le coordinateur de bascule + les écrans SwiftUI du lecteur.

- **Stockage (M2)** : `Storage/AppDatabase` (GRDB, `DatabaseMigrator` **additif** — jamais de
  drop&recreate), `Storage/CatalogStore` (DAO : upsert par lots, lectures paginées, recherche
  **FTS5** par titre, favoris/masquées **scopés `playlistId`**, `clearCatalog` vs `clearAll`).
  Base `Application Support/catalogue.sqlite`, **exclue du backup iCloud**. GRDB = 1re dépendance
  SPM (via `project.yml`). API synchrone pour l'instant → **M5** la déportera hors du main actor.
- **Sécurité (M2)** : `Security/KeychainStore` (générique, `ThisDeviceOnly`, non iCloud) +
  `KeychainPlaylistStore` (blob JSON chiffré, remplace le store mémoire M1 ; n'efface QUE sur
  échec **permanent**) ; `CleartextConsent` (HTTP autorisé seulement après consentement **par
  serveur**) ; `URLGuard` (allowlist `http/https`) ; `URL.excludeFromBackup()`. La réinjection
  `__cred__` + garde-fou d'hôte est déjà dans `XtreamURLFactory` (M1) — pas de doublon.

## Dépendances humaines (utilisateur)

- **Compte Apple Developer (99 $/an)** — requis pour signer + TestFlight (M7).
- **iPhone / iPad physique** de l'utilisateur — recette finale (M7).
- **Compte Xtream réel** — tests manuels de lecture/catch-up/téléchargement (serveur de démo
  utile si un jour revue App Store).
- Pousser ce dossier comme **dépôt GitHub autonome** pour activer la CI.
