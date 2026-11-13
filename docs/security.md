# Sécurité — PeachTV+ iOS / iPadOS

> Spec de sécurité **actionnable** pour le portage natif **Swift/SwiftUI** (iOS 17+) du
> lecteur IPTV Android PeachTV+ (client **Xtream Codes**, téléchargement hors-ligne).
> Référence faisant autorité pour le jalon **M2** (Sécurité) et pour la **revue avant
> release** (TestFlight, puis futur passage App Store).
>
> **Source** : porte `../mytv-player/docs/security.md`, l'audit
> `../mytv-player/docs/security-audit-2026-10.md` (2 HIGH + mediums déjà identifiés côté
> Android) et `docs/PORT-SPEC.md` §3/§5/§6. **⚠️ `../mytv-player` est en LECTURE SEULE.**
>
> **Posture** (identique à Android) : app grand public, usage personnel. Pas de secret
> serveur à protéger, pas de conformité bancaire. On protège **les identifiants de
> l'abonné** (souvent réutilisés ailleurs) et **sa vie privée** (ce qu'il regarde). On
> refuse l'amateurisme (identifiants en clair, logs qui fuient, `TrustAll`) sans tomber
> dans la paranoïa inadaptée (pinning rigide sur des serveurs Xtream tiers).
>
> **Standards ouverts** : aucun DRM contourné. Mapping **OWASP MASVS** indiqué par section.
> Dernière mise à jour : **2026-11-12**.

---

## 0. Modèle de menaces (rappel) et correspondance iOS

| Menace | Vecteur iOS concret | Atténuation (section) |
|---|---|---|
| Réseau actif (MITM) | HTTP clair Xtream sur Wi-Fi public ; downgrade HTTPS→HTTP | §4 (ATS + consentement + anti-downgrade) |
| Serveur IPTV hostile | JSON/EPG/titres/images = données non fiables ; SSRF local via schéma d'URL | §7 (données hostiles), §4.4 (allowlist schéma) |
| Vol / perte d'appareil | Secrets au repos, sauvegarde iCloud/chiffrée, aperçu multitâche | §1, §2, §5, §6 |
| Autre app / forensique | Fichiers lisibles, base avec secret, backup exfiltré | §1 (Keychain ThisDeviceOnly), §5 (exclusion backup) |
| Fuite passive | `print`/`os_log` d'URL brute, crash reports, captures | §3 (redaction + CI) |

**Correspondance MASVS** (v2) utilisée : **STORAGE** (§1, §2, §5), **CRYPTO** (§2),
**NETWORK** (§4), **PLATFORM** (§6, §7), **CODE/RESILIENCE** (§3, CI), **PRIVACY** (§8).

**Spécificités iOS vs Android (ce qui change) :**
- Le **bac à sable** iOS est plus strict ; le stockage app (`Application Support`,
  `Caches`, `tmp`) est privé par défaut. Le risque principal au repos n'est donc **pas**
  une autre app, mais la **sauvegarde** (iCloud / backup chiffré iTunes/Finder) et le vol.
- Pas de `FLAG_SECURE` fiable → la protection « aperçu multitâche / capture » passe par
  `scenePhase` + overlay (§6), pas par un drapeau système.
- Clé matérielle = **Secure Enclave** (via Keychain `kSecAttrAccessControl`), équivalent
  du StrongBox/Keystore Android.

---

## 1. Stockage des identifiants Xtream — Keychain
**MASVS-STORAGE-1 / STORAGE-2.**

**Règle absolue (comme Android) : jamais en clair.** Pas de `UserDefaults`, pas de `.plist`,
pas de fichier JSON/texte, pas en dur dans le binaire, pas dans la base GRDB.

### 1.1 Pourquoi PAS `UserDefaults` / fichier clair
- `UserDefaults` s'écrit en **`.plist` lisible** dans `Library/Preferences/` — récupérable
  par backup iTunes/Finder, par un outil forensique, et inclus dans la sauvegarde iCloud.
  Ce serait l'équivalent exact du bug Android H1 (identifiants en clair sur disque).
- Un fichier « chiffré maison » dans le sandbox a le même défaut que côté Android : la clé
  doit bien vivre quelque part → autant utiliser le Keychain, qui adosse la clé à la
  **Secure Enclave** et applique une classe de protection liée au déverrouillage.

### 1.2 Pourquoi PAS la synchronisation iCloud
- `kSecAttrSynchronizable = true` pousserait les identifiants dans le **trousseau iCloud**
  (autres appareils, serveurs Apple). Contraire à la posture « vie privée, ce device
  seulement » et à l'esprit du `...ThisDeviceOnly` d'Android (`allowBackup=false`).
- On impose donc **`kSecAttrSynchronizable = false`** ET
  **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** :
  - `AfterFirstUnlock` : lisible par les tâches de fond (reprise d'un téléchargement
    `URLSession .background` après reboot, avant déverrouillage interactif — cf. §6).
  - `ThisDeviceOnly` : **jamais** migré vers un nouvel appareil ni sauvegardé → une
    restauration de backup n'emporte pas les secrets (défense en profondeur).
  - On n'utilise **pas** `WhenUnlocked` (casserait les DL en fond) ni `...WhenPasscodeSet`
    comme défaut (l'app doit marcher sans code — on l'offre en option biométrique, §6.4).

### 1.3 Wrapper d'API — `KeychainStore`
Un unique point d'accès (équivalent du `SecureSessionStore` Android). Pas de framework
tiers : `Security.framework` suffit.

```swift
import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)   // échec transitoire ou permanent du Keychain
    case decodingFailed               // blob présent mais corrompu / illisible
    case notFound
}

/// Accès centralisé au trousseau. Un seul écrivain pour les secrets (règle un-seul-écrivain).
/// Classe de protection : AfterFirstUnlockThisDeviceOnly, jamais synchronisé iCloud.
struct KeychainStore {

    private let service: String

    init(service: String = "com.peachtvplus.app.credentials") {
        self.service = service
    }

    /// Écrit (ou remplace) un blob opaque sous `account`.
    func set(_ data: Data, account: String) throws {
        // Supprimer l'éventuelle entrée existante : SecItemAdd échoue sur doublon (errSecDuplicateItem).
        SecItemDelete(baseQuery(account) as CFDictionary)

        var attrs = baseQuery(account)
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse   // JAMAIS iCloud

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Lit le blob, ou nil si absent. Distingue « absent » d'« erreur » (important pour la
    /// migration non destructive : ne RIEN effacer sur une erreur transitoire — cf. §2.3).
    func get(account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.decodingFailed }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)   // NE PAS interpréter comme « vide »
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse,   // cohérent lecture/écriture
        ]
    }
}
```

**Codes d'erreur à connaître** (ils pilotent la logique de migration du §2.3) :
- `errSecSuccess (0)` — OK.
- `errSecItemNotFound (-25300)` — **absence** légitime (1er lancement) → **pas** une erreur.
- `errSecDuplicateItem (-25299)` — doublon à l'ajout → on fait `SecItemDelete` avant `Add`.
- `errSecInteractionNotAllowed (-25308)` — appareil **verrouillé** pour cette classe de
  protection → **transitoire**, ne jamais effacer le secret (surtout en tâche de fond).
- `errSecAuthFailed (-25293)` — échec d'authentification (si contrôle biométrique) →
  transitoire côté utilisateur, pas une corruption.
- `errSecDecode` / blob illisible → `KeychainError.decodingFailed` : **permanent**.

### 1.4 Le mot de passe est un secret, pas un champ d'écran
- Jamais affiché par défaut. L'écran Réglages le **révèle à la demande** (comme Android :
  `revealPassword()`), puis **auto-masque** (timer ~15 s + au passage en arrière-plan). Voir §6.3.
- `description`/`debugDescription` de `XtreamCredentials` **ne divulguent jamais** le mot de
  passe (leçon audit Android L3 : le `toString()` d'une `data class` fuitait le champ).

```swift
struct XtreamCredentials: Equatable {
    let serverUrl: String      // normalisé scheme://host[:port], sans slash final (cf. PORT-SPEC §3.4)
    let username: String
    let password: String

    var isSecure: Bool { serverUrl.lowercased().hasPrefix("https://") }
}

extension XtreamCredentials: CustomStringConvertible {
    // Ne JAMAIS laisser le mot de passe atteindre un log via l'interpolation par défaut.
    var description: String { "XtreamCredentials(server: \(serverUrl), user: \(username), pass: ***)" }
}
```

### 1.5 Hygiène
- **Rien** du Keychain n'est jamais copié dans `UserDefaults`, GRDB, un log, un crash report.
- Effacement réel à la déconnexion (§8) : `remove(account:)` sur le blob, pas seulement un flag.

---

## 2. Chiffrement du store multi-listes
**MASVS-STORAGE-1, MASVS-CRYPTO-1/2.**

Le store multi-listes (`{activeId, items[{id, serverUrl, username, password}]}`, cf.
PORT-SPEC §4) **contient plusieurs mots de passe** → c'est le secret central.

### 2.1 Deux options, une recommandée

**Option A — Keychain pur (RECOMMANDÉE).** Sérialiser le store en JSON (`Codable`) et
l'écrire comme **un seul blob** via `KeychainStore.set(_:account:)` (compte
`xtream_playlists_v2`). Avantages : aucune gestion de clé manuelle (la Secure Enclave et la
classe de protection s'en chargent), surface minimale, mapping 1:1 avec le `SecureSessionStore`
Tink v2 d'Android. **C'est le choix par défaut** pour PeachTV+ iOS.

```swift
struct PlaylistStore: Codable, Equatable {
    var activeId: String
    var items: [PlaylistEntry]
}
struct PlaylistEntry: Codable, Equatable {
    let id: String
    let serverUrl: String
    let username: String
    let password: String
}

/// Persistance chiffrée des listes (Keychain pur). Équivalent iOS du SecureSessionStore Tink v2.
final class SecurePlaylistStore {
    private let keychain: KeychainStore
    private let account = "xtream_playlists_v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: KeychainStore = .init()) { self.keychain = keychain }

    func load() throws -> PlaylistStore? {
        guard let data = try keychain.get(account: account) else { return nil }  // nil = absent, PAS vide
        do { return try decoder.decode(PlaylistStore.self, from: data) }
        catch { throw KeychainError.decodingFailed }   // échec PERMANENT (cf. §2.3)
    }

    func save(_ store: PlaylistStore) throws {
        try keychain.set(try encoder.encode(store), account: account)
    }

    func clear() throws { try keychain.remove(account: account) }
}
```

**Option B — CryptoKit AES-GCM + clé Keychain.** À réserver si un jour le store devient trop
gros pour un blob Keychain confortable, ou si on veut séparer *métadonnées* (en GRDB) et
*secrets* (chiffrés) : on génère une **`SymmetricKey` 256 bits** stockée dans le Keychain
(classe `...ThisDeviceOnly`), et on chiffre la charge avec `AES.GCM` (AEAD authentifié,
équivalent exact de l'`AES256_GCM` Tink d'Android).

```swift
import CryptoKit

enum PlaylistCipher {
    /// AEAD AES-256-GCM. La clé vit dans le Keychain (jamais en clair, jamais dans le code).
    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.seal(plaintext, using: key).combined!   // nonce|ciphertext|tag
    }
    static func open(_ combined: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
    }
}
```
> Jamais d'ECB/CBC maison, jamais de clé codée en dur, jamais de nonce réutilisé (GCM le gère
> via `combined`). Ne pas réinventer de crypto.

### 2.2 Migration non destructive (comme Android v1→v2)
Si une version antérieure a écrit un blob « legacy » (clé/format différent), le lire **une
fois** avec l'ancien schéma, puis **réécrire** au format courant à la première écriture. La
session utilisateur n'est **jamais** perdue par la migration.

### 2.3 N'effacer QUE sur échec **permanent** (règle critique, portée d'Android)
C'est la leçon la plus importante du `SecureSessionStore` Android : **ne pas confondre un
raté transitoire du Keychain avec une corruption**.

| Situation | Statut | Action |
|---|---|---|
| `errSecItemNotFound` | absence légitime | retourner `nil`, ne rien effacer |
| `errSecInteractionNotAllowed`, `errSecAuthFailed`, autre OSStatus | **transitoire** | **ne RIEN effacer** ; réessayer plus tard ; dégrader proprement |
| `KeychainError.decodingFailed` (blob présent mais indécodable) | **permanent** | effacer et repartir propre (sinon boucle d'échec) |

> Effacer les listes sur un simple échec transitoire déconnecterait l'utilisateur à tort
> (exactement le bug qu'Android a pris soin d'éviter : effacement seulement sur
> `AEADBadTag`/sérialisation/base64).

---

## 3. Redaction centralisée des logs
**MASVS-STORAGE-2, MASVS-PRIVACY-3.**

Les URL Xtream portent les identifiants **à deux endroits** : la query
(`?username=…&password=…`) **et** le chemin (`/live/USER/PASS/123.ts`,
`/movie/…`, `/series/…`, `/timeshift/…`). Les logger verbatim fuite le compte.

### 3.1 Règle
- **Aucun `print` ni `os_log`/`Logger` d'URL brute.** Tout log réseau passe par
  `RedactingLogger`. Interdit : `print(url)`, `Logger().debug("\(url)")`, `po request`.
- On logue **l'action et l'hôte**, jamais la query d'auth ni les segments user/pass.
- Pas de log réseau détaillé en **release** (niveau silencieux) ; même en debug, redaction active.

### 3.2 `RedactingLogger` (port fidèle du `RedactingHttpLogger` Android)
Mêmes deux regex, **plus `timeshift`** dès le départ (Android avait un bug L1 : `timeshift`
manquait à l'alternance — on le corrige nativement ici).

```swift
import OSLog

/// Masque les identifiants Xtream dans toute chaîne avant journalisation.
/// Port de RedactingHttpLogger.kt (+ correctif L1 : `timeshift` inclus d'emblée).
enum RedactingLogger {

    private static let subsystem = "com.peachtvplus.app"
    private static let net = Logger(subsystem: subsystem, category: "net")

    // username=... / password=... (query) → ***
    private static let queryCreds = try! NSRegularExpression(
        pattern: "(username|password)=([^&\\s]+)", options: [.caseInsensitive])
    // /live|movie|series|timeshift/USER/PASS/ (path) → /live/***/***/
    private static let pathCreds = try! NSRegularExpression(
        pattern: "/(live|movie|series|timeshift)/[^/]+/[^/]+/", options: [.caseInsensitive])

    static func redact(_ message: String) -> String {
        let range = NSRange(message.startIndex..., in: message)
        var out = queryCreds.stringByReplacingMatches(
            in: message, range: range, withTemplate: "$1=***")
        let r2 = NSRange(out.startIndex..., in: out)
        out = pathCreds.stringByReplacingMatches(
            in: out, range: r2, withTemplate: "/$1/***/***/")
        return out
    }

    /// Seul point de journalisation réseau autorisé.
    static func net(_ message: String) {
        #if DEBUG
        net.debug("\(redact(message), privacy: .public)")
        #endif
        // En release : rien (ou .error pour les seules erreurs, déjà expurgées).
    }
}
```
> Note `os_log`/`Logger` : par défaut les interpolations non annotées sont **privées**
> (`<private>`). On **expurge d'abord** puis on marque `.public` — on ne compte jamais sur
> `.private` pour cacher un secret (il réapparaît en clair sur une machine de dev liée).

### 3.3 Crash reports / diagnostics
- **Aucun** identifiant ni URL d'auth dans un rapport de crash (si MetricKit/crash tiers un
  jour) : filtrer toute exception/chaîne contenant une URL via `RedactingLogger.redact`.
- Le **journal de diagnostic** in-app (port du `DiagnosticLog` Android) ne logue que des
  chemins **déjà porteurs du marqueur `__cred__`** ou expurgés — jamais une URL résolue.

### 3.4 Règle CI (grep) — fait **échouer** la build
Portée telle quelle dans `.github/workflows/ci.yml` (étape Linux, avant macOS).
`#print|URL dans un logger` interdits hors du redactor lui-même.

```bash
# --- CI: aucune URL/secret brut vers un logger, aucun print d'URL ---
set -euo pipefail
SRC="Sources"

# 1) print()/NSLog() d'une variable d'URL
if grep -rnE '(print|NSLog)\s*\(.*\b(url|URL|serverUrl|streamUrl)\b' "$SRC"; then
  echo "❌ print/NSLog d'une URL détecté"; exit 1; fi

# 2) Logger/os_log recevant une URL hors du redactor
if grep -rnE '(Logger|os_log|\.debug|\.info|\.error)\(.*\b(url|URL|password|username)\b' "$SRC" \
     | grep -v 'RedactingLogger'; then
  echo "❌ URL/identifiant journalisé sans redaction"; exit 1; fi

echo "✅ Logs: aucune fuite d'URL/secret"
```

---

## 4. Réseau — ATS, consentement HTTP, anti-downgrade, allowlist
**MASVS-NETWORK-1/2.**

### 4.1 ATS : `NSAllowsArbitraryLoads = true` toléré au build, clair **bloqué par le code**
Beaucoup de panneaux Xtream ne servent qu'en **HTTP** et le serveur n'est connu **qu'à
l'exécution** → on ne peut pas lister les domaines autorisés dans `Info.plist` au build.
C'est l'équivalent exact du dilemme `network_security_config.xml` d'Android.

- **Décision** (parité avec l'approche A d'Android) : `Info.plist` autorise le clair en
  dernier recours, mais le **garde-fou vit dans le code** : l'app n'envoie **jamais** les
  identifiants en HTTP sans consentement **par serveur** (§4.2). ATS n'est pas la ligne de
  défense ; le code l'est.

```xml
<!-- Info.plist -->
<key>NSAppTransportSecurity</key>
<dict>
  <!-- Toléré : les serveurs Xtream HTTP-only existent et ne sont connus qu'au runtime.
       La protection réelle (HTTPS-first + consentement par serveur) est dans le code. -->
  <key>NSAllowsArbitraryLoads</key><true/>
</dict>
```
> **Ne pas** ajouter `NSAllowsLocalNetworking`/exceptions inutiles. Pour un futur passage App
> Store, documenter la justification ATS (requis par Apple pour `ArbitraryLoads`).

### 4.2 Consentement HTTP **par serveur** (MUST — c'était un MUST manqué côté Android, M2 audit)
- Au login : **normaliser en `https://` et l'essayer d'abord**. En cas d'échec réseau/TLS
  seulement, proposer le repli HTTP via un **dialogue de consentement non pré-coché**.
- **Ne jamais** transmettre les identifiants en clair tant que l'utilisateur n'a pas consenti
  pour **ce serveur précis**.
- Décision **persistée par serveur** (clé = host[:port]) et **révocable** dans les Réglages.
- **Badge persistant** « connexion non sécurisée » visible tant que la liste active est en HTTP.

```swift
/// Garde-fou applicatif : HTTPS d'abord, HTTP seulement après consentement explicite par serveur.
@Observable
final class CleartextConsent {
    private let defaults = UserDefaults.standard          // décision NON sensible (pas un secret)
    private func key(_ host: String) -> String { "cleartext.consent.\(host)" }

    func hasConsented(host: String) -> Bool { defaults.bool(forKey: key(host)) }
    func grant(host: String) { defaults.set(true, forKey: key(host)) }
    func revoke(host: String) { defaults.removeObject(forKey: key(host)) }

    /// À appeler AVANT tout envoi d'identifiants. `false` ⇒ bloquer et demander le consentement.
    func maySendCredentials(to url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        if scheme == "http", let host = url.host { return hasConsented(host: host) }
        return false   // autre schéma : jamais (cf. §4.4)
    }
}
```
> Le simple `host` (sans user/pass) **n'est pas un secret** → `UserDefaults` est acceptable
> pour la *décision* de consentement. Les **identifiants**, eux, restent au Keychain (§1).

### 4.3 Anti-downgrade HTTPS→HTTP (port du medium M3 Android)
Un serveur hostile peut répondre à une requête HTTPS par une **redirection vers `http://`**.
Comme les identifiants sont **dans le chemin**, le strip d'en-tête ne protège pas → on
**refuse** le passage HTTPS→HTTP via `URLSessionTaskDelegate`.

```swift
final class AntiDowngradeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let from = task.originalRequest?.url?.scheme?.lowercased()
        let to = request.url?.scheme?.lowercased()
        if from == "https", to == "http" {
            RedactingLogger.net("Redirection HTTPS→HTTP refusée pour \(request.url?.absoluteString ?? "")")
            completionHandler(nil)   // annule la redirection : pas de downgrade silencieux
        } else {
            completionHandler(request)
        }
    }
}
```
> **Interdit** de désactiver/affaiblir la validation TLS (voir §4.5). Idéalement, refuser
> aussi toute redirection vers un **hôte ≠ serveur configuré** (anti-exfiltration du flux).

### 4.4 Allowlist de schémas (anti-SSRF local)
Toute URL de flux/téléchargement/image est validée **avant** usage : schéma ∈ {`http`,
`https`} uniquement. Rejet de `file:`, `data:`, `content:`, `javascript:`, `ftp:`, etc. —
sinon un serveur hostile ferait lire un fichier local.

```swift
enum URLGuard {
    static let allowed: Set<String> = ["http", "https"]

    static func isPlayable(_ url: URL) -> Bool {
        guard let s = url.scheme?.lowercased(), allowed.contains(s), url.host != nil else { return false }
        return true
    }
}
```

### 4.5 Interdiction formelle de tout `URLSessionDelegate` TrustAll (règle CI)
On s'appuie sur la **validation de chaîne standard** d'`URLSession`. **Jamais** de
`urlSession(_:didReceive:completionHandler:)` qui appelle
`.useCredential` avec `URLCredential(trust:)` sans vérification, ni
`SecTrustSetExceptions`/`.performDefaultHandling` contourné. **Pas de pinning** (serveurs
Xtream tiers, certs Let's Encrypt renouvelés tous les 90 j — pinner casserait l'app, même
raisonnement qu'Android).

```bash
# --- CI: aucun contournement TLS (fait échouer la build) ---
set -euo pipefail
SRC="Sources"
PATTERNS='URLCredential\(trust:|serverTrust|\.cancelAuthenticationChallenge|NSExceptionAllowsInsecureHTTPLoads|kCFStreamSSLValidatesCertificateChain|allowsAnyHTTPSCertificate'
if grep -rnE "$PATTERNS" "$SRC"; then
  echo "❌ Contournement TLS / trust-all potentiel détecté"; exit 1; fi
echo "✅ TLS: validation standard, aucun trust-all"
```

### 4.6 Garde-fou d'hôte sur la réinjection du marqueur `__cred__` (anti-fuite cross-serveur)
Port **direct** du `CredentialInjectionInterceptor` Android (revue sécurité v1.03). Les URL
de téléchargement sont **persistées sans identifiants** (marqueur `__cred__` à la place de
user/pass — cf. PORT-SPEC §3.1/§6). On réinjecte les identifiants **en mémoire, juste avant
la requête**, **et seulement si l'hôte/port/schéma de l'URL correspond à la liste
propriétaire du téléchargement**. Sinon (DL d'une autre liste repris après une bascule), on
**ne révèle rien** — sinon on enverrait les identifiants de la liste active vers un **autre
serveur** (fuite).

```swift
/// Réinjecte user/pass dans une URL de téléchargement `__cred__`, avec garde-fou d'hôte.
/// Retourne nil ⇒ requête à BLOQUER (aucun identifiant exposé).
enum CredentialInjector {
    static let placeholder = "__cred__"

    static func inject(into stored: URL, using creds: XtreamCredentials) -> URL? {
        let marker = "/\(placeholder)/\(placeholder)/"
        guard stored.path.contains(marker) else { return stored }   // URL normale : telle quelle

        // Garde-fou d'hôte : l'URL stockée doit viser le serveur de SA liste.
        guard let expected = URLComponents(string: creds.serverUrl),
              let got = URLComponents(url: stored, resolvingAgainstBaseURL: false),
              got.host?.lowercased() == expected.host?.lowercased(),
              got.port == expected.port,
              got.scheme?.lowercased() == expected.scheme?.lowercased()
        else {
            RedactingLogger.net("DL: hôte \(stored.host ?? "?") ≠ liste active — identifiants NON injectés")
            return nil   // bloquer (équivalent du 409 local Android)
        }

        let enc = CharacterSet.urlPathAllowed
        let u = creds.username.addingPercentEncoding(withAllowedCharacters: enc) ?? creds.username
        let p = creds.password.addingPercentEncoding(withAllowedCharacters: enc) ?? creds.password
        return URL(string: stored.absoluteString.replacingOccurrences(of: marker, with: "/\(u)/\(p)/"))
    }
}
```
> L'URL **persistée** (table `downloads`, clé de cache) ne contient donc **jamais** de
> secret. On persiste la forme `__cred__` et on réinjecte au (re)lancement de la tâche.

---

## 5. Téléchargements — noms locaux, exclusion backup, zéro secret sur disque
**MASVS-STORAGE-1/2, MASVS-PLATFORM-2.**

### 5.1 Emplacement sandbox
- Fichiers dans **`Application Support/Downloads/`** (persistant, privé, hors `Caches` que le
  système peut purger). Jamais le dossier Documents exposé à Fichiers/iTunes si on ne veut
  pas que l'utilisateur voie/exporte les médias (ne pas déclarer `UIFileSharingEnabled`).

### 5.2 Nom de fichier généré **localement** (anti path-traversal)
**Ne jamais** dériver le nom d'un champ serveur (titre, nom de fichier renvoyé). Générer
depuis l'`id` local (UUID ou hash de `streamId`), extension dans une allowlist ; stocker le
« joli » titre en **métadonnée GRDB**. Puis **vérifier le `canonicalPath`** sous le dossier
cible (défense en profondeur contre un `..`).

```swift
enum DownloadPaths {
    static let allowedExt: Set<String> = ["mp4", "mkv", "ts", "m4v", "mov"]

    static func localURL(for streamId: String, ext rawExt: String) throws -> URL {
        let ext = allowedExt.contains(rawExt.lowercased()) ? rawExt.lowercased() : "mp4"
        // Nom 100% local : aucune donnée serveur dans le chemin.
        let safeName = "\(abs(streamId.hashValue))-\(UUID().uuidString).\(ext)"

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let candidate = base.appendingPathComponent(safeName)
        // Garde-fou canonicalPath : le fichier doit rester SOUS le dossier cible.
        let baseReal = base.standardizedFileURL.resolvingSymlinksInPath().path
        let candReal = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        guard candReal.hasPrefix(baseReal + "/") else { throw URLError(.badURL) }
        return candidate
    }
}
```

### 5.3 Exclusion de la sauvegarde iCloud (`isExcludedFromBackup`)
Équivalent du `allowBackup=false` + exclusions Android (H2 : la base DL doit sortir du
backup). On exclut **le dossier Downloads ET la base GRDB** de la sauvegarde iCloud/chiffrée.

```swift
extension URL {
    mutating func excludeFromBackup() throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try setResourceValues(values)   // à (ré)appliquer après (re)création du dossier/fichier
    }
}
// Appliquer sur: Application Support/Downloads/  ET  le fichier GRDB (ex. catalogue.sqlite).
```

### 5.4 Zéro secret sur disque
- La tâche `URLSession` reçoit l'URL **réelle en mémoire** (réinjection §4.6) ; on **persiste
  uniquement** la forme `__cred__` dans la table `downloads` (état, %, octets, `resumeData`,
  chemin local, URL `__cred__`).
- `resumeData` d'`URLSession` peut contenir l'URL d'origine : on ne persiste `resumeData` que
  pour des tâches dont l'URL stockée est déjà en `__cred__` (le secret n'y est donc pas). Si
  un jour `resumeData` devait porter un secret, le chiffrer (§2 option B) — à vérifier sur device.
- Nettoyage orphelins au démarrage (fichiers sans ligne en base → suppression réelle).

---

## 6. Protection de l'UI (arrière-plan, aperçu multitâche, révélation, biométrie)
**MASVS-PLATFORM-3, MASVS-STORAGE-7.**

Pas de `FLAG_SECURE` fiable sur iOS → on reproduit l'intention (bloquer capture + masquer
l'aperçu des tâches récentes) par le cycle de vie SwiftUI.

### 6.1 Overlay au passage en arrière-plan (`scenePhase == .inactive`)
iOS fait une **capture de l'écran** quand l'app passe en arrière-plan (pour l'aperçu
multitâche) : au moment `.inactive`, on **recouvre** le contenu sensible (login, Réglages
avec identifiants) d'un overlay opaque (logo sur fond noir) → la vignette ne montre aucun
secret.

```swift
struct PrivacyShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {               // .inactive (snapshot) ET .background
                Color.black.ignoresSafeArea()
                    .overlay(Image("PeachTVLogo").accessibilityHidden(true))
            }
        }
    }
}
extension View {
    /// À appliquer aux écrans sensibles (login, Réglages/identifiants).
    func privacyShielded() -> some View { modifier(PrivacyShield()) }
}
```

### 6.2 Pas de mot de passe dans l'aperçu multitâche
- Les champs mot de passe utilisent `SecureField` (masqués, pas d'autofill de contenu non
  voulu, exclus des captures texte).
- L'écran de login et le formulaire d'ajout de liste sont `privacyShielded()` (overlay §6.1)
  — équivalent du « ajout de liste sous FLAG_SECURE » d'Android.

### 6.3 Révélation à la demande + auto-masquage
Port de `revealPassword()` Android : le mot de passe n'est **jamais** gardé affiché ; révélé
au tap, **auto-masqué** après ~15 s **et** dès `scenePhase != .active`.

```swift
@Observable
final class PasswordReveal {
    private(set) var isRevealed = false
    private var task: Task<Void, Never>?

    func reveal() {
        isRevealed = true
        task?.cancel()
        task = Task { try? await Task.sleep(for: .seconds(15)); await MainActor.run { self.isRevealed = false } }
    }
    func hide() { task?.cancel(); isRevealed = false }   // appeler aussi sur scenePhase != .active
}
```

### 6.4 Option Face ID / Touch ID (NICE)
`LocalAuthentication` pour exiger une authentification biométrique **avant de révéler** les
identifiants (option Réglages). Le contexte biométrique **ne stocke pas** le secret ; il
**garde** l'accès à l'écran, le Keychain reste la source.

```swift
import LocalAuthentication

func authenticateToReveal() async -> Bool {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
    return (try? await ctx.evaluatePolicy(
        .deviceOwnerAuthentication,              // biométrie, repli code appareil
        localizedReason: "Afficher les identifiants de la liste de lecture")) ?? false
}
```
> Ajouter `NSFaceIDUsageDescription` à l'`Info.plist`. Ne jamais bloquer le fonctionnement de
> l'app sur la biométrie — c'est une **option** pour révéler les secrets, pas une porte d'entrée.

---

## 7. Données hostiles du serveur (EPG, titres, images)
**MASVS-PLATFORM-1, MASVS-CODE-4.**

Tout ce qui vient du serveur = **données à afficher, jamais à interpréter**.

- **Texte (titres, descriptions, catégories, EPG)** : rendu via `Text` SwiftUI uniquement.
  **Aucun** rendu HTML/Markdown actif, **aucune** `WebView` (comme Android : toute la classe
  « pont JS » est absente). Neutraliser les caractères de contrôle, borner la longueur affichée.
- **Parsing défensif** : `Codable` + `FlexibleString` (PORT-SPEC §3.2) ; chaque décodage en
  **`do/catch`**, dégradation propre (catégorie vide, item ignoré), **jamais** de crash sur
  JSON malformé. **Pas** de parseur XML à DTD/entités externes actives (anti-XXE) si un jour
  on parse du XMLTV — `XMLParser` avec `shouldResolveExternalEntities = false` (défaut).
- **Images (affiches, logos)** via **Nuke** : décodage en sandbox, placeholder/erreur, **cache
  négatif**, **bornes de taille et timeout** (anti « image-bomb » / épuisement mémoire).
  URLs d'images soumises à l'allowlist de schéma §4.4. Pas de SVG exécutant du script, pas de
  chargement d'image via WebView.
- **EPG Base64** : `title`/`description` souvent en Base64 (repli texte brut) → décoder en
  `do/catch`, traiter le résultat comme du **texte d'affichage** (jamais une instruction).

---

## 8. Droit à l'effacement (loi 25 / RGPD)
**MASVS-PRIVACY-4, MASVS-STORAGE-5.**

- **Déconnexion = purge réelle**, pas un flag. Retirer **une** liste purge **ses** données
  scopées `playlistId` (favoris, chaînes masquées — cf. PORT-SPEC §4) et son entrée du store
  Keychain.
- Retirer la **dernière** liste = **effacement total** : toute la base GRDB (catalogue,
  favoris, masquées, reprises, recherches récentes, téléchargements + fichiers), le store
  multi-listes (Keychain) et le consentement HTTP (`UserDefaults`), puis retour à l'écran de
  connexion. Parité exacte avec le comportement v1.04 Android.

```swift
/// Effacement total (dernière liste retirée) — droit à l'effacement loi 25.
func eraseAllLocalData() throws {
    try securePlaylistStore.clear()                 // Keychain : tous les secrets
    try database.deleteAllCatalogueAndUserData()    // GRDB : catalogue + favoris + masquées + reprises
    try downloadManager.removeAllFilesAndEntries()  // fichiers DL + table downloads
    UserDefaults.standard.removePersistentDomain(   // consentements HTTP + recherches récentes
        forName: Bundle.main.bundleIdentifier!)
    // Puis: isLoggedIn = false → renvoi à l'écran de connexion.
}
```
> Vérifier que `removePersistentDomain` ne jette aucune donnée nécessaire partagée ; les
> secrets ne sont **jamais** dans `UserDefaults`, donc ils partent bien via le Keychain.

---

## 9. Checklist avant release (TestFlight / futur App Store)

### MUST (bloquant)
- [ ] Identifiants Xtream dans le **Keychain** (`AfterFirstUnlockThisDeviceOnly`,
      `Synchronizable=false`) — **jamais** `UserDefaults`/fichier clair/base. (§1)
- [ ] Store multi-listes chiffré (Keychain pur, ou CryptoKit AES-GCM + clé Keychain). (§2)
- [ ] Migration **non destructive** ; n'effacer **que** sur échec **permanent** (pas transitoire). (§2.3)
- [ ] `RedactingLogger` partout ; **aucun `print`/`Logger` d'URL brute** ; redaction inclut
      `username=`/`password=` **et** `/live//movie//series//timeshift/`. (§3)
- [ ] Règle CI grep « pas d'URL/secret loggué » qui **fait échouer** la build. (§3.4)
- [ ] **HTTPS d'abord** ; **consentement HTTP par serveur** (non pré-coché, persisté,
      révocable) avant tout envoi d'identifiants en clair ; **badge « non sécurisé »**. (§4.2)
- [ ] ATS : clair toléré au build mais **bloqué par le code** sans consentement ; justification ATS documentée. (§4.1)
- [ ] Anti-downgrade HTTPS→HTTP (`URLSessionTaskDelegate` refuse la redirection). (§4.3)
- [ ] **Aucun** `URLSessionDelegate` trust-all / hostname permissif ; **pas de pinning** ;
      règle CI anti trust-all qui fait échouer la build. (§4.5)
- [ ] Allowlist de schémas `http/https` avant lecture/DL/image (rejet `file:`/`data:`/…). (§4.4)
- [ ] Garde-fou d'hôte sur la réinjection `__cred__` (anti-fuite cross-serveur). (§4.6)
- [ ] Noms de fichiers DL **générés localement** + vérif `canonicalPath`. (§5.2)
- [ ] Dossier DL **et** base GRDB **exclus de la sauvegarde** (`isExcludedFromBackup`). (§5.3)
- [ ] **Zéro secret sur disque** (URL persistée = `__cred__`, réinjection en mémoire). (§5.4)
- [ ] Parsing JSON/EPG **défensif** (`do/catch`, jamais de crash) ; aucune `WebView`. (§7)
- [ ] Déconnexion = purge réelle ; dernière liste retirée = **effacement total** (loi 25). (§8)

### SHOULD (fortement recommandé)
- [ ] Overlay `scenePhase != .active` sur login + Réglages/identifiants (aperçu multitâche). (§6.1)
- [ ] `SecureField` pour les mots de passe ; formulaire d'ajout de liste protégé. (§6.2)
- [ ] Révélation à la demande + auto-masquage (~15 s, et à l'arrière-plan). (§6.3)
- [ ] `description`/`debugDescription` de `XtreamCredentials` **ne fuient pas** le mot de passe. (§1.4)
- [ ] Refus des redirections vers un **hôte ≠ serveur configuré**. (§4.3)
- [ ] Images via Nuke avec **bornes taille/timeout + cache négatif**. (§7)
- [ ] Nettoyage des fragments de téléchargement orphelins au démarrage. (§5.4)

### NICE-TO-HAVE
- [ ] **Face ID / Touch ID** (`LocalAuthentication`) pour révéler les identifiants (option). (§6.4)
- [ ] Classe de protection **`...WhenPasscodeSetThisDeviceOnly`** pour les profils très sensibles
      (au prix de casser les DL en fond avant déverrouillage — à évaluer). (§1.2)
- [ ] `kSecAttrAccessControl` adossé à la **Secure Enclave** pour la clé CryptoKit (option B). (§2.1)
- [ ] Chiffrement optionnel des **fichiers** vidéo téléchargés (CryptoKit, clé Keychain). (§5)
- [ ] Avertissement non bloquant sur appareil jailbreaké (détection best-effort). (§0)

---

## Annexe — Correspondance Android → iOS

| Besoin | Android (source, lecture seule) | iOS (cible) |
|---|---|---|
| Secrets au repos | Tink AEAD `AES256_GCM` + AndroidKeyStore, blob v2 | **Keychain** `AfterFirstUnlockThisDeviceOnly`, `Synchronizable=false` |
| Clé matérielle | AndroidKeyStore / StrongBox | **Secure Enclave** (via `kSecAttrAccessControl`) |
| Chiffrement store | Tink `Aead` | **Keychain pur** (reco) ou **CryptoKit `AES.GCM`** |
| Redaction logs | `RedactingHttpLogger` (2 regex) | **`RedactingLogger`** (mêmes regex + `timeshift` d'emblée) |
| Réinjection creds | `CredentialInjectionInterceptor` (garde-fou d'hôte, 409) | **`CredentialInjector.inject` → nil = bloqué** |
| Politique clair | `network_security_config.xml` + garde-fou code | **ATS `ArbitraryLoads`** + garde-fou code (`CleartextConsent`) |
| Anti-downgrade | `followSslRedirects(false)` | **`URLSessionTaskDelegate`** refuse HTTPS→HTTP |
| TLS | OkHttp CA standard, pas de trust-all | **`URLSession`** CA standard, pas de delegate trust-all |
| Anti-capture | `FLAG_SECURE` | **overlay `scenePhase`** (pas d'équivalent fiable) |
| Exclusion backup | `allowBackup=false`, `data_extraction_rules.xml` | **`isExcludedFromBackup`** (dossier DL + base GRDB) |
| Biométrie | `BiometricPrompt` | **`LocalAuthentication` (`LAContext`)** |
| Images | Coil | **Nuke** (bornes + cache négatif) |
| Effacement loi 25 | purge Room + Tink | purge **GRDB + Keychain + UserDefaults + fichiers DL** |

*Document maintenu par le spécialiste sécurité iOS. Toute décision de sécurité PeachTV+ iOS
est consignée ici et reflétée dans la checklist M2 / revue avant release.*
