# PeachTV+ (iPhone / iPad)

App **jumelle iOS/iPadOS** du lecteur IPTV Android **PeachTV+** (`../mytv-player`).
Portage **natif Swift/SwiftUI**. Source de contenu : abonnement **Xtream Codes**.
Fonction phare : **téléchargement hors-ligne** (films + épisodes). Cible : **iPhone +
iPad**, **iOS 17+**. Distribution : **TestFlight (usage personnel)** — architecture tenue
« App-Store-ready » pour un éventuel passage en public.

> ⚠️ **PeachTV+ Android (`../mytv-player`) est une source de référence EN LECTURE SEULE.**
> Ce projet ne la modifie jamais. Il en reproduit le comportement sur iOS.

> Client bâti sur des standards IPTV ouverts (Xtream Codes, HLS, MPEG-TS). Ne contourne
> aucun DRM. Le contenu téléchargé relève de la responsabilité de l'utilisateur.

## Pourquoi un projet généré (pas de `.xcodeproj` versionné)

Développé **sous Windows, sans Mac**. Le `.xcodeproj` est **généré** par
[XcodeGen](https://github.com/yonaskolb/XcodeGen) depuis [`project.yml`](project.yml) ;
la compilation et les tests tournent sur un **Mac cloud en CI** (GitHub Actions `macos-14`).
On ne versionne que du texte (Swift + YAML). Nom de cible/scheme interne : `PeachTVPlus`
(sanitisé) ; nom affiché de l'app : **PeachTV+**.

## Stack

| Besoin | Techno |
|--------|--------|
| Langage / UI | Swift 5.10 + SwiftUI (iOS 17) |
| Archi | MVVM + Repository, DI par composition (`AppContainer`) |
| Lecture vidéo | AVPlayer (HLS/mp4) + MobileVLCKit (MPEG-TS, HEVC, AC3) |
| Téléchargement hors-ligne | `URLSession` background + reprise (HTTP Range) |
| Réseau | `URLSession` + async/await + `Codable` |
| Cache catalogue | GRDB.swift (SQLite) + FTS5 |
| Identifiants chiffrés | Keychain (Secure Enclave) |
| Images | Nuke |

## Compiler / tester (sur un Mac, ou en CI)

```bash
brew install xcodegen
cd PeachTV+_iPhone
xcodegen generate          # produit PeachTVPlus.xcodeproj
xcodebuild -scheme PeachTVPlus -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -scheme PeachTVPlus -destination 'platform=iOS Simulator,name=iPhone 15' test
```

La CI [`.github/workflows/ci.yml`](.github/workflows/ci.yml) fait exactement cela à chaque push.

> La CI suppose que **ce dossier est poussé comme son propre dépôt GitHub** (racine du
> dépôt = ce dossier). Le monorepo `git/` n'a pas de remote ; voir `docs/PORT-SPEC.md §0`.

## Distribution (TestFlight)

Nécessite un **compte Apple Developer (99 $/an)** et un **appareil** de l'utilisateur.
La signature + l'upload TestFlight se feront via Fastlane depuis la CI (jalon M7).

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — guide faisant autorité pour les sessions Claude Code.
- [`docs/PORT-SPEC.md`](docs/PORT-SPEC.md) — **source de vérité** : mapping Android→iOS, décisions, jalons, rôles.
- `docs/design-system.md`, `docs/security.md`, `docs/reliability-and-qa.md`, `docs/devops-testflight.md` — specs d'équipe (iOS).
- Références Android (lecture seule) : `../mytv-player/` (code + `docs/`).

## État

Voir les jalons M0–M7 dans [`docs/PORT-SPEC.md`](docs/PORT-SPEC.md). Actuel : **M0 (scaffold)**.
