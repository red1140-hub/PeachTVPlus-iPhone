# Fiche App Store / TestFlight — PeachTV+ (brouillon prêt à remplir)

*Source de vérité des champs de la fiche. Pour TestFlight interne, seuls le **nom**, les
**coordonnées** et les **notes de test** sont requis ; le reste sert la future publication
publique (lane `release_appstore` + `deliver`). Langue principale : **Français (Canada)**.*

## Identité

| Champ | Valeur |
|---|---|
| Nom (App Name, ≤30 car.) | `PeachTV+` |
| Sous-titre (Subtitle, ≤30 car.) | `Lecteur IPTV Xtream` |
| Bundle ID | `com.peachtvplus.app` |
| Catégorie primaire | Divertissement |
| Catégorie secondaire | *(aucune)* |
| Langue principale | Français (Canada) |
| Copyright | `© 2026` *(à compléter)* |

## Textes (brouillons — à affiner)

**Texte promotionnel** (≤170 car., modifiable sans revue) :
> Votre abonnement IPTV, nativement sur iPhone et iPad : direct, films, séries, rattrapage et
> téléchargements hors-ligne. Rapide, sobre, sans pub.

**Description** :
> PeachTV+ est un lecteur pour votre abonnement IPTV au protocole Xtream Codes. Branchez votre
> serveur et retrouvez vos chaînes en direct, vos films et vos séries, avec une interface native
> pensée pour iPhone et iPad.
>
> • Direct, films et séries, triés par catégories
> • Recherche instantanée par titre
> • Rattrapage (catch-up) sur les chaînes compatibles
> • Téléchargements hors-ligne pour regarder sans réseau
> • Favoris et reprise de lecture
> • Plusieurs listes de lecture
> • Lecture robuste (bascule de moteur automatique pour les formats exotiques)
> • Respect de la vie privée : aucune donnée collectée, identifiants chiffrés sur l'appareil
>
> PeachTV+ n'héberge aucun contenu : il lit uniquement les flux du serveur que vous fournissez.

**Mots-clés** (≤100 car., séparés par des virgules) :
> iptv,xtream,lecteur,streaming,m3u,playlist,direct,films,séries,tv

**Notes de version (release notes)** — première bêta :
> Première version de test : connexion, direct, films, séries, recherche, favoris,
> téléchargements hors-ligne.

## Coordonnées & URLs

| Champ | Valeur |
|---|---|
| URL de support | *(à compléter — page ou courriel)* |
| URL marketing | *(facultatif)* |
| **URL politique de confidentialité** | *(héberger `docs/privacy-policy.md` et coller l'URL ici — requis)* |
| Courriel de contact (App Review) | *(à compléter)* |

## Notes pour la revue Apple (App Review) — IMPORTANT pour une app IPTV

> PeachTV+ est un **lecteur** générique de flux IPTV (protocole Xtream Codes / standards ouverts
> HLS, MPEG-TS). **L'application n'héberge, ne fournit ni ne vend aucun contenu** : l'utilisateur
> saisit l'adresse et les identifiants de **son propre** serveur. Aucun DRM n'est contourné.
>
> Compte de démonstration pour l'évaluation : *(à fournir — un compte Xtream de **démo**
> fonctionnel ; ne jamais mettre d'identifiants réels dans le dépôt).*

## TestFlight — informations de test

| Champ | Valeur |
|---|---|
| Groupe | Testeurs **internes** (vous) — pas de revue bêta Apple |
| « What to Test » | fourni automatiquement par la CI (`TESTFLIGHT_CHANGELOG`) |
| Compte requis par le testeur | un **compte Xtream réel** |

## Captures d'écran (publication publique — plus tard)

Requises : iPhone 6,7″ et iPad 12,9″/13″. Automatisables via Fastlane `snapshot` (UI tests) —
synergie avec les snapshot tests reportés (M6). Non nécessaires pour TestFlight interne.
