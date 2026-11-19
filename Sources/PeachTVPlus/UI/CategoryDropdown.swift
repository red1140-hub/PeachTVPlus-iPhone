import SwiftUI

/// Sélecteur de catégories en **liste déroulante** (menu), visible en tête de liste. Partagé par
/// Direct, Films et Séries. Les catégories synthétiques (Tous/Toutes, Favoris, Revoir) sont de
/// simples `Category` avec un id sentinelle fourni par le ViewModel.
struct CategoryDropdown: View {
    let selectedName: String
    let entries: [Category]
    let selectedId: String?
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(entries) { cat in
                Button { onSelect(cat.id) } label: {
                    if cat.id == selectedId {
                        Label(cat.name, systemImage: "checkmark")
                    } else {
                        Text(cat.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedName).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .background(Color(white: 0.12))
    }
}
