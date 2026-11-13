# Politique de confidentialité — PeachTV+ (iOS/iPadOS)

*Dernière mise à jour : 2026-11-13. Brouillon à héberger sur une URL publique (exigée par
App Store Connect et par la revue). Adapté de la politique Android, aligné sur la **loi 25**
(Québec) et le **RGPD**.*

## En bref

PeachTV+ est un **lecteur** de flux IPTV au protocole Xtream Codes. L'app **n'héberge aucun
contenu** : elle lit uniquement les flux du **serveur que vous fournissez**. Nous (l'éditeur)
**ne collectons, ne transmettons et ne stockons aucune donnée personnelle** sur nos serveurs —
nous n'avons d'ailleurs aucun serveur. **Aucun suivi publicitaire, aucune analyse tierce.**

## Données traitées, et où elles restent

| Donnée | Usage | Où elle est stockée | Transmise à un tiers ? |
|---|---|---|---|
| Identifiants Xtream (serveur, utilisateur, mot de passe) | se connecter à **votre** serveur | **Trousseau (Keychain)** chiffré de l'appareil | Non — uniquement vers **votre** serveur, et en HTTPS sauf si vous autorisez le HTTP |
| Cache catalogue (chaînes, films, séries, EPG) | navigation/recherche hors-ligne | base locale chiffrable, **exclue de la sauvegarde iCloud** | Non |
| Favoris, positions de lecture, chaînes masquées | confort d'usage | base locale | Non |
| Fichiers téléchargés | lecture hors-ligne | stockage local de l'app | Non |
| Consentement HTTP par serveur | garde-fou « HTTPS d'abord » | `UserDefaults` (aucun secret) | Non |

Aucune de ces données ne quitte votre appareil, sauf les **requêtes vers le serveur IPTV que
vous configurez** (indispensables pour lire les flux). Nous n'y avons aucun accès.

## Ce que nous **ne** faisons **pas**

- Aucun compte chez nous, aucune inscription.
- Aucun identifiant publicitaire, aucun pistage, aucun SDK d'analyse ou de pub.
- Aucune revente de données (il n'y en a aucune à revendre).

## Permissions

- **Réseau** : lire les flux et le catalogue de votre serveur.
- **Stockage local** : cache + téléchargements hors-ligne.
- Pas d'accès à la localisation, aux contacts, au micro, à la caméra ni aux photos.

## Suppression de vos données (loi 25)

Tout est local. Vous effacez tout à tout moment :
- **Retirer une liste** supprime ses favoris, chaînes masquées et téléchargements.
- **Se déconnecter** (retirer la dernière liste) efface **l'intégralité** du cache et les
  identifiants du trousseau.
- Désinstaller l'app supprime toutes ses données.

## Sécurité

Identifiants au **Trousseau** chiffré ; **HTTPS par défaut**, le HTTP n'étant utilisé qu'après
votre **consentement explicite par serveur** (révocable dans les Réglages) ; aucune vérification
TLS désactivée.

## Enfants

L'app ne cible pas les enfants et ne collecte aucune donnée les concernant.

## Contact

*(À compléter : adresse courriel de support publiée dans la fiche App Store.)*
