import Foundation

/// Erreur de lecture **orientée utilisateur** : jamais de code brut ni de stacktrace. Chaque
/// cas = titre court + cause probable + **une** action. On distingue toujours « ce flux est
/// mort » (serveur) de « ta connexion est coupée » (local). Voir `docs/reliability-and-qa.md §2`.
struct PlaybackError: Error, Equatable {

    enum Kind: Equatable {
        case noConnection          // appareil hors-ligne
        case serverUnreachable     // panel down / adresse fausse / DNS
        case serverSlow            // timeout, débit au goutte-à-goutte
        case streamUnavailable     // 404 : chaîne/film retiré
        case accessDenied          // 401/403 : abo expiré / non autorisé / UA filtré
        case behindLive            // décrochage du direct (silencieux)
        case unsupportedFormat     // HEVC/AC3 sur AVPlayer (bascule VLC auto)
        case unreadableContainer   // mauvais moteur (bascule auto)
        case cleartextBlocked      // http sans consentement (ATS)
        case schemeRejected        // file:/data: après redirection (allowlist)
        case unknown
    }

    let kind: Kind
    let title: String
    let message: String
    let action: String
    /// `true` = à traiter sans message (ex. décrochage direct → re-seek silencieux).
    let isSilent: Bool

    init(kind: Kind, title: String, message: String, action: String, isSilent: Bool = false) {
        self.kind = kind; self.title = title; self.message = message
        self.action = action; self.isSilent = isSilent
    }
}

extension PlaybackError {

    /// Classe une erreur réseau/HTTP en message produit. `statusCode` prioritaire sur
    /// `urlErrorCode` (un 401 reste 401 même via une session en timeout). Textes FR, lisibles,
    /// cohérents avec le reste de l'app (pas de jargon, pas de québécois sur les erreurs).
    static func classify(statusCode: Int? = nil, urlErrorCode: URLError.Code? = nil) -> PlaybackError {
        switch statusCode {
        case 404:
            return PlaybackError(kind: .streamUnavailable,
                                 title: "Cette chaîne n'est pas disponible.",
                                 message: "Le flux a peut-être été retiré par le fournisseur.",
                                 action: "Réessayer")
        case 401, 403:
            return PlaybackError(kind: .accessDenied,
                                 title: "Accès refusé.",
                                 message: "Vérifiez votre abonnement pour cette liste de lecture.",
                                 action: "Voir la liste de lecture")
        default:
            break
        }

        switch urlErrorCode {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return PlaybackError(kind: .noConnection,
                                 title: "Pas de connexion.",
                                 message: "Vérifiez votre réseau.",
                                 action: "Réessayer")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return PlaybackError(kind: .serverUnreachable,
                                 title: "Serveur injoignable.",
                                 message: "Impossible de joindre le serveur de la liste.",
                                 action: "Vérifier la liste")
        case .timedOut:
            return PlaybackError(kind: .serverSlow,
                                 title: "Le serveur met trop de temps à répondre.",
                                 message: "Le débit semble instable.",
                                 action: "Changer de qualité")
        case .appTransportSecurityRequiresSecureConnection:
            return PlaybackError(kind: .cleartextBlocked,
                                 title: "Connexion non sécurisée bloquée.",
                                 message: "Autoriser le HTTP pour ce serveur ?",
                                 action: "Autoriser le HTTP")
        case .unsupportedURL:
            return PlaybackError(kind: .schemeRejected,
                                 title: "Flux refusé (adresse non autorisée).",
                                 message: "L'adresse du flux n'est pas prise en charge.",
                                 action: "Retour")
        default:
            return PlaybackError(kind: .unknown,
                                 title: "Lecture impossible.",
                                 message: "Une erreur est survenue pendant la lecture.",
                                 action: "Réessayer")
        }
    }

    /// Décrochage du direct — **silencieux** (re-seek automatique au bord direct).
    static let behindLive = PlaybackError(kind: .behindLive,
                                          title: "", message: "", action: "", isSilent: true)

    /// Les deux moteurs ont échoué sur un format/conteneur (après bascule auto).
    static let unsupported = PlaybackError(kind: .unsupportedFormat,
                                           title: "Format non pris en charge.",
                                           message: "Ce flux utilise un format illisible sur cet appareil.",
                                           action: "Retour")
}
