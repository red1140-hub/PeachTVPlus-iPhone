import Foundation

extension URL {
    /// Exclut ce fichier/dossier de la **sauvegarde iCloud / chiffrée** (`isExcludedFromBackup`).
    /// Équivalent du `allowBackup=false` + exclusions Android (H2). À (ré)appliquer **après**
    /// (re)création de la cible. Voir `docs/security.md §5.3`.
    /// Appliqué sur : la base GRDB (`catalogue.sqlite`) et — en M4 — le dossier `Downloads/`.
    mutating func excludeFromBackup() throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try setResourceValues(values)
    }
}
