# Installer PeachTV+ sur un iPhone/iPad SANS l'App Store (sideload)

> But : donner à un proche le fichier **`PeachTv+iphone.ipa`** pour qu'il l'installe sur son
> iPhone/iPad avec **son propre identifiant Apple gratuit**. Pas besoin de notre compte Apple
> Developer, pas besoin de TestFlight.

## Pourquoi « réactiver tous les 7 jours » ?

Apple permet de signer une app avec un **identifiant Apple gratuit**, mais la signature
**expire au bout de 7 jours**. Passé ce délai, l'app ne s'ouvre plus tant qu'on ne l'a pas
**re-signée** (« réactivée »). C'est normal et attendu pour du sideload gratuit.

- Avec un **identifiant Apple gratuit** : re-signature **tous les 7 jours**, **3 apps**
  sideloadées en même temps max.
- Avec un **compte Apple Developer payant (99 $/an)** : signature valable **1 an** (pas de
  corvée des 7 jours).

**AltStore** automatise cette re-signature en arrière-plan (« refresh ») tant que le téléphone
et l'ordinateur sont sur le même réseau Wi-Fi de temps en temps → en pratique, on ne s'en
occupe presque pas.

## Étape 0 — Obtenir le fichier `PeachTv+iphone.ipa`

Le `.ipa` se fabrique sur le **Mac cloud Codemagic** (on n'a pas de Mac local) :

1. Aller sur **codemagic.io** → l'application **PeachTVPlus-iPhone**.
2. **Start new build** → choisir le workflow **`ios-ipa-unsigned`** → lancer.
3. À la fin, **télécharger l'artefact `PeachTv+iphone.ipa`**.

> Cet `.ipa` est **non signé** exprès : c'est l'outil de sideload de ton ami qui le signe avec
> **son** identifiant Apple. Tu peux donc lui transmettre le même fichier sans y mettre aucun
> de tes identifiants.

## Étape 1 — Choisir l'outil de sideload (au choix de ton ami)

### Option A — AltStore (recommandé : gère le renouvellement des 7 jours tout seul)
Pré-requis : un ordinateur (Windows ou Mac) avec **AltServer**, iTunes (Windows) + iCloud
(versions Apple, pas Microsoft Store), et le câble.

1. Installer **AltServer** sur l'ordinateur (altstore.io).
2. Brancher l'iPhone, faire confiance à l'ordinateur.
3. AltServer → **Install AltStore** sur l'appareil (demande l'identifiant Apple **de ton ami**).
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → faire confiance au
   profil développeur de son identifiant.
5. Ouvrir **AltStore** sur l'iPhone → onglet **My Apps** → **+** → choisir `PeachTv+iphone.ipa`.
6. AltStore installe et **re-signe automatiquement** l'app (laisser AltServer tourner sur
   l'ordinateur, même Wi-Fi, pour le « Background Refresh » hebdomadaire).

### Option B — Sideloadly (simple, mais re-signature manuelle chaque semaine)
1. Installer **Sideloadly** (sideloadly.io) sur l'ordinateur + iTunes/iCloud (Windows).
2. Brancher l'iPhone, glisser `PeachTv+iphone.ipa` dans Sideloadly.
3. Saisir l'identifiant Apple **de ton ami**, cliquer **Start**.
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → faire confiance.
5. **Tous les 7 jours** : rebrancher et refaire **Start** pour re-signer (sinon l'app ne
   s'ouvre plus).

## Étape 2 — Première ouverture

- Ouvrir **PeachTV+**, saisir les identifiants de **son** serveur Xtream (serveur,
  utilisateur, mot de passe). HTTPS recommandé ; en HTTP, l'app demande une confirmation.
- Tester : Direct, Films, Séries, recherche, un téléchargement hors-ligne.

## Limites honnêtes du sideload gratuit

- **Re-signature tous les 7 jours** (automatique avec AltStore, manuelle avec Sideloadly).
- **Max 3 apps** sideloadées par identifiant gratuit.
- Les **notifications push** et certaines capacités avancées ne sont pas disponibles en
  identifiant gratuit — **sans impact ici** : PeachTV+ n'utilise ni push, ni App Groups, ni
  Associated Domains. Les modes d'arrière-plan utilisés (lecture audio, téléchargement) **sont**
  permis.
- L'app n'est pas revue par Apple : c'est un usage **personnel**. Ne redistribue pas largement.

## Alternative sans corvée des 7 jours

Si ton ami accepte, l'inviter comme **testeur TestFlight** (avec notre compte Apple Developer,
cf. `devops-testflight.md`) évite totalement le sideload et les 7 jours — mais exige le compte
payant et son adresse courriel/Apple ID dans App Store Connect.
