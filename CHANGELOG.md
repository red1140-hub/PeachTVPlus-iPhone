# Journal des modifications — PeachTV+ (iOS / iPadOS)

Toutes les dates en 2026. Format inspiré de *Keep a Changelog*. L'app est développée **sans
Mac** : chaque entrée « validée par la CI » signifie qu'elle compile et que les tests passent
sur le Mac cloud (Codemagic), jamais sur l'appareil tant que la recette TestFlight n'est pas faite.

## [0.1.0] — en préparation (TestFlight / sideload)

Première version complète et fonctionnelle de l'app jumelle iOS/iPadOS de PeachTV+ (Android).
Portage natif Swift/SwiftUI, iOS 17+, iPhone + iPad. Toutes les briques ci-dessous sont **vertes
en CI**.

### Ajouté — Réseau & modèles (M1)
- Couche Xtream Codes en Swift pur (zéro dépendance) : authentification, catégories, chaînes
  Live, films, séries, détails VOD/séries, EPG court, rattrapage (timeshift).
- Décodeur tolérant `FlexibleString` (clés Xtream Int/Double/String incohérentes), parsing
  défensif (aucun crash sur JSON malformé).
- Fabrique d'URL `XtreamURLFactory` : URLs d'API et de flux, **masquage des identifiants**
  (`__cred__`) jamais persistés, réinjection avec **garde-fou d'hôte** (anti-fuite vers un
  autre serveur).
- Multi-listes de lecture (id déterministe FNV-1a), EPG Base64, timestamps epoch.

### Ajouté — Stockage & sécurité (M2)
- Cache catalogue **GRDB (SQLite + FTS5)** : lectures paginées, recherche plein-texte par titre,
  migrations **additives** (jamais de perte de favoris/reprises).
- Favoris et chaînes masquées **scopés par liste de lecture** (`playlistId`).
- **Keychain** (`ThisDeviceOnly`, non synchronisé iCloud) pour les identifiants ; blob JSON
  chiffré ; effacement uniquement sur échec permanent.
- Consentement **HTTP par serveur** (HTTPS d'abord), allowlist de schémas, base exclue de la
  sauvegarde iCloud.

### Ajouté — Lecture (M3a + M3b)
- Abstraction `VideoEngine` à deux moteurs : **AVPlayer** (HLS/mp4) **+ VLCKit** (MPEG-TS brut,
  HEVC, AC3/DTS que refuse AVPlayer).
- **Coordinateur de bascule** AVPlayer↔VLC (une seule bascule par tentative), **retry réseau**
  en back-off (1→2→4→8 s, jamais sur 401/403/404, plus de tentatives en Direct).
- Profils de buffer (faible latence / équilibré / anti-coupure), erreurs orientées utilisateur
  (distingue flux mort vs connexion coupée), EPG now/next, rattrapage.
- **Écran lecteur plein écran** : contrôles auto-masqués, **arbitre de gestes unique**
  (volume à droite, luminosité à gauche, changement de chaîne en Direct), scrubber VOD, EPG
  maintenant/ensuite, overlay d'erreur, **volume système réel** (MPVolumeView).

### Ajouté — Téléchargement hors-ligne ⭐ (M4)
- `URLSession` **en arrière-plan** (poursuite app tuée, reprise `resumeData`), file d'attente
  persistée, plafond de parallélisme (max 3, FIFO), **Wi-Fi uniquement**, garde-fou d'espace
  disque, nettoyage des orphelins.
- Réinjection `__cred__` avec garde-fou d'hôte, **anti-downgrade HTTPS→HTTP**, nom de fichier
  local anti path-traversal, dossier exclu de la sauvegarde iCloud.
- Bouton de téléchargement **à 6 états** avec libellés d'accessibilité.

### Ajouté — UI complète & câblage runtime (M5)
- **Injection de dépendances** (`AppContainer`) avec **un seul writer GRDB** partagé catalogue +
  téléchargements ; coffre d'identifiants thread-safe pour le délégué background.
- Routage **connexion → shell**, réveil background des téléchargements
  (`handleEventsForBackgroundURLSession`).
- Shell à **5 onglets** : Direct (catégories + chaînes), Recherche (FTS5 : Direct/Films/Séries),
  Favoris (lecture + retrait, scopés à la liste), Téléchargements (états en direct,
  pause/reprise/suppression), Réglages (listes, consentement HTTP par hôte, resynchronisation,
  déconnexion).
- Synchronisation du catalogue (API → cache GRDB, anti-données-fantômes).
- **Écran détail séries** : saisons → épisodes, lecture d'un épisode (depuis Recherche et Favoris).
- **Purge au retrait d'une liste** : supprime ses téléchargements + fichiers, puis cache et
  identifiants (dernière liste retirée = tout effacé, **loi 25**).

### Ajouté — Qualité (M6, partie 1)
- Formatage de durée extrait et testé ; tests de robustesse (réinjection d'identifiants
  adversariale, accessibilité, formatage).
- *(Tests de snapshot visuels reportés à une session avec Mac — ils exigent l'enregistrement
  d'images de référence.)*

### Ajouté — Livraison (M7, préparation)
- Pipeline **TestFlight** via Codemagic (workflow `ios-testflight` sur tag `v*`,
  `fastlane beta`, signature par clé d'API App Store Connect).
- Workflow **`ios-ipa-unsigned`** (manuel) produisant `PeachTv+iphone.ipa` **non signée** pour
  sideload (AltStore / Sideloadly) — voir `docs/sideload-altstore.md`.
- **Manifeste de confidentialité** (`PrivacyInfo.xcprivacy`, aucun tracking/collecte),
  conformité export (`ITSAppUsesNonExemptEncryption = false`).
- Brouillons politique de confidentialité et fiche App Store.

### Corrigé
- Course au retrait d'une liste qui laissait un **fichier de téléchargement orphelin** sur
  disque (la ligne était supprimée avant la suppression asynchrone du fichier).
- `Info.plist` de la cible de tests absent → échec de signature en CI (ajout de
  `GENERATE_INFOPLIST_FILE`).

### Sécurité
- Aucune donnée personnelle collectée ou transmise à un tiers. Identifiants chiffrés au
  Trousseau, jamais en clair, jamais dans une URL persistée ni un log (redaction centralisée).
- HTTPS par défaut ; HTTP seulement après consentement explicite par serveur, révocable.

### Connu / limites
- Lecture, catch-up et téléchargement **réels** restent à valider sur appareil (recette
  TestFlight / sideload) : la CI compile et teste la logique, pas la lecture vidéo réelle.
- Détail séries : la distribution/les acteurs ne sont pas exposés par Xtream (comme sur Android).
