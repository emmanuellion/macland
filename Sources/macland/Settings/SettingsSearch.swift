import SwiftUI

// Recherche dans les réglages : chaque ligne (`SettingsRow`) déclare son titre via une préférence.
// Un index invisible affiche toutes les pages et récolte ces déclarations ; la barre de recherche
// filtre cet index. Aucune liste à maintenir à la main : une nouvelle ligne est trouvable d'office.

/// Un réglage trouvable.
struct SearchEntry: Hashable {
    let title: String
    var detail: String?
    /// Section (titre de carte ou intertitre) qui contient le réglage.
    var section: String?
    var page: SettingsPage?
}

struct SearchEntriesKey: PreferenceKey {
    static let defaultValue: [SearchEntry] = []
    static func reduce(value: inout [SearchEntry], nextValue: () -> [SearchEntry]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Rend ce titre trouvable par la recherche.
    func searchable(_ title: String, detail: String? = nil) -> some View {
        preference(key: SearchEntriesKey.self, value: [SearchEntry(title: title, detail: detail)])
    }

    /// Rattache les réglages trouvés dans cette vue à une section.
    func searchSection(_ section: String?) -> some View {
        transformPreference(SearchEntriesKey.self) { entries in
            for index in entries.indices where entries[index].section == nil {
                entries[index].section = section
            }
        }
    }

    /// Rattache les réglages trouvés dans cette vue à une page.
    func searchPage(_ page: SettingsPage) -> some View {
        transformPreference(SearchEntriesKey.self) { entries in
            for index in entries.indices where entries[index].page == nil {
                entries[index].page = page
            }
        }
    }
}

enum SettingsSearch {
    /// Comparaison sans accents ni majuscules : « lumi » trouve « Luminosité ».
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Pertinence : titre qui commence par la requête > titre qui la contient > description ou section.
    static func score(_ entry: SearchEntry, query: String) -> Int {
        let title = normalized(entry.title), query = normalized(query).trimmingCharacters(in: .whitespaces)
        if title.hasPrefix(query) { return 3 }
        if title.contains(query) { return 2 }
        return 1
    }

    /// Tous les mots de la requête doivent apparaître dans le titre, la description ou la section.
    static func matches(_ entry: SearchEntry, query: String) -> Bool {
        let haystack = normalized([entry.title, entry.detail ?? "", entry.section ?? ""].joined(separator: " "))
        return normalized(query).split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Sections

/// Titre de section porté par un intertitre, lu par `SettingsSections` pour découper en cartes.
private struct SectionTitleKey: ContainerValueKey {
    static let defaultValue: String? = nil
}

/// Titre d'une ligne de réglage, pour lui redonner son identifiant après le découpage en cartes
/// (sans quoi la recherche ne peut pas faire défiler jusqu'à elle).
private struct RowTitleKey: ContainerValueKey {
    static let defaultValue: String? = nil
}

extension ContainerValues {
    var settingsSectionTitle: String? {
        get { self[SectionTitleKey.self] }
        set { self[SectionTitleKey.self] = newValue }
    }

    var settingsRowTitle: String? {
        get { self[RowTitleKey.self] }
        set { self[RowTitleKey.self] = newValue }
    }
}

/// Découpe une suite de lignes en cartes distinctes, une par `SettingsSubheader`.
/// Les lignes avant le premier intertitre forment une carte titrée `title`.
struct SettingsSections<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { subviews in
            let sections = Self.split(subviews, firstTitle: title)
            VStack(alignment: .leading, spacing: 28) {
                ForEach(sections.indices, id: \.self) { index in
                    let section = sections[index]
                    SettingsCard(section.title) {
                        ForEach(section.rows) { row in
                            if let title = row.containerValues.settingsRowTitle { row.id(title) } else { row }
                        }
                    }
                    .searchSection(section.title)
                }
            }
        }
    }

    private struct Section {
        var title: String?
        var rows: [Subview]
    }

    private static func split(_ subviews: SubviewsCollection, firstTitle: String?) -> [Section] {
        var sections: [Section] = []
        var current = Section(title: firstTitle, rows: [])
        for subview in subviews {
            if let header = subview.containerValues.settingsSectionTitle {
                if !current.rows.isEmpty { sections.append(current) }
                current = Section(title: header, rows: [])
            } else {
                current.rows.append(subview)
            }
        }
        if !current.rows.isEmpty { sections.append(current) }
        return sections
    }
}
