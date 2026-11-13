# PeachTV+ iOS — Spécification de fiabilité & plan de tests QA/bêta

> **Rôle du document** : référence fiabilité + plan de tests pour **M6** (QA : XCTest +
> snapshots + règles CI) et la **recette M7** (TestFlight sur device réel).
> **Cible** : app IPTV **native Swift/SwiftUI**, iPhone + iPad, iOS 17+. Double moteur de
> lecture **AVPlayer ↔ MobileVLCKit**, téléchargement hors-ligne `URLSession.background`,
> cache **GRDB/FTS5**, identifiants en **Keychain**, multi-listes isolées par `playlistId`.
> **Source portée** : `../mytv-player/docs/reliability-and-qa.md` (matrice QA Android,
> codes `CN/NV/PL/EP/DL/OF`) — **référence en lecture seule, jamais modifiée**.
>
> **Contrainte de pilotage n°1 (à graver)** : développement **sous Windows, aucun Mac**.
> Donc *tout ce qui peut l'être est automatisé en CI* (`macos-14`, simulateur iPhone 15,
> XCTest + snapshots). Tout ce qui exige un **vrai serveur Xtream + un device physique**
> devient une **checklist bêta** (M7, dépend du compte Apple Developer de l'utilisateur).
>
> **Hypothèse de travail n°2 (héritée d'Android)** : les flux IPTV sont *hostiles par
> défaut*. Le serveur peut couper, renvoyer un 302 vers une pub, livrer un TS corrompu, un
> codec exotique, un EPG vide ou un catalogue de 50 000 entrées. La fiabilité est
> l'architecture de départ, pas un polish de fin.

---

## Sommaire

1. [Profils de résilience de lecture](#1-profils-de-résilience-de-lecture)
2. [Taxonomie des messages d'erreur](#2-taxonomie-des-messages-derreur)
3. [Matrice QA portée (cas par cas depuis Android)](#3-matrice-qa-portée-cas-par-cas-depuis-android)
4. [Plan de tests unitaires XCTest](#4-plan-de-tests-unitaires-xctest)
5. [Snapshot tests (swift-snapshot-testing)](#5-snapshot-tests-swift-snapshot-testing)
6. [Règles CI « fail the build »](#6-règles-ci--fail-the-build-)
7. [Checklist bêta (device + serveur réel)](#7-checklist-bêta-device--serveur-réel)
8. [Critères de sortie go/no-go](#8-critères-de-sortie-gono-go)
- [Annexe A — Correspondance Android → iOS des mécanismes](#annexe-a--correspondance-android--ios-des-mécanismes)

---

## 1. Profils de résilience de lecture

### 1.1 Deux profils + un réglage à trois crans

Android règle le `DefaultLoadControl` d'ExoPlayer. iOS n'a pas d'équivalent unique : on règle
**deux moteurs différemment**. La règle produit reste la même : **exposer trois crans
compréhensibles, pas des millisecondes**.

| Réglage UI | Intention | AVPlayer (HLS/mp4) | MobileVLCKit (TS/HEVC/AC3) |
|---|---|---|---|
| **Faible latence** | coller au direct, re-démarrer vite | `automaticallyWaitsToMinimizeStalling = false`, `preferredForwardBufferDuration ≈ 2 s` | `--network-caching=1000`, `--live-caching=1000` |
| **Équilibré** (défaut) | compromis | `automaticallyWaitsToMinimizeStalling = true`, `preferredForwardBufferDuration ≈ 5 s` | `--network-caching=3000` |
| **Anti-coupure** | bufferiser large, tolérer un débit instable | `preferredForwardBufferDuration ≈ 15 s` (Live) / `30 s` (VOD) | `--network-caching=8000` |

- **Live faible latence vs VOD large buffer** : par défaut, Live démarre sur « Équilibré »
  côté latence, VOD force un buffer avant plus large (relecture d'un fichier stable, le scrub
  et le retour arrière doivent être fluides). Le cran choisi par l'utilisateur **module** ces
  deux bases, il ne les remplace pas.
- `preferredForwardBufferDuration = 0` = « laisser le système décider » → **ne pas** utiliser 0
  comme valeur « faible latence » (ambigu). Toujours une valeur explicite.
- Le cran est persistant (GRDB `settings` ou `UserDefaults` non sensible) et s'applique **au
  prochain `prepare`**, pas à chaud, pour éviter un re-buffer brutal en pleine lecture.

### 1.2 Timeouts, redirections, User-Agent

Configurés sur la `URLSessionConfiguration` (métadonnées : login, EPG, détail) **et** répliqués
sur chaque moteur de lecture.

- **Timeouts tolérants** : `timeoutIntervalForRequest ≈ 15 s` (serveur lent mais vivant),
  `timeoutIntervalForResource` large pour les longs transferts. Côté VLC :
  `--ipv4-timeout` / `--http-reconnect`. Trop court = faux « flux mort » ; trop long = UI figée.
- **Redirections cross-protocol http↔https** : `URLSession` suit les redirections par défaut
  (y compris http→https et https→http) via `urlSession(_:task:willPerformHTTPRedirection:...)`.
  **Non négociable** en IPTV : les panels Xtream redirigent constamment entre domaine principal
  et CDN, http et https. ⚠️ **Mais** : toute URL après redirection repasse par l'**allowlist de
  schéma** (`http`/`https` only) ; rejet de `file:`/`data:`/autres (règle sécurité, §6).
- **User-Agent configurable** : exposer un UA par **liste de lecture** (défaut : un UA
  « compatible lecteur », p. ex. le même que l'app Android pour hériter de ses autorisations
  panel). Certains serveurs renvoient **403 sauf** si l'UA ressemble à un lecteur connu. Posé
  sur `httpAdditionalHeaders` (métadonnées) et sur l'option VLC `:http-user-agent=`.

### 1.3 Retry back-off exponentiel plafonné

Politique **applicative** (iOS n'a pas de `LoadErrorHandlingPolicy` ExoPlayer) : un
`PlaybackRetryPolicy` qui décide, sur erreur, s'il faut re-préparer et après combien de temps.

- **Back-off exponentiel plafonné** : 1 → 2 → 4 → 8 s (plafond 8 s), pour ne pas marteler un
  serveur saturé.
- **Plus de retries en Live** qu'en VOD (Live = coupure transitoire fréquente ; VOD = un échec
  franc est plus souvent définitif).
- **Pas de retry sur 401 / 403 / 404** : abonnement expiré, flux retiré, URL morte → on
  **remonte immédiatement** une erreur claire (§2) au lieu de boucler. Détecter le code via
  `HTTPURLResponse.statusCode` (AVPlayer : `AVPlayerItem.errorLog()` / `error`) ou le code VLC.
- **Compteur remis à zéro** dès lecture stable (`AVPlayer.timeControlStatus == .playing` ou
  `VLCMediaPlayerStatePlaying`), pour ne pas abandonner après une longue session.

### 1.4 Reconnexion réseau (NWPathMonitor)

- Un **`NWPathMonitor`** partagé (déjà requis pour le « Wi-Fi uniquement » des téléchargements)
  publie l'état réseau. En lecture, dès que le réseau **revient** (`.satisfied`), re-préparer
  **sans** que l'utilisateur tape « Réessayer ».
- **Anti double-prepare** : garder un flag `isReconnecting` ; ignorer un rebond réseau si un
  `prepare` est déjà en vol (leçon Android `OF-04` « réseau qui clignote »).
- Tant que les retries internes + applicatifs ne sont pas épuisés : **overlay discret
  « Reconnexion… »** (spinner), jamais un écran d'erreur plein (§2).

### 1.5 `BEHIND_LIVE_WINDOW` (décrochage du direct)

- Cas IPTV très fréquent : app en arrière-plan puis retour → le direct a avancé hors fenêtre.
  Android : `seekToDefaultPosition() + prepare()`.
- **iOS AVPlayer** : sur un item HLS live, re-`seek` vers `seekableTimeRanges.last.end`
  (le « bord direct ») puis reprendre ; si l'item est devenu invalide, **recréer l'`AVPlayerItem`**.
- **iOS VLCKit** : relancer le média (le TS n'a pas de notion de fenêtre glissante HLS, mais
  une longue suspension peut laisser le flux dans un état mort → `stop()` puis `play()`).
- Déclencheur : observer `scenePhase` (retour `.active`) + l'erreur de lecture. Toujours
  **silencieux** pour l'utilisateur (pas de message).

### 1.6 Double moteur AVPlayer ↔ VLCKit & bascule

- **Détection sans se fier à l'extension** (URLs Live Xtream souvent sans extension) :
  1. URL en `.m3u8` → **AVPlayer**.
  2. URL en `.ts` ou **sans extension** → **MobileVLCKit** (AVPlayer ne lit pas le TS brut).
  3. `.mp4`/`.mkv` VOD → AVPlayer d'abord ; HEVC/AC3 problématique → VLCKit.
- **Bascule sur échec conteneur/codec** : si le moteur courant échoue avec une erreur de type
  « format/conteneur non supporté » ou « décodeur », **basculer sur l'autre moteur** et, si
  possible, **construire l'URL alternative** (la même chaîne Xtream existe souvent en `.ts`
  **et** `.m3u8` : permuter l'extension et le moteur). Une seule bascule par tentative (éviter
  le ping-pong infini AVPlayer↔VLC) : si les deux échouent → message clair (§2).
- **Cast/AirPlay** : toujours la variante **HLS `.m3u8`**, jamais le `.ts` brut (AirPlay/Cast
  ne lisent pas le TS). La bascule de moteur ne s'applique **pas** à une sortie AirPlay active.
- **VLC couvre beaucoup de codecs qu'AVPlayer refuse** (HEVC, AC3/E-AC3, DTS) nativement :
  c'est la raison d'être du double moteur (équivalent de la leçon Android FFmpeg/Dolby qui
  exigeait l'extension `.aar`). Donc le fallback « AVPlayer échoue → VLC » est le chemin
  **nominal**, pas une exception.

---

## 2. Taxonomie des messages d'erreur

**Jamais** de code brut (`NSURLErrorTimedOut`, `-11800`, `VLCMediaPlayerStateError`) ni de
stacktrace à l'écran. Chaque erreur → **titre court + cause probable + UNE action**. Toujours
distinguer **« ce flux est mort » (serveur, l'app va bien)** de **« ta connexion est coupée »
(problème local)** — les confondre génère des faux rapports de bug.

| Classe d'erreur (source) | Cause réelle | Titre + message | Action |
|---|---|---|---|
| **Réseau local absent** (`NWPathMonitor .unsatisfied`, `NSURLErrorNotConnectedToInternet`) | Appareil hors-ligne | « Pas de connexion. » — *Vérifiez votre réseau.* | Auto-reconnexion puis Réessayer |
| **Serveur injoignable** (`NSURLErrorCannotConnectToHost`, `CannotFindHost`, DNS) | Panel down / adresse fausse | « Serveur injoignable. » — *Impossible de joindre le serveur de la liste.* | Réessayer / Vérifier la liste |
| **Serveur trop lent** (`NSURLErrorTimedOut`, timeout VLC) | Débit au goutte-à-goutte | « Le serveur met trop de temps à répondre. » | Réessayer / Changer de qualité |
| **Flux indisponible 404** (`statusCode 404`) | Chaîne/film retiré | « Cette chaîne n'est pas disponible. » (≠ réseau) | Retour / Réessayer |
| **Accès refusé 401/403** (`statusCode 401/403`) | Abo expiré / non autorisé / UA filtré | « Accès refusé. Vérifiez votre abonnement. » | Voir la liste de lecture |
| **Décrochage direct** (`BEHIND_LIVE_WINDOW` équivalent) | Retour avant-plan sur Live | *(silencieux)* re-seek au direct | Automatique |
| **Format/codec non supporté** (AVPlayer `-11828`/`-11833`, VLC) | HEVC/AC3 sur AVPlayer | *(bascule VLC auto)* sinon « Format non pris en charge. » | Automatique puis message |
| **Conteneur illisible** (TS/HLS mauvais type) | Mauvais moteur | *(bascule moteur auto)* sinon « Flux illisible. » | Automatique |
| **HTTP bloqué par ATS** (`NSURLErrorAppTransportSecurityRequiresSecureConnection`) | http sans consentement | « Connexion non sécurisée bloquée. » — *Autoriser le HTTP pour ce serveur ?* | Consentement HTTP (par serveur, §Sécurité) |
| **Schéma rejeté** (allowlist) | URL `file:`/`data:` après redirection | « Flux refusé (adresse non autorisée). » | Retour |
| **Stockage insuffisant** (téléchargement, `NSFileWriteOutOfSpace`) | Disque plein | « Stockage insuffisant pour télécharger. » | Libérer de l'espace |
| **Abonnement expiré (DL en cours)** (401/403 pendant transfert) | Abo coupé | « Téléchargement arrêté : abonnement expiré. » | Voir la liste — **pas** de retry |

**Principes transverses (identiques à Android)** : (1) toujours une action possible, ou
« Automatique » ; (2) séparer problème serveur/flux de problème réseau local ; (3) aucun jargon,
code ni stacktrace visible ; (4) overlay discret « Reconnexion… » tant que les retries ne sont
pas épuisés, écran d'erreur plein seulement en dernier recours ; (5) ton **français, lisible**,
cohérent avec le reste de l'app (québécois toléré sur les verdicts, pas sur les erreurs).

---

## 3. Matrice QA portée (cas par cas depuis Android)

Reprise **intégrale** des familles Android `CN / NV / PL / EP / DL / OF`, chaque cas adapté aux
mécanismes iOS. Préfixe **`i`** = identifiant iOS traçant l'origine Android (ex. `iPL-07` ⇐
`PL-07`). Colonnes : **id · scénario · attendu · type de test**.

**Type** : `auto` = XCTest sans device/serveur · `snap` = snapshot `swift-snapshot-testing` ·
`device` = **manuel, device + serveur Xtream réel** (checklist bêta §7). Priorité implicite :
P0 = tout cas `device` de lecture/DL + tout cas erreur ; voir §8.

### 3.1 Connexion / Compte Xtream (CN → iCN)

| id | scénario | attendu | type |
|---|---|---|---|
| iCN-01 | Login host+user+pass valides | `login` OK, `status == "Active"`, persistance Keychain, catalogues chargés | device (+ auto sur mapping DTO) |
| iCN-02 | Mot de passe erroné | `auth == 0`/`userInfo == nil` → « Identifiants invalides », pas de crash | auto (mapping) + device |
| iCN-03 | Host injoignable / DNS mort | « Serveur injoignable », bouton Réessayer, distinct de « identifiants refusés » | auto (classif. erreur) + device |
| iCN-04 | Host en `http://` (cleartext) | ATS bloque par défaut → **consentement HTTP par serveur** puis login OK ; badge « non sécurisé » | auto (garde-fou consentement) + device |
| iCN-05 | Abonnement expiré à la connexion | `status != "Active"` → « Abonnement expiré/suspendu », date si fournie | auto (mapping) |
| iCN-06 | Port non standard (`:8080`, `:25461`) | `XtreamCredentials.normalize` conserve le port, URL correcte | **auto** |
| iCN-07 | user/pass avec caractères spéciaux (`@ / + espace`) | URL-encode correct (percent-encoding), pas d'URL malformée | **auto** |
| iCN-08 | Serveur renvoie HTML (portail captif) au lieu de JSON | `do/catch` décodage → « Réponse inattendue du serveur », pas de crash | **auto** |
| iCN-09 | Max connexions atteint sur le compte | Message dédié, **pas** de boucle de retry | auto (classif.) + device |
| iCN-10 | **Multi-listes** : ajouter/basculer plusieurs comptes | Bascule sans fuite de données entre listes ; `activeId` à jour | **auto** + device |
| iCN-11 | Timeout de login (serveur lent 20 s) | Spinner puis timeout propre, pas de blocage UI (main thread libre) | auto (timeout) + device |
| iCN-12 | Normalisation : URL `player_api.php` complète collée | Réduite à l'origine `scheme://host[:port]`, sans path/slash final | **auto** |
| iCN-13 | `description`/log des credentials | Mot de passe **jamais** divulgué (toString/log rédigé) | **auto** |

### 3.2 Navigation / Catalogue (NV → iNV)

| id | scénario | attendu | type |
|---|---|---|---|
| iNV-01 | Parcourir catégories Live/Films/Séries | Listes correctes, affiches chargées (Nuke) | snap + device |
| iNV-02 | Catégorie de 15 000–50 000 entrées | Scroll fluide, pagination GRDB, pas de pic mémoire (OOM) sur iPhone bas de gamme | device (+ perf) |
| iNV-03 | Catégorie vide | État vide propre (« Aucun contenu ») | **snap** |
| iNV-04 | Recherche « matrix » (titre, FTS5) | Résultats pertinents < 300 ms, debounce 250–300 ms | auto (requête FTS) + device |
| iNV-05 | Recherche accents/émoji (« amelie » → « Amélie ») | Normalisation NFC + fold accents, pas de crash, RTL supporté | **auto** |
| iNV-06 | Ajout/retrait Favoris | Persisté GRDB, **scopé `playlistId`**, survit redémarrage | **auto** + device |
| iNV-07 | Rotation / iPhone↔iPad (`NavigationSplitView`) | État préservé, layout adapté (Compact/Expanded) | **snap** + device |
| iNV-08 | Perte réseau pendant chargement de liste | Cache GRDB affiché, bandeau « hors-ligne » | auto (repo offline) + device |
| iNV-09 | Affiche/logo manquant (404) | Placeholder Nuke, **cache négatif**, jamais case vide/crash, pas de re-requête en boucle | **snap** + auto (cache négatif) |
| iNV-10 | Tri (A-Z, récents, note) sur gros catalogue | Tri correct, requête SQL indexée | auto |
| iNV-11 | **Favoris synthétiques** en tête (Direct « Favoris », Films/Séries « À l'affiche ») | Catégorie par défaut correcte, section « Reprendre » en tête | auto (logique catégorie) + snap |
| iNV-12 | **Chaînes cachées** (appui long → cacher ; restaurer) | Masquage scopé `playlistId`, restauration tout/individuel | **auto** + device |

### 3.3 Lecture Live & VOD (PL → iPL)

| id | scénario | attendu | type |
|---|---|---|---|
| iPL-01 | Chaîne live HLS `.m3u8` → AVPlayer | Lecture < 3 s, pas d'artefact | **device** |
| iPL-02 | Chaîne live MPEG-TS (`.ts`/sans ext) → VLCKit | Lecture OK (AVPlayer ne lit pas le TS) | **device** |
| iPL-03 | Film VOD mp4, scrub avant/arrière, recul 1 min/avance 10 s | Seek précis, pas de blocage | **device** |
| iPL-04 | Flux mort (404 / offline) | « Chaîne indisponible », **pas** de boucle infinie, pas de retry sur 404 | auto (politique retry) + device |
| iPL-05 | Serveur lent / débit variable | Rebuffer géré, reprise auto, overlay « Reconnexion » | **device** |
| iPL-06 | Coupure serveur en pleine lecture | Retry back-off 1→2→4→8 s puis reconnexion auto au retour | auto (back-off) + device |
| iPL-07 | Codec non supporté par AVPlayer (HEVC) | **Bascule AVPlayer→VLCKit** auto, sinon message clair | auto (sélection moteur) + device |
| iPL-08 | Audio non décodable AVPlayer (E-AC3/AC4/DTS) | VLCKit décode ; sinon message, vidéo si possible | **device** |
| iPL-09 | `BEHIND_LIVE_WINDOW` (retour avant-plan sur Live) | Re-seek au bord direct (`seekableTimeRanges.last`) auto, silencieux | auto (calcul seek) + device |
| iPL-10 | Zapping rapide (10 chaînes/10 s) | Pas de fuite de player, pas de crash, **un seul** moteur actif (libéré à chaque bascule) | **device** (+ auto sur cycle de vie) |
| iPL-11 | Changement piste audio / sous-titres (VOD) | Appliqué sans recharger le flux (AVPlayer `AVMediaSelectionGroup` / VLC tracks) | **device** |
| iPL-12 | Perte puis retour réseau en lecture (NWPathMonitor) | Reconnexion auto sans action utilisateur, pas de double-prepare | auto (anti-rebond) + device |
| iPL-13 | Interruption audio (appel, Siri, `AVAudioSession` interruption) | Pause auto, reprise après (observer `.interruptionNotification`) | **device** |
| iPL-14 | PiP (Picture-in-Picture, AVPlayer) | Continue, contrôles OK, libère bien à la fermeture | **device** |
| iPL-15 | Veille écran puis réveil | Reprend ou re-prepare proprement | **device** |
| iPL-16 | Redirection 302 cross-protocol http↔https | Suivie (URLSession) + **re-allowlist schéma** ; si contenu inattendu, remonter | auto (allowlist) + device |
| iPL-17 | Lecture 2 h+ (stabilité longue durée) | Pas de dérive mémoire, pas de crash, pas de fuite de player | **device** |
| iPL-18 | **Gestes** : tap=contrôles, drag vert. droite=volume/gauche=luminosité, horiz.=chaîne± (Direct) | **Un seul** gestionnaire de gestes (pas d'empilement), tout répond | snap (overlay) + **device** (gestes) |
| iPL-19 | **Reprise VOD** : réouverture d'un film déjà lu | Position GRDB proposée, reprise au bon timestamp | **auto** (persistance) + device |
| iPL-20 | Mémoire : AVPlayer/VLC **libéré** à la fermeture de l'écran | `onDisappear`/`deinit` → release ; pas de leak (Instruments) | device (Instruments) + auto (cycle de vie si testable) |

### 3.4 EPG / guide XMLTV (EP → iEP)

| id | scénario | attendu | type |
|---|---|---|---|
| iEP-01 | EPG now/next d'une chaîne (`get_short_epg`) | Programme courant + suivant corrects | auto (décodage) + device |
| iEP-02 | EPG volumineux (`get_simple_data_table`) | Parse/insert en arrière-plan (hors main thread), UI non bloquée | device |
| iEP-03 | EPG absent pour une chaîne | « Aucune info programme », pas de case vide cassée | **snap** |
| iEP-04 | **Base64** `title`/`description` + **repli texte brut** | Décodage Base64 ; si non-Base64, garder le texte tel quel ; jamais de crash | **auto** |
| iEP-05 | Timestamps **epoch secondes** + décalage horaire/fuseau | Heures affichées en **fuseau local** correct, offset géré | **auto** (conversion) + device |
| iEP-06 | EPG partiel (certaines chaînes seulement) | Dégradé propre par chaîne | snap |
| iEP-07 | XMLTV/JSON malformé, tronqué | Parse défensif `do/catch`, entrées cassées ignorées, pas de crash | **auto** |
| iEP-08 | Grille EPG façon téléviseur (colonne figée, timeline 12 h, en-têtes collants) | Mise en page correcte, barre de progression du programme en cours | **snap** |
| iEP-09 | Clic case horaire → détails + **lien IMDb par titre** | Pop-up détails, lien de recherche IMDb (pas d'acteurs réels sans TMDb) | snap + device |
| iEP-10 | **Catch-up / rattrapage** depuis l'EPG | URL `/timeshift/user/pass/durée/{yyyy-MM-dd:HH-mm}/id.ts`, **début en fuseau local**, bon timestamp | **auto** (URLFactory) + device |

### 3.5 Téléchargement hors-ligne (DL → iDL)

Moteur : **`URLSession` `.background`** + `resumeData` (HTTP Range) ; file maison en GRDB
(table `downloads`), max 3 parallèles.

| id | scénario | attendu | type |
|---|---|---|---|
| iDL-01 | Télécharger un film VOD | Notif progression, fichier lisible hors-ligne, nom local UUID (anti path-traversal) | device (+ auto sur transitions d'état) |
| iDL-02 | Télécharger un épisode de série | OK, rangé par série/saison | device |
| iDL-03 | Coupure réseau pendant DL | `resumeData` conservé → reprise sans re-télécharger (Range) | auto (logique reprise) + **device** |
| iDL-04 | **App tuée** pendant DL | `.background` continue / système relance l'app (`handleEventsForBackgroundURLSession`), file rechargée au lancement | **device** |
| iDL-05 | Disque plein | `failed` « Stockage insuffisant », **pas** de retry en boucle | **auto** (transition sans retry) + device |
| iDL-06 | 3+ DL concurrents | Limité à 3 parallèles, file FIFO visible/réordonnable | **auto** (file) + device |
| iDL-07 | **« Wi-Fi uniquement »** + passage en données | `allowsCellularAccess = false` + NWPathMonitor → pause auto, reprise au retour Wi-Fi | **auto** (décision) + device |
| iDL-08 | Abonnement expire pendant DL | 401/403 → `failed` « Abonnement expiré », **pas** de retry | **auto** + device |
| iDL-09 | Lire un contenu téléchargé hors-ligne | Lecture 100 % locale, **aucun** contact serveur, pas de vérif en ligne | **device** |
| iDL-10 | Supprimer un DL | Fichier + entrée GRDB supprimés, espace récupéré | **auto** + device |
| iDL-11 | Fichier orphelin après crash | Au démarrage, croiser fichiers vs table → suppression des fragments non référencés | **auto** (balayage) + device |
| iDL-12 | Permission notif refusée | DL marche quand même, sans notif (ne jamais bloquer sur la permission) | auto (découplage) + device |
| iDL-13 | Redémarrage de l'appareil | DL en cours repris (file persistée + `.background`) | **device** |
| iDL-14 | **Garde-fou d'hôte** : DL d'une autre liste ne reçoit **jamais** les identifiants de la liste active | Réinjection `__cred__` seulement si l'hôte de l'URL = la liste propriétaire ; sinon échec local | **auto** |
| iDL-15 | URL persistée / clé de cache | Contient la forme **`__cred__`**, **aucun** secret (user/pass) sur disque | **auto** |
| iDL-16 | **Bouton 6 états** (non DL / en file / en cours % / pause / terminé / erreur) | Couleur+icône+label d'accessibilité VoiceOver dynamique par état | **snap** (6 états) |

### 3.6 Hors-ligne / Résilience générale (OF → iOF)

| id | scénario | attendu | type |
|---|---|---|---|
| iOF-01 | Lancer l'app sans réseau | Catalogue cache GRDB + DL accessibles | device (+ auto repo) |
| iOF-02 | Mode avion en pleine session | Bascule hors-ligne propre, pas de crash | device |
| iOF-03 | Réseau très lent (Network Link Conditioner) | Timeouts propres, messages clairs, UI réactive | device |
| iOF-04 | Réseau qui clignote (on/off/on) | Pas de double-prepare, pas de leak (flag `isReconnecting`) | auto (anti-rebond) + device |
| iOF-05 | **Bascule de liste active** (multi-listes) | `clearCatalogueCache()` + **epoch++** ; `refresh*` en vol **abandonnent** l'écriture (anti-fantômes) ; favoris/masquées (scopés `playlistId`) **survivent** | **auto** |
| iOF-06 | **Masquage en arrière-plan** (`scenePhase == .inactive`) | Overlay masquant le contenu sensible (identifiants) dans l'aperçu multitâche | **snap** + device |
| iOF-07 | Retirer la **dernière** liste | Efface **toute** la base GRDB + Keychain (loi 25), retour à l'écran de connexion | **auto** |

---

## 4. Plan de tests unitaires XCTest

Cible : **tournent en CI `macos-14` sur simulateur, sans serveur ni device**. Les réponses
réseau sont **injectées** via un `URLProtocol` stub (ou un `XtreamAPI` mocké) — **jamais** un
vrai panel. Organisation : un fichier de test par module, nommé `XxxTests.swift`.

### 4.1 `FlexibleStringTests`
- `test_decodesInt` : `42` → `"42"`.
- `test_decodesDouble` : `42.0` → `"42"` (pas `"42.0"` — normaliser l'entier).
- `test_decodesString` : `"42"` → `"42"`.
- `test_absentOrNull_yieldsEmpty` : clé absente / `null` → `""`.
- `test_malformed_doesNotThrow` : objet/array inattendu → `""` (dégradation, pas de crash).
- `test_roundTripInContainer` : décodage d'un DTO entier où `stream_id`/`category_id` mélangent int et string.

### 4.2 `XtreamCredentialsTests` (`normalize`)
- `test_hostPortOnly` : `serveur.com:8080` → `http://serveur.com:8080` (ou https selon défaut).
- `test_fullSchemeTrailingSlash` : `http://serveur.com:8080/` → `http://serveur.com:8080` (slash final retiré).
- `test_playerApiUrl_reducedToOrigin` : `https://s.com/player_api.php?...` → `https://s.com`.
- `test_nonStandardPort_preserved` : `:25461` conservé.
- `test_specialCharsUserPass_urlEncoded` : `@ / + espace` → percent-encodés dans l'URL construite.
- `test_noHost_returnsNil`.
- `test_isSecure` : `https://` → true ; `http://` → false.
- `test_description_neverLeaksPassword` : la `description`/`debugDescription` ne contient pas le mot de passe.

### 4.3 `XtreamURLFactoryTests`
- `test_apiBase` / `test_authURL` (sans `action`) / `test_actionURL` (+ `category_id`).
- `test_allActions` : `get_live_categories`, `get_live_streams`, `get_vod_categories`, `get_vod_streams`, `get_series_categories`, `get_series`, `get_vod_info`, `get_series_info`, `get_short_epg`, `get_simple_data_table` → URL exacte attendue.
- `test_liveStreamURL` : `/live/{user}/{pass}/{id}.ts` **et** variante `.m3u8` (AirPlay/Cast).
- `test_vodURL` / `test_seriesEpisodeURL` avec extension.
- `test_catchupURL` : `/timeshift/{user}/{pass}/{durée}/{yyyy-MM-dd:HH-mm}/{id}.ts`, **début formaté en fuseau local** (geler le fuseau dans le test, p. ex. `America/Montreal`, et vérifier le string).
- `test_credMarker` : l'URL **persistée** (DL) contient `__cred__`, **jamais** user/pass.
- `test_credReinjection_sameHost` : réinjection OK si l'hôte correspond à la liste propriétaire.
- `test_credReinjection_hostGuard_blocksForeignHost` : hôte différent → **pas** de réinjection (garde-fou, retour échec/nil).
- `test_redaction_noSecretInBuiltURLLog` : toute URL passée au logger est rédigée (voir 4.9).

### 4.4 `EpgDecodingTests`
- `test_base64Title_decoded` : titre/description Base64 → texte clair.
- `test_plainText_fallback` : chaîne non-Base64 → gardée telle quelle (repli).
- `test_invalidBase64_doesNotCrash` : Base64 cassé → repli texte brut, pas de throw.
- `test_epochSeconds_toDate` : epoch secondes → `Date` correcte.
- `test_timezoneOffset_appliedToLocal` : programme affiché au bon fuseau local (geler le fuseau).
- `test_malformedEpgEntry_skipped` : entrée cassée ignorée, les autres passent.

### 4.5 `DTOMappingTests` (DTO → modèle de domaine)
- **Login** : `test_authZero_invalidCredentials` ; `test_userInfoNil_invalid` ; `test_statusNotActive_expired` ; `test_active_success`.
- **Détail** : `test_vodInfo_mapped` ; `test_seriesInfo_seasonsEpisodes_mapped` (saisons → épisodes, ordre correct).
- `test_missingOptionalFields_degradeGracefully` : champs absents → valeurs par défaut, pas de crash.
- `test_unknownKeys_ignored` : clés inconnues ignorées (`Codable` par défaut).

### 4.6 `DownloadQueueTests`
- `test_stateTransitions` : `queued → downloading → paused → downloading → completed` ; `… → failed`.
- `test_maxThreeParallel` : 4e DL reste `queued` tant qu'un slot n'est pas libre.
- `test_wifiOnly_pausesOnCellular` : NWPath mocké « cellular » + Wi-Fi only → pause ; retour Wi-Fi → reprise.
- `test_diskFull_failsNoRetry` : erreur « out of space » simulée → `failed`, **aucun** retry planifié.
- `test_subscriptionExpired_401_failsNoRetry` : 401/403 → `failed` « abonnement expiré », pas de retry.
- `test_resumeDataPersistedAndReloaded` : pause → `resumeData` en GRDB → reprise sans re-télécharger.
- `test_orphanCleanup` : fichier sans entrée → supprimé au balayage ; entrée sans fichier → nettoyée.
- `test_localFilename_isUUID_noPathTraversal` : nom généré localement, `canonicalPath` sous le dossier cible.

### 4.7 `MultiPlaylistTests`
- `test_switchActive_clearsCatalogue_bumpsEpoch` : bascule → cache catalogue vidé + epoch incrémenté.
- `test_refreshAbandonedOnEpochChange` : un `refresh*` capturant l'ancien epoch **n'écrit pas** après une bascule (anti-données-fantômes).
- `test_favoritesScopedByPlaylistId_survive` : favoris de la liste A invisibles sous B, re-visibles au retour sur A ; survivent à la bascule.
- `test_hiddenChannelsScopedByPlaylistId_survive` : idem chaînes masquées.
- `test_removePlaylist_purgesItsFavoritesAndHidden` : retrait d'une liste → ses favoris/masquées purgés (pas ceux des autres).
- `test_removeLastPlaylist_wipesAllLocalData` : dernière liste retirée → base + Keychain vidés (loi 25).

### 4.8 `HostGuardTests` (peut fusionner avec 4.3/4.6)
- `test_injection_onlyForOwningListHost` : identifiants réinjectés uniquement pour l'hôte de la liste propriétaire du DL.
- `test_foreignHost_noLeak` : URL d'un autre hôte → aucun secret ajouté.

### 4.9 `RedactingLoggerTests`
- `test_redactsUsernamePassword` : `?username=u&password=p` → `username=***&password=***`.
- `test_redactsStreamPathSegments` : `/live/u/p/123.ts`, `/movie/u/p/…`, `/series/u/p/…`, `/timeshift/u/p/…` → segments user/pass masqués.
- `test_noRawURLEverReachesSink` : un `log(url:)` brut passe forcément par la rédaction (vérifier qu'il n'existe pas de chemin direct).
- `test_authHeadersNeverLogged`.

> **Convention de test** : injecter l'horloge et le fuseau (`Calendar`/`TimeZone` en paramètre)
> pour que catch-up et EPG soient **déterministes** en CI. Jamais de `Date()` ou `TimeZone.current`
> nu dans le code testé des URLs/temps.

---

## 5. Snapshot tests (swift-snapshot-testing)

But : **vérification visuelle sans œil humain** (pas de simulateur sous la main). Enregistrer
les références en CI (premier run `record`), puis comparer. Fixer le **device virtuel**
(iPhone 15) et **forcer le mode sombre OLED** (l'app est dark-only) pour des images stables.
Couvrir **iPhone (Compact)** et **iPad (`NavigationSplitView`, Expanded)** pour les écrans
responsives, et au moins un cas **Dynamic Type XXL** + un cas **français long** (troncature).

Écrans / états clés :

1. **Login / connexion** : champ URL vide ; état « identifiants invalides » ; état « serveur injoignable » ; badge « non sécurisé » (HTTP consenti) ; mot de passe masqué/révélé.
2. **Accueil** : onglets Direct/Films/Séries ; barre d'onglets du bas (icônes, actif gris→jaune/orangé) ; iPhone Compact **et** iPad split.
3. **Cartes** : `LiveChannelCard` ; `PosterCard` (overlays qualité / hors-ligne / reprise) ; placeholder affiche manquante.
4. **Grille catalogue adaptative** : 3 colonnes portrait iPhone ; 4+ paysage/iPad ; section « Reprendre la lecture » en tête.
5. **Bouton de téléchargement — 6 états** : non DL / en file / en cours (anneau %) / pause / terminé / erreur (couleur + icône + forme). *Cas phare du snapshot.*
6. **Grille EPG** : colonne de chaînes figée + timeline 12 h + en-têtes collants + barre de progression ; état « EPG absent » ; pop-up détails de case + lien IMDb.
7. **Lecteur** (toujours sombre) : contrôles affichés (Live : barre rattrapage « début/direct », badge logo+nom 5 s) ; (VOD : scrub + recul 1 min/avance 10 s + sélecteur langue/sous-titres) ; overlay « Reconnexion… ».
8. **Réglages** : section « Liste de lecture » (multi, radio actif) ; **StorageDonut** / **StorageBar** (utilisé jaune / libre foncé) ; chaînes cachées ; test de vitesse (verdicts).
9. **Favoris** : sections Direct → Films → Séries ; **Téléchargements** : sections Films / Séries.
10. **États génériques** : skeleton/shimmer (chargement) ; vide (icône + titre + CTA) ; erreur (message orienté solution + Réessayer).
11. **Masquage arrière-plan** : overlay `scenePhase == .inactive` sur un écran contenant des identifiants.

---

## 6. Règles CI « fail the build » (grep/lint)

Exécutées **sur Linux avant l'étape macOS** (rapides, pas de toolchain Xcode requise). Toute
occurrence fait **échouer** la CI. Script dédié (`ci/security-grep.sh`) versionné, appelé par
`.github/workflows/ci.yml`. Chaque règle liste ses **exceptions autorisées** (fichiers de test).

1. **Pas de `TrustAll` / validation TLS permissive** : échec si un `URLSessionDelegate`
   implémente `urlSession(_:didReceive:completionHandler:)` en renvoyant
   `URLCredential(trust:)` sans validation, ou `.performDefaultHandling` contourné. Grep :
   `serverTrust`, `URLCredential(trust:`, `.useCredential` hors allowlist. **Pas de pinning**
   attendu (serveurs tiers), mais **jamais** d'acceptation aveugle.
2. **Aucune URL brute loguée** : échec si un `print(`/`NSLog(`/`os_log(` reçoit une variable
   d'URL ou une interpolation contenant `server`, `username`, `password`, `/live/`, `/movie/`,
   `/series/`, `/timeshift/`. Tout log d'URL **doit** passer par `RedactingLogger`.
3. **Pas d'identifiants en `UserDefaults` / fichier clair** : échec si `UserDefaults` est
   écrit avec une clé contenant `password`, `pass`, `credential`, `token`, `xtream` ou si un
   mot de passe atteint `write(to:`/`.plist`. Les secrets vont **uniquement** en Keychain.
4. **Pas de `print` d'URL de flux dans le lecteur** (sous-cas de 2, ciblé `Player/`).
5. **ATS** : échec si `Info.plist`/`project.yml` contient `NSAllowsArbitraryLoads = true`
   (le clair global est interdit ; le HTTP passe par le **consentement applicatif par serveur**).
6. **Pas de `.xcodeproj` / `Package.resolved` / `DerivedData` versionnés** (cohérence
   XcodeGen ; `.gitignore` vérifié).
7. **Pas de littéral d'UI en dur** (lint souple, *warning* d'abord) : texte visible via
   `String(localized:)` / `.strings` (`fr`), pas de `Text("...")` en français en dur — aligne
   sur la règle « français exclusivement ».
8. **Lint Swift** (`swiftlint` si dispo en CI) : au minimum `force_unwrapping` et
   `force_try` signalés dans `Networking/`, `Storage/`, `Player/`, `Download/` (le parsing doit
   être défensif `do/catch`, pas de `try!`/`!` sur des données serveur hostiles).

Étape macOS (après les règles vertes) : `xcodegen generate` + `xcodebuild build test`
(simulateur iPhone 15) + exécution des snapshots. La CI est **la seule** autorité de compilation
(aucune compilation locale sous Windows).

---

## 7. Checklist bêta (device + serveur réel)

**Ne peut être validé qu'avec** : un **compte Apple Developer**, un **iPhone + iPad physiques**,
un **compte Xtream réel** (idéalement deux listes, pour la bascule). Jalon **M7**. Le testeur
remplit cette checklist ; joindre le **journal de diagnostic rédigé** (vérifier qu'il ne
contient **aucun** mot de passe/URL complète avant envoi).

### 7.1 Parc d'appareils
- [ ] **iPhone récent** (iOS 17/18) — nominal, PiP, AirPlay.
- [ ] **iPhone plus ancien / faible RAM** — perfs, pas d'OOM sur catalogue 50 000, codecs via VLC.
- [ ] **iPad** (`NavigationSplitView`, paysage) — adaptation layout, grille 4+ colonnes.
- [ ] Au moins un appareil testant **HEVC/AC3** (chemin VLCKit).
- [ ] Un appareil au **stockage presque plein** (disque plein réel).

### 7.2 Lecture Live / VOD
- [ ] Live **HLS** (`.m3u8`, AVPlayer) : démarrage < 3 s, stable.
- [ ] Live **MPEG-TS** (`.ts`/sans extension, VLCKit) : lecture OK.
- [ ] VOD film : scrub, recul 1 min / avance 10 s, **reprise** à la réouverture.
- [ ] Série : saisons/épisodes, lecture épisode.
- [ ] **Bascule de moteur** : une chaîne HEVC bascule bien AVPlayer→VLC.
- [ ] **Gestes** plein écran : volume (droite), luminosité (gauche), chaîne ± (Direct), tap contrôles, auto-masquage ~7 s, badge logo+nom 5 s.
- [ ] Sélecteur **langue audio / sous-titres** (VOD).
- [ ] **AirPlay** : caste la version **HLS**, jamais le `.ts`.

### 7.3 Catch-up / rattrapage
- [ ] Depuis l'EPG, « revenir au début de la diffusion » lance le bon programme (bon timestamp).
- [ ] « Revenir au direct » recolle au bord live.
- [ ] Vérifier le **fuseau** (serveur dans un autre fuseau que Montréal) + changement d'heure été/hiver.

### 7.4 Téléchargement réel + hors-ligne
- [ ] Télécharger un film et un épisode : notif progression, bouton 6 états corrects.
- [ ] **Coupure réseau** pendant DL → reprise (Range) au retour.
- [ ] **App tuée** puis relancée → DL repris.
- [ ] **Redémarrage appareil** → DL repris.
- [ ] **Wi-Fi uniquement** + passage en données → pause ; retour Wi-Fi → reprise.
- [ ] **Disque plein** → échec propre « Stockage insuffisant », pas de boucle.
- [ ] **Abonnement expiré** pendant DL → `failed` « abonnement expiré ».
- [ ] Lire un DL **hors-ligne total (mode avion)** : aucune requête serveur (vérifier au proxy/Charles).
- [ ] Supprimer un DL → espace récupéré, fichier parti.

### 7.5 Résilience & longue durée
- [ ] **Lecture 2 h** (Live et VOD) : pas de dérive mémoire, pas de crash (Instruments si possible).
- [ ] **Mode avion** en pleine session → bascule hors-ligne propre.
- [ ] **Réseau lent** (Network Link Conditioner 3G/Edge) : messages clairs, UI réactive.
- [ ] **Réseau qui clignote** : pas de double-prepare, pas de leak.
- [ ] **Interruption** (appel, Siri, autre app audio) → pause/reprise.
- [ ] Nuit en arrière-plan → reprend proprement au réveil.

### 7.6 Multi-listes
- [ ] **Bascule de liste active** : catalogue rechargé, **favoris + chaînes masquées conservés** (scopés `playlistId`).
- [ ] Ajouter / retirer une liste ; retirer la **dernière** → tout effacé, retour connexion.
- [ ] Un DL d'une liste **ne fuit pas** vers le serveur d'une autre (garde-fou d'hôte).

### 7.7 iPad / iPhone / accessibilité
- [ ] iPhone Compact (`TabView` + pile) **et** iPad Expanded (`NavigationSplitView`).
- [ ] Rotation en pleine lecture : pas de perte de position, pas de recreate du player.
- [ ] **VoiceOver** : navigation complète ; le **bouton DL annonce état + %** ; cibles ≥ 44 pt ; contrôles lecteur étiquetés.
- [ ] **Dynamic Type** grand : pas de texte tronqué/chevauché (login, cartes, réglages).
- [ ] **Réduire les animations** respecté.
- [ ] **Masquage arrière-plan** : l'aperçu multitâche ne montre pas les identifiants.

### 7.8 Sécurité (vérif device)
- [ ] Aucune fuite d'identifiant dans le journal de diagnostic exporté.
- [ ] HTTP bloqué sans consentement ; consentement **par serveur**, révocable ; badge « non sécurisé ».
- [ ] Dossier DL + base GRDB **exclus** de la sauvegarde iCloud.
- [ ] (NICE) Face ID/Touch ID pour révéler les identifiants.

---

## 8. Critères de sortie go/no-go

**GO** (recette M7) seulement si **tous** les points suivants sont tenus :

1. **Zéro crash P0** sur ≥ 7 jours de bêta (viser crash-free ≥ 99,5 % une fois TestFlight
   instrumenté) ; aucun des cas `device` de lecture/DL ne crashe.
2. **Aucune fuite d'identifiant** dans les logs, le journal de diagnostic, les URLs persistées,
   les clés de cache ni les rapports de crash (vérifié par 4.9 + règles CI §6 + §7.8).
3. **Tous les cas erreur** de la matrice §3 produisent un **message clair** (§2) — jamais un
   écran blanc, figé, un code brut ni une stacktrace. Flux mort vs réseau coupé toujours
   distingués.
4. **Reprise des téléchargements** vérifiée après **coupure réseau, app tuée et redémarrage de
   l'appareil** sur ≥ 2 appareils (iDL-03/04/13).
5. **Lecture stable 2 h** (Live et VOD) sans dérive mémoire ni crash ; un seul moteur actif,
   libéré à chaque bascule/fermeture (pas de leak de player).
6. **Bascule de liste** sans perte de favoris ni de chaînes masquées ; `refresh*` abandonnés sur
   changement d'epoch (aucune donnée fantôme) ; garde-fou d'hôte effectif.
7. **CI verte** : règles de sécurité §6 + `xcodebuild build test` + snapshots au vert.
8. **Catch-up** lance le bon programme au bon fuseau (iEP-10) et **hors-ligne** ne contacte
   jamais le serveur (iDL-09).

**NO-GO** si un seul des points 1–3 échoue (bloquants), ou si deux points parmi 4–8 restent non
vérifiés faute de device/serveur — dans ce cas, livraison repoussée, pas contournée.

---

## Annexe A — Correspondance Android → iOS des mécanismes

| Mécanisme Android (source) | Équivalent iOS porté | Cas QA concernés |
|---|---|---|
| `DefaultLoadControl` (buffers) | `preferredForwardBufferDuration` (AVPlayer) + `--network-caching` (VLC), 3 crans | §1.1, iPL-05 |
| `DefaultHttpDataSource` timeouts/UA/redirects | `URLSessionConfiguration` + options VLC | §1.2, iCN-11, iPL-16 |
| `LoadErrorHandlingPolicy` (back-off, pas de retry 4xx) | `PlaybackRetryPolicy` applicatif | §1.3, iPL-04/06 |
| `ConnectivityManager` reconnexion | **`NWPathMonitor`** | §1.4, iPL-12, iOF-04 |
| `ERROR_CODE_BEHIND_LIVE_WINDOW` | re-seek `seekableTimeRanges.last` (AVPlayer) / relance (VLC) | iPL-09 |
| ExoPlayer + extension FFmpeg (Dolby/DTS) | **MobileVLCKit** (codecs natifs) via bascule | iPL-07/08 |
| Arbitre de gestes unique (`PlayerGestureControls`) | **un seul** gestionnaire SwiftUI | iPL-18 |
| Media3 `DownloadManager`/`Service` + Range | **`URLSession.background`** + `resumeData` | §3.5 entier |
| `Requirements.NETWORK_UNMETERED` | `allowsCellularAccess=false` + NWPathMonitor | iDL-07 |
| Room + FTS + Paging 3 | **GRDB.swift** + FTS5 + pagination `ValueObservation` | iNV-02/04 |
| Tink + AndroidKeyStore | **Keychain** `...ThisDeviceOnly` (non iCloud) | §7.8, 4.9 |
| `CredentialInjectionInterceptor` + garde-fou d'hôte | réinjection `__cred__` + garde-fou d'hôte | iDL-14, 4.8 |
| `RedactingHttpLogger` | **`RedactingLogger`** + règle CI grep | §6, 4.9 |
| Coil (placeholder/cache négatif) | **Nuke** / NukeUI | iNV-09 |
| Migrations Room non destructives | **GRDB `DatabaseMigrator`** additif | (non régressé à la mise à jour) |
| epoch + `sameEpoch()` anti-fantômes | epoch capturé par `refresh*` | iOF-05, 4.7 |
| `playlistId` sur favoris/masquées | colonnes GRDB scopées | iNV-06/12, 4.7 |
| `FLAG_SECURE` (login/compte) | overlay `scenePhase == .inactive` | iOF-06 |

---

*Document maintenu par le rôle QA/CI de l'équipe PeachTV+ iOS. Les rapports de l'équipe de
revue sont des sorties de modèle, pas une autorité : trier, vérifier, puis appliquer. La seule
autorité de compilation est la CI `macos-14`.*
