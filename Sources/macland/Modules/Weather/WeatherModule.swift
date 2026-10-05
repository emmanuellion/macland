import SwiftUI

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    var id: String { rawValue }
    var label: String { self == .celsius ? "°C" : "°F" }
}

@MainActor
@Observable
final class WeatherModule: IslandModule {
    let id = "weather"
    var name: String { tr("Météo", "Weather") }
    let systemImage = "cloud.sun.fill"
    var summary: String {
        tr("Température et conditions actuelles, fournies par open-meteo.com (seul module qui se connecte à Internet).",
           "Current temperature and conditions from open-meteo.com (the only module that goes online).")
    }
    let tint = Color.cyan
    let enabledByDefault = false

    @ObservationIgnored private let store = ModuleDefaults(moduleID: "weather", registering: [
        "placeName": "",
        "placeDetail": "",
        "latitude": 0.0,
        "longitude": 0.0,
        "unit": TemperatureUnit.celsius.rawValue,
        "showHighLow": true,
    ])

    /// Ville choisie, `nil` tant qu'aucune n'a été sélectionnée.
    var place: WeatherPlace? {
        didSet {
            store.set(place?.name ?? "", "placeName")
            store.set(place?.detail ?? "", "placeDetail")
            store.set(place?.latitude ?? 0, "latitude")
            store.set(place?.longitude ?? 0, "longitude")
            if place != oldValue { report = nil; refresh() }
        }
    }
    var unit: TemperatureUnit { didSet { store.set(unit.rawValue, "unit"); if unit != oldValue { refresh() } } }
    var showHighLow: Bool { didSet { store.set(showHighLow, "showHighLow") } }

    private(set) var report: WeatherReport?

    /// Lieu affiché : celui choisi par l'utilisateur, ou une ville fictive pour les captures publiques.
    var displayedPlace: WeatherPlace? { demoPlace ?? place }
    @ObservationIgnored private var demoPlace: WeatherPlace?
    private(set) var error: String?

    // Recherche de ville (pas de @State sans Xcode : l'état vit ici).
    var searchQuery = ""
    private(set) var searchResults: [WeatherPlace] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    private(set) var isLocating = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var locationFetcher: CurrentLocationFetcher?

    init() {
        let name = store.string("placeName")
        place = name.isEmpty ? nil : WeatherPlace(name: name, detail: store.string("placeDetail"),
                                                  latitude: store.double("latitude"), longitude: store.double("longitude"))
        unit = TemperatureUnit(rawValue: store.string("unit")) ?? .celsius
        showHighLow = store.bool("showHighLow")
    }

    func expandedView() -> AnyView { AnyView(WeatherView(module: self)) }
    func settingsView() -> AnyView? { AnyView(WeatherSettingsView(module: self)) }

    func start() {
        isRunning = true
        #if DEBUG
        // Météo fictive pour les captures (la ville enregistrée n'est pas modifiée).
        if CommandLine.arguments.contains("--demo-media") {
            report = WeatherReport(temperature: 21, code: 2, isDay: true, high: 24, low: 14, date: .now)
            demoPlace = WeatherPlace(name: "Lisbon", detail: "Portugal", latitude: 38.72, longitude: -9.14)
            return
        }
        #endif
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: Données

    func refresh() {
        guard isRunning, let place else { return }
        let fahrenheit = unit == .fahrenheit
        Task {
            do {
                let report = try await WeatherService.forecast(for: place, fahrenheit: fahrenheit)
                // Ignore une réponse arrivée après un changement de ville ou d'unité.
                guard place == self.place, fahrenheit == (unit == .fahrenheit) else { return }
                self.report = report
                error = nil
            } catch {
                // On garde la dernière météo connue.
                self.error = tr("Météo indisponible (connexion ?)", "Weather unavailable (offline?)")
            }
        }
    }

    func search() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        Task {
            do {
                searchResults = try await WeatherService.search(query, french: IslandSettings.shared.isFrench)
                if searchResults.isEmpty { searchError = tr("Aucune ville trouvée.", "No city found.") }
            } catch {
                searchResults = []
                searchError = tr("Recherche impossible (connexion ?)", "Search failed (offline?)")
            }
            isSearching = false
        }
    }

    func select(_ place: WeatherPlace) {
        self.place = place
        searchResults = []
        searchQuery = ""
        searchError = nil
    }

    func useCurrentLocation() {
        let fetcher = CurrentLocationFetcher()
        locationFetcher = fetcher
        isLocating = true
        searchError = nil
        Task {
            do {
                select(try await fetcher.fetch())
            } catch CurrentLocationFetcher.Failure.denied {
                searchError = tr("Accès à la position refusé : autorise macland dans Confidentialité › Service de localisation.",
                                 "Location access denied: allow macland in Privacy › Location Services.")
            } catch {
                searchError = tr("Position introuvable.", "Couldn't get your location.")
            }
            isLocating = false
            locationFetcher = nil
        }
    }

    func formatted(_ temperature: Double) -> String {
        "\(Int(temperature.rounded()))°"
    }
}

// MARK: - Vue

private struct WeatherView: View {
    let module: WeatherModule

    private func symbol(_ report: WeatherReport, size: CGFloat) -> some View {
        Image(systemName: WeatherService.symbol(for: report.code, isDay: report.isDay))
            .font(.system(size: size))
            .symbolRenderingMode(.multicolor)
    }

    private func temperature(_ report: WeatherReport, size: CGFloat) -> some View {
        Text(module.formatted(report.temperature))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
    }

    @ViewBuilder private func highLow(_ report: WeatherReport) -> some View {
        if module.showHighLow, let high = report.high, let low = report.low {
            Text("↑\(module.formatted(high))  ↓\(module.formatted(low))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        if let place = module.displayedPlace {
            if let report = module.report {
                // Du plus complet au plus compact : l'île garde la première variante qui tient.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        symbol(report, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            temperature(report, size: 30)
                            Text("\(place.name) · \(WeatherService.condition(for: report.code))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            highLow(report)
                        }
                    }
                    HStack(spacing: 10) {
                        symbol(report, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            temperature(report, size: 26)
                            highLow(report)
                        }
                    }
                    VStack(spacing: 4) {
                        symbol(report, size: 20)
                        temperature(report, size: 18).minimumScaleFactor(0.7)
                    }
                }
                .lineLimit(1)
            } else {
                Label(module.error ?? tr("Chargement…", "Loading…"), systemImage: "cloud")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            Label(tr("Choisis une ville dans les réglages", "Pick a city in Settings"), systemImage: "cloud.sun")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Réglages

private struct WeatherSettingsView: View {
    @Bindable var module: WeatherModule

    var body: some View {
        SettingsSubheader(tr("Lieu", "Location"))
        SettingsRow(tr("Ville", "City"),
                    subtitle: module.place.map { [$0.name, $0.detail].filter { !$0.isEmpty }.joined(separator: " — ") }
                        ?? tr("Aucune ville choisie.", "No city selected.")) {
            Button {
                module.useCurrentLocation()
            } label: {
                Label(tr("Ma position", "My location"), systemImage: "location.fill")
            }
            .disabled(module.isLocating)
        }
        SettingsRow(tr("Rechercher une ville", "Search for a city")) {
            HStack(spacing: 8) {
                TextField(tr("Ex. : Lyon", "e.g. London"), text: $module.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { module.search() }
                Button(tr("Rechercher", "Search")) { module.search() }
                    .disabled(module.isSearching || module.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if let searchError = module.searchError {
            SettingsRow(searchError) { EmptyView() }
        }
        ForEach(module.searchResults) { result in
            SettingsRow(result.name, subtitle: result.detail) {
                Button(tr("Choisir", "Select")) { module.select(result) }
            }
        }
        SettingsSubheader(tr("Affichage", "Display"))
        PickerRow(tr("Unité", "Unit"), selection: $module.unit) {
            ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
        }
        ToggleRow(tr("Minimales et maximales", "Highs and lows"),
                  subtitle: tr("Températures du jour sous la condition.", "Today's temperatures below the condition."),
                  isOn: $module.showHighLow)
        if let error = module.error {
            SettingsRow(tr("État", "Status"), subtitle: error) {
                Button(tr("Réessayer", "Retry")) { module.refresh() }
            }
        }
    }
}
