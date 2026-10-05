import SwiftUI

// Briques de la fenêtre de réglages. Les modules les utilisent aussi dans leur `settingsView()`.

/// Carte arrondie regroupant des lignes, séparées automatiquement par un filet.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)
                                .padding(.horizontal, 18)
                        }
                        subview
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .searchSection(title)
    }
}

/// Ligne : titre (+ sous-titre) à gauche, contrôle à droite.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var leadingColor: Color?
    var icon: (systemImage: String, tint: Color)?
    @ViewBuilder var control: Control

    init(_ title: String, subtitle: String? = nil, leadingColor: Color? = nil,
         icon: (systemImage: String, tint: Color)? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.leadingColor = leadingColor
        self.icon = icon
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                IconTile(systemImage: icon.systemImage, tint: icon.tint, size: 28)
            } else if let leadingColor {
                Circle().fill(leadingColor).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 24)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 54)
        .background(
            // Mise en évidence quand on arrive ici depuis la recherche.
            Color.accentColor.opacity(SettingsNavigation.shared.highlighted == title ? 0.14 : 0)
                .animation(.easeOut(duration: 0.6), value: SettingsNavigation.shared.highlighted)
        )
        .id(title)
        .containerValue(\.settingsRowTitle, title)
        .searchable(title, detail: subtitle)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    var leadingColor: Color?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, leadingColor: Color? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.leadingColor = leadingColor
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle, leadingColor: leadingColor) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(_ title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>,
         step: Double, format: @escaping (Double) -> String) {
        self.title = title
        self.subtitle = subtitle
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            HStack(spacing: 10) {
                // Pas de `step:` : sur macOS il dessine des graduations. On arrondit nous-mêmes.
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .controlSize(.small)
                    .frame(width: 170)
                Text(format(value))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

struct PickerRow<Value: Hashable, Options: View>: View {
    let title: String
    var subtitle: String?
    @Binding var selection: Value
    @ViewBuilder var options: Options

    init(_ title: String, subtitle: String? = nil, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.title = title
        self.subtitle = subtitle
        _selection = selection
        self.options = options()
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Picker("", selection: $selection) { options }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
        }
    }
}

struct StepperRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        self.subtitle = subtitle
        _value = value
        self.range = range
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Text("\(Int(value))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Stepper("", value: $value, in: range, step: 1).labelsHidden()
            }
        }
    }
}

/// Intertitre à l'intérieur d'une carte.
/// Intertitre. Dans `SettingsSections`, il ouvre une nouvelle carte portant ce titre ;
/// ailleurs, il s'affiche comme un petit titre à l'intérieur de la carte.
struct SettingsSubheader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .containerValue(\.settingsSectionTitle, title)
    }
}

/// Pastille d'icône colorée façon Réglages Système.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.gradient)
            )
    }
}
