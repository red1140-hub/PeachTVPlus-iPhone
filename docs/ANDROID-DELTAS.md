# PeachTV+ — Deltas Android à porter (post-parité v1.04)

> **But** : communiquer au portage iOS/iPadOS les changements livrés côté **Android
> (`../mytv-player`)** APRÈS la synchro de référence de [`PORT-SPEC.md`](PORT-SPEC.md)
> (figée à **v1.04**, 2026-11-12). Chaque entrée = ce qu'Android a fait + la note de
> portage iOS. **`../mytv-player` reste EN LECTURE SEULE.** Rien n'est obligatoire : à
> l'équipe iOS de décider d'une éventuelle mise à jour.
>
> Source : équipe Android (DevRed1140). Dernière mise à jour : **2026-11-15 (Android v1.08).**

---

## v1.08 (2026-11-15) — 4 changements

### 1. Recherche d'émissions limitée aux chaînes de l'Accueil/Direct (en mémoire)
- **Android** : la Recherche ne précharge **plus** toutes les chaînes du panneau
  (`refreshAllChannels` retiré de `SearchViewModel`). **Films** et **Séries** se cherchent
  toujours sur toute la bibliothèque ; **chaînes directes** + **titres d'émissions (EPG)** se
  cherchent **uniquement sur les chaînes déjà en mémoire** (la catégorie affichée à
  l'Accueil/Direct — liste réduite). L'index EPG (`epg_programmes`, vidage `xmltv.php` en **une
  requête**, jamais chaîne par chaîne) est **borné aux `epgChannelId` présents dans le cache**
  (`LiveChannelDao.distinctEpgChannelIds`, repli : tout si cache vide). But : plus léger, ne pas
  pointer sur des chaînes non utilisées.
- **iOS** : scoper la recherche chaînes/émissions au **même périmètre** (chaînes chargées de la
  catégorie Direct par défaut), laisser films/séries en recherche globale. Si l'EPG recherchable
  est indexé (GRDB), le borner aux chaînes en cache et le joindre par `epgChannelId`. Ne **jamais**
  requêter l'EPG chaîne par chaîne (bannissement).

### 2. Robustesse de la recherche sur certains caractères
- **Android** : toutes les requêtes `LIKE` utilisent désormais `ESCAPE '\'` et les jokers
  (`%`, `_`, `\`) sont échappés en amont (`XtreamRepository.escapeLike`) → cherchés
  littéralement. Combiné au point 1 (fin du balayage de tout le catalogue), ça supprime les
  ralentissements/plantages observés sur des requêtes « larges ». Requêtes toujours
  **paramétrées** (pas d'injection SQL).
- **iOS** : si la recherche GRDB utilise `LIKE`, appliquer le même échappement des jokers +
  `ESCAPE`, et garder des requêtes paramétrées. Borner les résultats (LIMIT).

### 3. Flèche « retour » en lecture plein écran (paysage)
- **Android** : en plein écran paysage (Live **et** VOD **et** hors-ligne), l'interface au
  toucher affiche maintenant une **flèche retour en haut à gauche** (revient à l'écran
  précédent, comme en portrait). Impl. : slot `topStartContent` ajouté à `PlayerControlsOverlay`
  + `PlayerBackButton`.
- **iOS** : ajouter un bouton **chevron/flèche retour** dans l'overlay de contrôles plein écran
  paysage des lecteurs (apparaît/disparaît avec les autres contrôles, auto-masquage 7 s),
  déclenchant la même navigation retour qu'en portrait.

### 4. Réordonnancement manuel des chaînes favorites (Direct)
- **Android** : dans la catégorie **« Favoris »** du Direct, l'appui long ajoute **Monter** /
  **Descendre** (désactivés en tête / en queue). Ordre persisté via une nouvelle colonne
  **`favorites.sortOrder`** (`INTEGER NOT NULL DEFAULT 0`, migration Room **v8→v9** non
  destructive) ; tri `sortOrder ASC, addedAt DESC` (0 = non réordonné → « plus récent d'abord »).
  Réordonner réécrit une séquence dense 1..n (`XtreamRepository.reorderLiveFavorites`). Un favori
  (ré)ajouté revient en tête tant qu'on ne le place pas. **Choix d'UI** : menu (et non
  glisser-déposer) car la grille Direct a un **défilement horizontal par ligne** — un drag
  entrerait en conflit ; le menu est sans ambiguïté et accessible iPhone + iPad.
- **iOS** : ajouter un champ d'**ordre** aux favoris (migration GRDB **additive**), trier par cet
  ordre, et offrir la réorganisation. Sur iOS, `List` + `.onMove` (mode édition) est l'idiome
  naturel pour les favoris ; sinon reproduire le menu Monter/Descendre. Conserver la règle
  « (ré)ajout en tête jusqu'à placement ».

---

## Rappel : deltas v1.05–v1.07 (déjà livrés Android, également post-v1.04)

Pour mémoire, à porter aussi (non détaillés ici, voir l'historique `../mytv-player`) :

- **v1.05** — Stabilité : reprise auto du flux Live sur coupure (`LiveStreamRecovery`,
  back-off), **Cast Live** marqué `STREAM_TYPE_LIVE` (évite l'arrêt ~3-5 min),
  `WAKE_MODE_NETWORK`, mitigation Cast MKV/AC-3/DTS (avertissement + lecture locale).
  → iOS : la plupart déjà anticipé dans §3 de PORT-SPEC (M3a : `PlaybackRetryPolicy`,
  back-off, no-retry en Live) ; valider la parité Cast quand le Cast iOS sera ajouté (post-v1).
- **v1.06** — Recherche **par titre d'émission EPG** (direct + rattrapage) : section
  « Émissions » (titre + chaîne + horaire), ouverture en rattrapage si l'émission est terminée.
  → iOS : fonctionnalité à ajouter (voir §1 ci-dessus pour le périmètre v1.08).

> Dès que le portage iOS atteint l'un de ces points, **mettre à jour la ligne de synchro** en
> tête de `PORT-SPEC.md` et cocher le milestone correspondant.
