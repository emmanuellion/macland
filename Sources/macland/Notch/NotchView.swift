import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    let model: NotchViewModel
    var onOpenSettings: () -> Void

    private let settings = IslandSettings.shared
    private let registry = ModuleRegistry.shared

    private var animation: Animation {
        .spring(duration: settings.animationResponse, bounce: settings.animationBounce)
    }

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        let receiver = registry.fileDropReceiver

        ZStack(alignment: .top) {
            IslandBackground(shape: shape, isExpanded: model.isExpanded)

            if model.isExpanded {
                ExpandedView(model: model, onOpenSettings: onOpenSettings)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)).combined(with: .blur))
            } else if let activity = model.activity {
                CompactActivityView(activity: activity, notchWidth: model.geometry.size.width,
                                    notchHeight: model.geometry.size.height)
                    .padding(.horizontal, model.topRadius)
                    .transition(.opacity.combined(with: .blur))
                    .id(activity.id)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(settings.showShadow && (model.isExpanded || model.activity?.bottom != nil) ? 0.45 : 0),
                radius: 14, y: 6)
        .contentShape(shape)
        .onTapGesture {
            if settings.expandTrigger == .click, !model.isExpanded { model.expand() }
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { receiver?.isDropTargeted ?? false },
            set: { receiver?.isDropTargeted = $0 }
        )) { providers in
            receiver?.receive(providers) ?? false
        }
        .contextMenu {
            Button(tr("Réglages…", "Settings…"), action: onOpenSettings)
            Divider()
            Button(tr("Quitter macland", "Quit macland")) { NSApp.terminate(nil) }
        }
        .animation(animation, value: model.isExpanded)
        .animation(animation, value: size)
        .animation(animation, value: model.activity?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.locale, settings.locale)
    }
}

// MARK: - Fond

/// Fond de l'île : noir une fois fermée (pour se fondre dans l'encoche), puis couleur
/// ou Liquid Glass teinté une fois ouverte.
struct IslandBackground: View {
    let shape: NotchShape
    let isExpanded: Bool
    private let settings = IslandSettings.shared

    var body: some View {
        if isExpanded, settings.usesGlass, #available(macOS 26, *) {
            let base: Glass = settings.glassVariant == .clear ? .clear : .regular
            Color.clear
                .glassEffect(base.tint(settings.islandColor.color.opacity(settings.glassTint)), in: shape)
        } else {
            shape.fill(isExpanded ? settings.islandColor.color : .black)
        }
    }
}

// MARK: - Île fermée : activité en direct

private struct CompactActivityView: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                activity.leading
                    .frame(width: activity.sideWidth, alignment: .leading)
                    .padding(.leading, 6)
                Spacer(minLength: notchWidth - 12)
                activity.trailing
                    .frame(width: activity.sideWidth, alignment: .trailing)
                    .padding(.trailing, 6)
            }
            .frame(height: notchHeight)

            if let bottom = activity.bottom {
                bottom
                    .frame(height: activity.bottomHeight)
                    .padding(.horizontal, 14)
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.primary)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Île ouverte

private struct ExpandedView: View {
    let model: NotchViewModel
    var onOpenSettings: () -> Void

    private let registry = ModuleRegistry.shared

    var body: some View {
        let pages = registry.enabledPages

        VStack(spacing: 0) {
            // Barre supérieure, de part et d'autre de la caméra.
            HStack(spacing: 4) {
                if !pages.isEmpty {
                    PageButton(systemImage: "house.fill", isSelected: model.selectedPage == NotchViewModel.homePage) {
                        model.selectedPage = NotchViewModel.homePage
                    }
                    ForEach(pages, id: \.id) { page in
                        PageButton(systemImage: page.systemImage, isSelected: model.selectedPage == page.id) {
                            model.selectedPage = page.id
                        }
                    }
                }
                Spacer(minLength: model.geometry.size.width + 16)
                PageButton(systemImage: "gearshape.fill", isSelected: false, action: onOpenSettings)
            }
            .frame(height: model.geometry.size.height)

            Group {
                if let page = pages.first(where: { $0.id == model.selectedPage }) {
                    page.expandedView()
                } else {
                    HomeView(widgets: registry.enabledWidgets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)
        }
        .padding(.horizontal, NotchViewModel.expandedTopRadius + 18)
        .padding(.bottom, 16)
        .environment(\.colorScheme, IslandSettings.shared.islandColor.colorScheme)
        .animation(.smooth(duration: 0.25), value: model.selectedPage)
    }
}

private struct HomeView: View {
    let widgets: [any IslandModule]
    private let settings = IslandSettings.shared

    var body: some View {
        // Sans widget flexible (rien en lecture), chaque widget est centré dans sa part de largeur.
        let hasFlexible = widgets.contains { $0.layoutPriority > 0 }

        if widgets.isEmpty {
            Text(tr("Aucun widget activé", "No widgets enabled"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            HomeLayout {
                ForEach(Array(widgets.enumerated()), id: \.element.id) { index, module in
                    if index > 0 {
                        // Sans filet, l'espace entre widgets est conservé.
                        Rectangle()
                            .fill(Color.primary.opacity(settings.showWidgetSeparators ? 0.1 : 0))
                            .frame(width: 1)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .layoutValue(key: HomeItemRole.self, value: .divider)
                    }
                    module.expandedView()
                        .frame(maxWidth: .infinity, alignment: hasFlexible ? .leading : .center)
                        .layoutValue(key: HomeItemRole.self, value: module.layoutPriority > 0 ? .flexible : .widget)
                }
            }
        }
    }
}

private enum HomeItemRole: LayoutValueKey {
    case divider, widget, flexible
    static let defaultValue = HomeItemRole.widget
}

/// Répartit la largeur de l'accueil :
/// - les widgets normaux gardent leur largeur naturelle ;
/// - les widgets flexibles (lecture en cours) prennent le reste, avec un minimum garanti ;
/// - si la place manque, les widgets normaux rétrécissent proportionnellement ;
/// - sans widget flexible, la largeur est partagée à parts égales entre les widgets.
private struct HomeLayout: Layout {
    var minFlexibleWidth: CGFloat = 230

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 600, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(for: bounds.width, subviews: subviews)
        let used = widths.reduce(0, +)
        var x = bounds.minX + max(0, (bounds.width - used) / 2)
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }

    private func widths(for total: CGFloat, subviews: Subviews) -> [CGFloat] {
        let roles = subviews.map { $0[HomeItemRole.self] }
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        var widths = natural

        let dividers = roles.indices.filter { roles[$0] == .divider }
        let fixed = roles.indices.filter { roles[$0] == .widget }
        let flexible = roles.indices.filter { roles[$0] == .flexible }

        let available = max(0, total - dividers.reduce(0) { $0 + natural[$1] })
        let fixedNatural = fixed.reduce(0) { $0 + natural[$1] }
        let reserved = CGFloat(flexible.count) * minFlexibleWidth
        let roomForFixed = available - reserved

        if fixedNatural > roomForFixed, fixedNatural > 0 {
            let scale = max(0, roomForFixed) / fixedNatural
            fixed.forEach { widths[$0] = natural[$0] * scale }
        }

        if !flexible.isEmpty {
            let used = fixed.reduce(0) { $0 + widths[$1] }
            let share = max(0, available - used) / CGFloat(flexible.count)
            flexible.forEach { widths[$0] = share }
        } else if !fixed.isEmpty, fixedNatural <= available {
            let share = available / CGFloat(fixed.count)
            if fixed.allSatisfy({ natural[$0] <= share }) {
                fixed.forEach { widths[$0] = share }
            } else {
                // Un widget plus large que sa part : on partage seulement le surplus.
                let extra = (available - fixedNatural) / CGFloat(fixed.count)
                fixed.forEach { widths[$0] = natural[$0] + extra }
            }
        }
        return widths
    }
}

private struct PageButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.45))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transitions

private extension AnyTransition {
    static var blur: AnyTransition {
        .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
