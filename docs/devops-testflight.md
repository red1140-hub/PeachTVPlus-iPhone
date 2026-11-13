# DevOps / CI-CD + TestFlight — PeachTV+ iOS (M7)

> Spec de déploiement de l'app jumelle iOS/iPadOS de PeachTV+. Cible : **TestFlight,
> usage personnel**, tenue **App-Store-ready**. Réalise le jalon **M7** de
> `docs/PORT-SPEC.md §11`.
>
> **Contrainte structurante** : l'utilisateur développe **sous Windows, sans aucun Mac**.
> Donc **tout** build / test / archive / upload se fait sur un **Mac cloud en CI**
> (GitHub Actions `macos-14`). Rien ne compile sous Windows ni dans la session Claude.
> Le projet est **généré par XcodeGen** depuis `project.yml` (le `.xcodeproj` n'est
> **jamais** versionné) ; dépendances via **SPM**.
>
> Ce document est le pendant iOS de `../mytv-player/docs/devops-setup.md` (Android, lecture
> seule). Les idées (dépôt dédié, secrets, release manuelle par tag, aucun secret versionné)
> sont reprises et adaptées aux outils Apple.

---

## 1. Vue d'ensemble du pipeline

Deux workflows GitHub Actions, même philosophie qu'Android : les contrôles **rapides et
gratuits** (Linux) tournent **avant** de réserver un runner macOS (coûteux, facturé ~10×).

```
                 push / PR / dispatch                         tag v*  / dispatch
                        │                                            │
        ┌───────────────┴───────────────┐            ┌───────────────┴────────────────┐
        │   .github/workflows/ci.yml     │            │  .github/workflows/release.yml  │
        │                                │            │                                 │
        │  job 1  security-rules (Linux) │            │  job 1  security-rules (Linux)  │
        │   grep: TrustAll / URL loguée  │            │   (mêmes règles, re-jouées)     │
        │        / creds UserDefaults    │            │            │                    │
        │            │ needs             │            │            │ needs              │
        │  job 2  build-test (macos-14)  │            │  job 2  archive-testflight      │
        │   xcodegen → xcodebuild test   │            │         (macos-14)              │
        │   (simulateur iPhone 15)       │            │   xcodegen → archive → export   │
        │                                │            │   IPA → upload TestFlight       │
        └────────────────────────────────┘            └─────────────────────────────────┘
          À CHAQUE push/PR : « ça compile + tests verts »   SUR TAG seulement : livre à TestFlight
```

- **`ci.yml`** (déjà en place) : validation continue. Reste la **porte de qualité** —
  on ne release jamais un commit dont le `ci.yml` est rouge.
- **`release.yml`** (fourni ci-dessous, §3) : **ne se déclenche que sur un tag `v*`**
  (ou à la main via `workflow_dispatch`). C'est lui seul qui **signe** et **téléverse**
  sur TestFlight. Il **re-joue** les règles de sécurité Linux en préalable (une release
  ne doit jamais contourner la porte de sécurité).

Pourquoi Linux d'abord : les règles `grep` (voir `ci.yml` et `docs/security.md`) échouent
la build en quelques secondes si un `TrustAll`, une URL/secret logué, ou des identifiants
en `UserDefaults` apparaissent — **avant** de payer une minute macOS.

---

## 2. Signer SANS Mac — clé d'API App Store Connect (+ match en option)

Le point délicat d'une CI iOS sans Mac : **signer** l'archive et **s'authentifier** auprès
d'Apple **sans interaction humaine** (pas de mot de passe Apple ID, pas de 2FA, pas de
trousseau macOS local).

### 2.1 App Store Connect API Key (obligatoire — authentification)

C'est le mécanisme officiel d'authentification **machine-to-machine** d'Apple. Il remplace
le couple Apple ID + mot de passe + 2FA, **ingérable** sur un runner.

**Création (UNE fois, par l'utilisateur)** : App Store Connect → **Users and Access** →
onglet **Integrations** → **App Store Connect API** → **Keys** → rôle **App Manager**
(suffisant pour TestFlight) → télécharger le fichier **`AuthKey_XXXXXXXXXX.p8`**.
Apple ne le laisse télécharger **qu'une seule fois** → le garder en lieu sûr.

Trois valeurs en résultent :

| Valeur | Où la trouver | Exemple |
|---|---|---|
| **Key ID** | nom du fichier / colonne « Key ID » | `ABC123DEF4` |
| **Issuer ID** | en haut de la page Keys (UUID du compte) | `6a0b…-…-…` |
| **Clé privée** | contenu du fichier `.p8` | `-----BEGIN PRIVATE KEY----- …` |

### 2.2 Deux stratégies de signature

Il faut, en plus de l'authentification, un **certificat de distribution** et un **profil de
provisioning** pour signer l'IPA. Deux chemins, sans Mac :

**Option A — Signature AUTOMATIQUE par clé d'API (recommandée ici, perso/solo).**
`xcodebuild … -allowProvisioningUpdates` + la clé d'API : Xcode crée/renouvelle **tout seul**
le certificat et le profil « app-store » côté Apple, à chaque archive. **Rien à stocker**
hormis la clé d'API et le Team ID. Le plus simple, zéro dépôt de certificats. C'est le
réglage par défaut du `Fastfile` et du `release.yml` fournis.

**Option B — Fastlane `match` (App-Store-ready, multi-machines).**
`match` stocke cert + profil **chiffrés** dans un **dépôt Git privé séparé**, (dé)chiffrés
par une phrase secrète. Build **reproductible** et partageable entre machines/collaborateurs.
Plus lourd (un dépôt de plus). À activer le jour où l'app vise l'App Store public ou plusieurs
contributeurs. Fichiers `fastlane/Matchfile` + bloc `match(...)` du `Fastfile` déjà prêts
(commentés). La première génération des certs se fait **une fois** (`fastlane match appstore`
depuis une machine de confiance ou un run dédié), puis la CI les consomme en **lecture seule**.

> Recommandation : **démarrer en Option A**. Migrer vers B seulement si un vrai besoin
> multi-machines / App Store public apparaît. Les deux sont documentées pour ne pas se
> repeindre dans un coin.

### 2.3 Secrets GitHub (jamais versionnés)

Dépôt du projet → **Settings → Secrets and variables → Actions → New repository secret**.
Aucune de ces valeurs n'entre dans Git (le `.gitignore` bloque déjà `AuthKey_*.p8`,
`ExportOptions.plist`, `fastlane/.env`, `*.p12`, `*.mobileprovision`).

| Secret | Contenu | Obligatoire |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | le **Key ID** (ex. `ABC123DEF4`) | ✅ |
| `APP_STORE_CONNECT_API_ISSUER_ID` | l'**Issuer ID** (UUID du compte) | ✅ |
| `APP_STORE_CONNECT_API_KEY` | le **contenu du `.p8` encodé base64** (voir encodage ci-dessous) | ✅ |
| `APPLE_TEAM_ID` | le **Team ID** (10 car., App Store Connect → Membership) | ✅ |
| `MATCH_GIT_URL` | URL du dépôt privé des certs | Option B seulement |
| `MATCH_PASSWORD` | phrase secrète de (dé)chiffrement de `match` | Option B seulement |
| `MATCH_GIT_BASIC_AUTHORIZATION` | token base64 `user:PAT` pour cloner le dépôt certs en HTTPS | Option B seulement |

**Encoder le `.p8` en base64** (le secret doit être du texte sur une ligne) :

```powershell
# Windows PowerShell (machine de l'utilisateur) — PAS d'accents, pas de piège UTF-8 ici :
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_ABC123DEF4.p8")) | Set-Content -NoNewline asc_key.b64.txt
# Copier le contenu de asc_key.b64.txt dans le secret APP_STORE_CONNECT_API_KEY, puis SUPPRIMER le .txt.
```

```bash
# macOS/Linux équivalent :
base64 -i AuthKey_ABC123DEF4.p8 | tr -d '\n'
```

Le workflow **re-décode** ce base64 en un fichier `AuthKey_XXXX.p8` sur le runner (jamais écrit
dans le dépôt), consommé par Fastlane.

---

## 3. Workflow release — `.github/workflows/release.yml`

Déclenché **sur tag `v*`** (ex. `v0.1.0`) ou à la main. Chaîne :
`security-rules` (Linux) → `xcodegen` → `archive` → `export IPA` → `upload TestFlight`.

Deux variantes de l'étape de signature/upload sont montrées :
- **Variante Fastlane** (recommandée, lisible, gère la clé d'API et l'IPA proprement) ;
- **Variante `xcodebuild` pur** (en commentaire, sans Fastlane, pour comprendre/dépanner).

```yaml
name: Release (TestFlight)

# Déclenché par un tag de version (ex. git tag v0.1.0 && git push origin v0.1.0),
# ou manuellement avec un numéro de version en entrée.
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      marketing_version:
        description: "Version marketing (ex. 0.1.0). Vide = déduite du dernier tag."
        required: false
        default: ""

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  # --- Porte de sécurité : mêmes règles que ci.yml, re-jouées avant toute release ---
  security-rules:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Interdire TrustAll / vérification TLS désactivée
        run: |
          if grep -RInE '\.useCredential.*serverTrust|allowsAnyHTTPSCertificate|_allowsAnyHTTPSCertificate' Sources/ ; then
            echo "::error::Vérification TLS potentiellement désactivée (TrustAll interdit)."; exit 1
          fi
      - name: Interdire les URLs/secrets bruts vers un logger
        run: |
          if grep -RInE 'print\(.*(username=|password=|/live/|/movie/|/series/|/timeshift/|player_api\.php)' Sources/ ; then
            echo "::error::URL/secret potentiellement logué sans redaction."; exit 1
          fi
      - name: Interdire le stockage d'identifiants en clair
        run: |
          if grep -RInE 'UserDefaults.*(password|username|credential)' Sources/ ; then
            echo "::error::Identifiants potentiellement stockés dans UserDefaults (utiliser le Keychain)."; exit 1
          fi

  archive-testflight:
    runs-on: macos-14
    needs: security-rules
    timeout-minutes: 45
    env:
      SCHEME: PeachTVPlus
      # Secrets → variables d'env lues par le Fastfile (fastlane/Fastfile) :
      ASC_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
      APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
    steps:
      - uses: actions/checkout@v4

      - name: Sélectionner Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Installer XcodeGen
        run: brew install xcodegen

      # Fastlane est préinstallé sur les images macOS GitHub ; sinon : gem install fastlane.
      - name: Vérifier Fastlane
        run: fastlane --version

      # ---- Reconstituer la clé d'API .p8 depuis le secret base64 (jamais versionnée) ----
      - name: Écrire la clé d'API App Store Connect
        run: |
          echo "${{ secrets.APP_STORE_CONNECT_API_KEY }}" | base64 --decode > "$RUNNER_TEMP/AuthKey.p8"
          echo "ASC_KEY_P8_PATH=$RUNNER_TEMP/AuthKey.p8" >> "$GITHUB_ENV"

      # ---- Calcul des numéros de version (voir §5) ----
      # MARKETING_VERSION : input manuel > tag (vX.Y.Z → X.Y.Z) > valeur de project.yml.
      # CURRENT_PROJECT_VERSION (build number) : numéro de run CI, strictement croissant.
      - name: Déterminer les versions
        run: |
          TAG="${GITHUB_REF_NAME}"
          MV="${{ github.event.inputs.marketing_version }}"
          if [ -z "$MV" ]; then MV="${TAG#v}"; fi          # retire le 'v' du tag
          if [ -z "$MV" ] || [ "$MV" = "$TAG" ]; then MV="0.1.0"; fi # repli (dispatch sans tag)
          echo "MARKETING_VERSION=$MV" >> "$GITHUB_ENV"
          echo "BUILD_NUMBER=${GITHUB_RUN_NUMBER}" >> "$GITHUB_ENV"
          echo "Version marketing = $MV / build = ${GITHUB_RUN_NUMBER}"

      - name: Générer le projet (XcodeGen)
        # Injecte Team ID + versions dans l'environnement lu par project.yml (voir §5).
        env:
          DEVELOPMENT_TEAM: ${{ secrets.APPLE_TEAM_ID }}
        run: xcodegen generate

      - name: Résoudre les dépendances SPM
        run: xcodebuild -resolvePackageDependencies -scheme "$SCHEME"

      # ---- Archive + export IPA + upload TestFlight (lane fastlane/Fastfile:beta) ----
      - name: Archive + TestFlight (Fastlane)
        env:
          MARKETING_VERSION: ${{ env.MARKETING_VERSION }}
          CURRENT_PROJECT_VERSION: ${{ env.BUILD_NUMBER }}
          TESTFLIGHT_CHANGELOG: "Release ${{ github.ref_name }} (build ${{ github.run_number }})"
        run: fastlane beta

      # ---- Conserver l'IPA comme artefact de run (pratique, non obligatoire) ----
      - name: Archiver l'IPA en artefact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: PeachTVPlus-ipa
          path: "**/PeachTVPlus.ipa"
          if-no-files-found: ignore
          retention-days: 14

# ------------------------------------------------------------------------------
# VARIANTE SANS FASTLANE (xcodebuild pur) — pour comprendre/dépanner.
# Remplace l'étape "Archive + TestFlight (Fastlane)" par les trois ci-dessous :
#
#   - name: Archiver
#     run: |
#       set -o pipefail
#       xcodebuild -scheme "$SCHEME" \
#         -configuration Release \
#         -destination 'generic/platform=iOS' \
#         -archivePath "$RUNNER_TEMP/PeachTVPlus.xcarchive" \
#         -allowProvisioningUpdates \
#         -authenticationKeyPath "$ASC_KEY_P8_PATH" \
#         -authenticationKeyID "$ASC_KEY_ID" \
#         -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
#         MARKETING_VERSION="$MARKETING_VERSION" \
#         CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
#         clean archive
#
#   - name: Exporter l'IPA (ExportOptions.plist généré au vol — gitignoré)
#     run: |
#       cat > "$RUNNER_TEMP/ExportOptions.plist" <<PLIST
#       <?xml version="1.0" encoding="UTF-8"?>
#       <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
#       <plist version="1.0"><dict>
#         <key>method</key><string>app-store</string>
#         <key>destination</key><string>export</string>
#         <key>signingStyle</key><string>automatic</string>
#         <key>teamID</key><string>${APPLE_TEAM_ID}</string>
#         <key>uploadSymbols</key><true/>
#       </dict></plist>
#       PLIST
#       xcodebuild -exportArchive \
#         -archivePath "$RUNNER_TEMP/PeachTVPlus.xcarchive" \
#         -exportPath "$RUNNER_TEMP/export" \
#         -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
#         -allowProvisioningUpdates \
#         -authenticationKeyPath "$ASC_KEY_P8_PATH" \
#         -authenticationKeyID "$ASC_KEY_ID" \
#         -authenticationKeyIssuerID "$ASC_ISSUER_ID"
#
#   - name: Téléverser sur TestFlight (xcrun altool)
#     run: |
#       xcrun altool --upload-app -f "$RUNNER_TEMP/export/PeachTVPlus.ipa" -t ios \
#         --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
#       # altool lit la clé .p8 dans ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 :
#       # copier $ASC_KEY_P8_PATH vers ce dossier avant l'appel, nommé AuthKey_$ASC_KEY_ID.p8.
# ------------------------------------------------------------------------------
```

> `-allowProvisioningUpdates` + les trois `-authenticationKey*` = le cœur de la signature
> **sans Mac** (Option A) : Xcode gère cert/profil automatiquement en s'authentifiant par la
> clé d'API. Si tu passes en Option B (`match`), retire `-allowProvisioningUpdates`, dé-commente
> le bloc `match` du `Fastfile`, et laisse les profils gérés signer.

---

## 4. Fastfile / Appfile / Matchfile

Fichiers d'exemple **déjà écrits** et commentés dans `fastlane/` :

- **`fastlane/Fastfile`** — lanes :
  - `tests` : `run_tests` (build + tests simulateur iPhone 15) — doublon pratique de `ci.yml`.
  - `beta` : `app_store_connect_api_key` → `build_app` (archive + export IPA, signature auto par
    clé d'API, Option A) → `upload_to_testflight` (`skip_waiting_for_build_processing`,
    `skip_submission`, testeurs internes). Bloc `match` prêt en commentaire (Option B).
  - `release_appstore` : squelette commenté pour une future soumission App Store publique.
- **`fastlane/Appfile`** — `app_identifier("com.peachtvplus.app")`, `team_id` via `APPLE_TEAM_ID`.
  **Aucun secret** (pas de mot de passe Apple ID : on signe par clé d'API).
- **`fastlane/Matchfile`** — config `match` (Option B) : dépôt git privé des certs, `type
  "appstore"`, `readonly(true)` en CI. À utiliser seulement si tu adoptes `match`.

Lancement local (sur un Mac, ou tel que la CI le fait) :

```bash
bundle exec fastlane tests   # ou: fastlane tests
bundle exec fastlane beta    # nécessite les variables ASC_* + APPLE_TEAM_ID
```

---

## 5. Gestion de version (MARKETING_VERSION / CURRENT_PROJECT_VERSION)

Comme Android injecte `VERSION_NAME`/`VERSION_CODE` depuis l'environnement, on injecte ici les
deux clés Xcode **depuis le tag et le numéro de run**, sans éditer `project.yml` à la main.

| Clé Xcode | Rôle | Source en release | Repli |
|---|---|---|---|
| `MARKETING_VERSION` (`CFBundleShortVersionString`) | version visible (ex. `0.1.0`) | **tag `vX.Y.Z` → `X.Y.Z`**, ou l'input `marketing_version` du dispatch | `0.1.0` de `project.yml` |
| `CURRENT_PROJECT_VERSION` (`CFBundleVersion`) | **build number**, doit être **strictement croissant** pour chaque upload TestFlight du même `MARKETING_VERSION` | **`github.run_number`** (monotone) | `1` |

**Comment l'injection arrive au build** — rendre `project.yml` sensible à l'environnement.
Modifier les deux lignes de `settings.base` pour lire l'env avec repli (XcodeGen substitue
`${VAR}`) :

```yaml
# project.yml — settings.base (remplacer les valeurs fixes actuelles)
settings:
  base:
    MARKETING_VERSION: "${MARKETING_VERSION:-0.1.0}"
    CURRENT_PROJECT_VERSION: "${CURRENT_PROJECT_VERSION:-1}"
    DEVELOPMENT_TEAM: "${DEVELOPMENT_TEAM:-}"   # vide en local, Team ID en CI
```

Le workflow exporte `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` et `DEVELOPMENT_TEAM`
**avant** `xcodegen generate` (étape « Déterminer les versions » + env de l'étape XcodeGen).
En local (dev Windows), les variables sont absentes → les replis `0.1.0` / `1` / `""`
s'appliquent, et `ci.yml` reste vert sans signature.

> Contrainte TestFlight : deux uploads ne peuvent **jamais** partager le même couple
> (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). `github.run_number` garantit l'unicité du
> build number. Pour une **nouvelle version marketing**, pousser un nouveau tag (`v0.2.0`).

---

## 6. Dépendances humaines (ce que SEUL l'utilisateur peut faire)

Aucune de ces actions ne peut être automatisée ni faite par Claude — elles exigent le compte,
un appareil physique ou une décision de l'utilisateur :

1. **Compte Apple Developer Program — 99 $/an.** Obligatoire pour signer et pour TestFlight.
   S'inscrire sur developer.apple.com (vérification d'identité Apple, parfois 24–48 h).
2. **Créer l'app dans App Store Connect** : My Apps → **+** → New App → plateforme iOS,
   nom « PeachTV+ », langue principale **Français (Canada)**, **bundle id `com.peachtvplus.app`**
   (doit déjà exister comme App ID — créé automatiquement par la signature auto, ou
   manuellement dans Certificates, Identifiers & Profiles). Le bundle id est **définitif**.
3. **Générer la clé d'API App Store Connect** (`.p8` + Key ID + Issuer ID), rôle **App Manager**
   (§2.1). Téléchargement **unique** → sauvegarder.
4. **Renseigner les secrets GitHub** (§2.3) à partir de ces valeurs + le **Team ID**.
5. **Pousser `PeachTV+_iPhone/` comme dépôt GitHub autonome** (racine du dépôt = ce dossier),
   car Actions ne lit les workflows **qu'à la racine** d'un dépôt. Le monorepo `git/` n'a pas
   de remote (voir `PORT-SPEC §0`). Vérifier que le `.gitignore` fourni est présent (il l'est)
   pour ne versionner aucun secret.
6. **Groupe de testeurs TestFlight** : dans App Store Connect → TestFlight. Pour un usage perso,
   s'ajouter comme **testeur interne** (membre de l'équipe, pas de revue bêta Apple). Un groupe
   **externe** déclencherait une revue bêta Apple.
7. **Appareil physique** (iPhone et/ou iPad de l'utilisateur) : installer l'app **TestFlight**
   depuis l'App Store, s'y connecter avec le même Apple ID, puis installer PeachTV+ pour la
   recette finale (lecture Live/VOD, catch-up, téléchargement réel, hors-ligne — cf. checklist
   bêta de `PORT-SPEC §9`). Requiert un **compte Xtream réel**.
8. **Accepter les contrats** Apple (Agreements, Tax, Banking — au moins « Free Apps » /
   Paid Apps si un jour payant) dans App Store Connect. Claude ne peut pas accepter de CGU.

---

## 7. Note « App-Store-ready » — passer en public plus tard

L'archi est tenue prête ; voici ce qui s'ajouterait pour une **publication App Store publique**
(pas nécessaire pour TestFlight perso) :

- **Fiche App Store** : description FR, mots-clés, catégorie (Divertissement), URL de support,
  **politique de confidentialité hébergée** (adapter celle d'Android `privacy-policy.html` :
  Keychain au lieu de Tink, pas de Firebase, mentions AirPlay/IMDb).
- **Captures d'écran** requises (6.7″ iPhone + 12.9″/13″ iPad) : automatisables plus tard via
  Fastlane `snapshot` (UI tests) — synergie avec les **snapshot tests** déjà prévus (M6,
  `swift-snapshot-testing`). Lane `release_appstore` + `deliver` (squelette dans le `Fastfile`).
- **Revue App Store renforcée pour les apps IPTV** (même risque qu'Android) : prévoir un
  **compte Xtream de démo** fonctionnel pour les évaluateurs Apple, et un texte de « Review
  notes » expliquant que l'app est un **lecteur** de flux fournis par l'utilisateur (aucun
  contenu hébergé, standards ouverts, aucun DRM contourné).
- **`PrivacyInfo.xcprivacy` (Privacy Manifest)** : requis par Apple. Déclarer les **API à
  raison requise** réellement utilisées — typiquement `UserDefaults` (catégorie `CA92.1` si
  réglages non sensibles), accès **disque/horodatage de fichier** (téléchargements), et
  l'absence de **tracking** (`NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes` vide si
  aucune donnée collectée). À ajouter dans `Sources/PeachTVPlus/` et à référencer dans le bundle
  de ressources via `project.yml`. **Recommandé de l'ajouter dès M6** même pour TestFlight
  (Apple le réclame déjà à l'upload de certaines API).
- **Export compliance** : l'app utilise HTTPS standard → en général « usage exempté ». Déclarer
  `ITSAppUsesNonExemptEncryption = false` dans `Info.plist` pour éviter la question à chaque
  build TestFlight.
- **Contrats Paid/Banking/Tax** si l'app devient payante (frais unique côté Android — décision
  **séparée** sur iOS).

---

## 8. Checklist de mise en place (étape par étape)

**Phase 0 — compte (utilisateur, bloquant) :**
- [ ] S'inscrire au **Apple Developer Program** (99 $/an) et attendre l'activation.
- [ ] Accepter les **Agreements** dans App Store Connect.
- [ ] Noter le **Team ID** (App Store Connect → Membership).

**Phase 1 — dépôt GitHub autonome :**
- [ ] Créer un dépôt **privé** (ex. `peachtv-ios`) et pousser le **contenu de
      `PeachTV+_iPhone/`** à la **racine** (le `.github/` s'active alors).
- [ ] Vérifier que `ci.yml` passe au **vert** (M0 : build + tests simulateur).
- [ ] Confirmer que `.gitignore` bloque bien secrets et `.xcodeproj` (déjà le cas).

**Phase 2 — clé d'API + secrets :**
- [ ] Générer la **clé d'API App Store Connect** (rôle App Manager) → `.p8` + Key ID + Issuer ID.
- [ ] Encoder le `.p8` en **base64** (§2.3) ; renseigner les 4 secrets GitHub obligatoires
      (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
      `APP_STORE_CONNECT_API_KEY`, `APPLE_TEAM_ID`). Supprimer les fichiers temporaires.

**Phase 3 — versionnage + release :**
- [ ] Appliquer la modif `project.yml` (§5 : `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`/
      `DEVELOPMENT_TEAM` lus depuis l'env avec replis).
- [ ] Ajouter `.github/workflows/release.yml` (§3) et `fastlane/` (déjà écrit).
- [ ] Créer l'app dans **App Store Connect** (bundle `com.peachtvplus.app`).
- [ ] Déclencher une première release : `git tag v0.1.0 && git push origin v0.1.0`
      (ou **Run workflow** → `release.yml` avec `marketing_version = 0.1.0`).
- [ ] Vérifier dans App Store Connect → TestFlight que le build apparaît et finit son traitement.

**Phase 4 — recette appareil :**
- [ ] S'ajouter comme **testeur interne** ; installer **TestFlight** sur iPhone/iPad.
- [ ] Installer PeachTV+, dérouler la **checklist bêta** (`PORT-SPEC §9`) avec un **compte
      Xtream réel** : lecture Live/VOD, catch-up, téléchargement + hors-ligne, 2 h stables.

**Phase 5 (plus tard) — App Store public :**
- [ ] Ajouter `PrivacyInfo.xcprivacy` + `ITSAppUsesNonExemptEncryption`.
- [ ] Fiche + captures (Fastlane `snapshot`/`deliver`) + compte Xtream de **démo** pour la revue.
- [ ] Activer la lane `release_appstore`.

---

*Document maintenu par le rôle QA / CI / Déploiement (voir `PORT-SPEC §10`). Toute décision de
signature / release est consignée ici. Rien ne compile sous Windows : tout est validé par la CI
macOS.*

---

## 9. ⚠️ MISE À JOUR (M7, 2026-11-13) — release réelle via **Codemagic**, pas GitHub Actions

**Correction importante** : les §1–§3 supposent des runners **GitHub Actions `macos-14`**. En
pratique, **GitHub n'alloue AUCUN runner macOS hébergé à ce compte** (file d'attente indéfinie,
constaté 2026-11). Tout le build macOS — **y compris la release TestFlight** — tourne donc sur
**Codemagic** (runners Apple Silicon, tier gratuit). Le `release.yml` GitHub du §3 **ne tournerait
jamais** : on ne l'ajoute pas. `.github/workflows/ci.yml` ne garde que les règles de sécurité (Linux).

### 9.1 Ce qui est déjà en place (prépa M7 livrée)

- **`codemagic.yaml` → workflow `ios-testflight`** : déclenché **sur tag `v*`**, re-joue les règles
  de sécurité, `xcodegen generate`, résout SPM, puis lance **`fastlane beta`** (archive signée par
  clé d'API + envoi TestFlight). Le workflow `build-test` (push/PR) reste la porte de qualité.
- **`fastlane/Fastfile`** : lane `beta` inchangée dans l'esprit (Option A, clé d'API) + **injection
  de version** résolue — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` passés en **réglages de
  build** (`xcargs`) depuis l'environnement, car **XcodeGen ne sait pas écrire `${VAR:-défaut}`**
  dans `project.yml` (c'est pourquoi le §5 n'est PAS appliqué tel quel ; l'override au build le
  remplace).
- **Manifeste de confidentialité** `Sources/PeachTVPlus/PrivacyInfo.xcprivacy` (aucun tracking,
  aucune collecte ; API à raison requise : `UserDefaults` CA92.1, Espace disque E174.1) + **conformité
  export** `ITSAppUsesNonExemptEncryption = false` dans `project.yml`. Requis par Apple à l'upload.
- **Brouillons** : `docs/privacy-policy.md` (à héberger → URL dans la fiche) et
  `docs/app-store-listing.md` (fiche + notes de revue IPTV).

### 9.2 Secrets côté Codemagic (au lieu des secrets GitHub du §2.3)

Dans l'UI Codemagic → **Environment variables** → groupe **`appstore_credentials`** (tout en
« secure ») :

| Variable | Contenu |
|---|---|
| `ASC_KEY_ID` | Key ID de la clé d'API App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID du compte |
| `ASC_KEY_P8_B64` | contenu du `.p8` **encodé base64** (une ligne — voir §2.3 pour l'encodage) |
| `APPLE_TEAM_ID` | Team ID (10 car.) |

Le workflow décode `ASC_KEY_P8_B64` en un fichier `.p8` sur le runner (jamais versionné) et
expose `ASC_KEY_P8_PATH` au `Fastfile`.

### 9.3 Déclencher une release

1. S'assurer que `build-test` (Codemagic) est **vert** sur `main`.
2. Créer un **tag `v0.1.0`** sur le dépôt GitHub `red1140-hub/PeachTVPlus-iPhone` — p.ex.
   `gh release create v0.1.0 --target main` (ou l'UI GitHub). Codemagic détecte le tag et lance
   `ios-testflight`.
3. Vérifier dans App Store Connect → TestFlight que le build apparaît et finit son traitement.

### 9.4 Reste strictement humain (bloquant — cf. §6)

Compte **Apple Developer (99 $/an)**, création de l'app dans **App Store Connect** (bundle
`com.peachtvplus.app`), génération de la **clé d'API** (rôle App Manager), **héberger** la
politique de confidentialité, s'ajouter en **testeur interne**, et la **recette sur appareil**
(iPhone/iPad réels + **compte Xtream réel**). Claude ne peut ni créer le compte, ni accepter les
contrats, ni téléverser à ta place.

### 9.5 Reporté explicitement

- **Snapshot tests visuels** (`swift-snapshot-testing`) : nécessitent un **Mac** pour enregistrer
  les images de référence (sinon CI rouge au 1er run). À faire dans une session avec Mac ; ils
  alimenteront aussi les **captures d'écran** via Fastlane `snapshot` pour la publication publique.
- Lane `release_appstore` + `deliver` (App Store **public**) : squelette prêt, à activer plus tard.
