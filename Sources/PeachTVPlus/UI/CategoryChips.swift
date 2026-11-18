import SwiftUI

/// Barre de **catégories** horizontale et visible, en tête de liste (Direct / Films / Séries).
/// Remplace le menu discret de la barre d'outils : la catégorie active est mise en évidence
/// (accent néon). Défile horizontalement si les catégories sont nombreuses.
struct CategoryChips: View {
    let categories: [Category]
    let selectedId: String?
    /// Libellé de la puce « tout » (ex. « Toutes », « Tous les films »).
    let allLabel: String
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(allLabel, id: nil).id("all")
                    ForEach(categories) { cat in
                        chip(cat.name, id: cat.id).id(cat.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedId) { _, new in
                withAnimation { proxy.scrollTo(new ?? "all", anchor: .center) }
            }
        }
    }

    private func chip(_ title: String, id: String?) -> some View {
        let selected = (id == selectedId)
        return Button {
            onSelect(id)
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Color(white: 0.15), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
