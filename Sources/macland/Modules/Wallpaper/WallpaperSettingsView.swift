import SwiftUI

/// Réglages du module Fonds d'écran : sources du bureau et du verrouillage, bibliothèque, playlists.
struct WallpaperSettingsView: View {
    @Bindable var module: WallpaperModule

    private static let intervals: [(minutes: Double, label: () -> String)] = [
        (1, { "1 min" }), (5, { "5 min" }), (15, { "15 min" }), (30, { "30 min" }),
        (60, { tr("1 h", "1 hr") }), (180, { tr("3 h", "3 hr") }), (720, { tr("12 h", "12 hr") }), (1440, { tr("1 jour", "1 day") }),
    ]

    var body: some View {
        SettingsSubheader(tr("Bureau", "Desktop"))
        SettingsRow(tr("Fond du bureau", "Desktop wallpaper"),
                    subtitle: module.isPaused ? tr("En pause (batterie, économie d'énergie ou session verrouillée).",
                                                    "Paused (battery, Low Power Mode or locked session).") : nil) {
            SourceMenu(module: module, selection: $module.desktopSource)
        }
        PickerRow(tr("Ajustement", "Scaling"), selection: $module.scaling) {
            Text(tr("Remplir", "Fill")).tag(WallpaperScaling.fill)
            Text(tr("Entière", "Fit")).tag(WallpaperScaling.fit)
        }
        SettingsSubheader(tr("Écran de verrouillage", "Lock screen"))
        PickerRow(tr("Affichage", "Display"),
                  subtitle: module.lockMode == .native
                      ? tr("La vidéo est animée, même quand macland est fermé.", "The video is animated, even when macland is closed.")
                      : tr("Une image tirée de la vidéo.", "A still taken from the video."),
                  selection: $module.lockMode) {
            Text(tr("Vidéo animée", "Animated video")).tag(LockScreenMode.native)
            Text(tr("Image fixe", "Still image")).tag(LockScreenMode.still)
        }
        .disabled(!AerialCatalog.isAvailable)
        ToggleRow(tr("Comme le bureau", "Same as desktop"), isOn: $module.lockFollowsDesktop)
        if !module.lockFollowsDesktop {
            SettingsRow(tr("Fond de l'écran de verrouillage", "Lock screen wallpaper")) {
                SourceMenu(module: module, selection: $module.lockSource)
            }
        }
        if let error = module.nativeError {
            SettingsRow(tr("Impossible d'appliquer la vidéo", "Couldn't apply the video"), subtitle: error) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        SettingsSubheader(tr("Mise en pause", "Pausing"))
        ToggleRow(tr("Quand des fenêtres couvrent le bureau", "When windows cover the desktop"),
                  subtitle: tr("La vidéo ne joue que si on peut la voir.", "The video only plays when it can be seen."),
                  isOn: $module.pauseWhenCovered)
        ToggleRow(tr("Quand une app est en plein écran", "When an app is full screen"), isOn: $module.pauseInFullScreen)
        ToggleRow(tr("Sur batterie", "On battery"), isOn: $module.pauseOnBattery)
        ToggleRow(tr("En mode économie d'énergie", "In Low Power Mode"), isOn: $module.pauseInLowPower)
        SettingsSubheader(tr("Bibliothèque", "Library"))
        LibraryGrid(module: module)
        SettingsSubheader(tr("Playlists", "Playlists"))
        ToggleRow(tr("Fondu enchaîné", "Crossfade"), subtitle: tr("Transition douce entre deux vidéos d'une playlist.",
                                                                  "Smooth transition between two videos of a playlist."),
                  isOn: $module.crossfade)
        ForEach(module.library.playlists) { playlist in
            PlaylistEditor(module: module, playlist: playlist, intervals: Self.intervals)
        }
        SettingsRow(tr("Nouvelle playlist", "New playlist"),
                    subtitle: tr("Plusieurs vidéos qui s'enchaînent à l'intervalle de ton choix.",
                                 "Several videos that rotate at the interval you choose.")) {
            Button(tr("Créer", "Create")) {
                module.library.createPlaylist(named: tr("Playlist \(module.library.playlists.count + 1)",
                                                        "Playlist \(module.library.playlists.count + 1)"))
            }
        }
    }
}

/// Menu de choix d'une source : aucune, une vidéo ou une playlist.
private struct SourceMenu: View {
    let module: WallpaperModule
    @Binding var selection: WallpaperSource

    var body: some View {
        Menu(module.sourceName(selection)) {
            Button(tr("Aucun", "None")) { selection = .none }
            if !module.library.videos.isEmpty {
                Section(tr("Vidéos", "Videos")) {
                    ForEach(module.library.videos) { video in
                        Button(video.name) { selection = .video(video.id) }
                    }
                }
            }
            if !module.library.playlists.isEmpty {
                Section(tr("Playlists", "Playlists")) {
                    ForEach(module.library.playlists) { playlist in
                        Button(playlist.name) { selection = .playlist(playlist.id) }
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// Vignettes des vidéos importées, avec un bouton d'ajout.
private struct LibraryGrid: View {
    let module: WallpaperModule

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(module.library.videos) { video in
                VideoTile(module: module, video: video)
            }
            Button(action: module.importVideos) {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    Text(tr("Ajouter des vidéos", "Add videos")).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 112)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct VideoTile: View {
    let module: WallpaperModule
    let video: WallpaperVideo

    var body: some View {
        let isOnDesktop = module.currentDesktopVideo == video.id
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.primary.opacity(0.08)
                if let thumbnail = module.library.thumbnails[video.id] {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOnDesktop ? Color.accentColor : .clear, lineWidth: 2)
            )
            Text(video.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture { module.desktopSource = .video(video.id) }
        .contextMenu {
            Button(tr("Mettre sur le bureau", "Set as desktop")) { module.desktopSource = .video(video.id) }
            Button(tr("Mettre sur l'écran de verrouillage", "Set as lock screen")) {
                module.lockFollowsDesktop = false
                module.lockSource = .video(video.id)
            }
            Button(tr("Afficher dans le Finder", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([video.url])
            }
            Divider()
            Button(tr("Retirer de la bibliothèque", "Remove from library"), role: .destructive) {
                module.removeVideo(video.id)
            }
        }
        .help(tr("Clic : mettre sur le bureau. Clic droit : plus d'options.", "Click: set as desktop. Right-click: more options."))
    }
}

/// Édition d'une playlist : nom, intervalle, ordre aléatoire, vidéos incluses.
private struct PlaylistEditor: View {
    let module: WallpaperModule
    let playlist: WallpaperPlaylist
    let intervals: [(minutes: Double, label: () -> String)]

    private func update(_ change: (inout WallpaperPlaylist) -> Void) {
        var copy = playlist
        change(&copy)
        module.library.updatePlaylist(copy)
        module.playlistDidChange(playlist.id)
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("Nom", "Name")).foregroundStyle(.secondary)
                    TextField("", text: Binding(get: { playlist.name }, set: { name in update { $0.name = name } }))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(tr("Changer toutes les", "Change every")).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { playlist.intervalMinutes },
                                                  set: { minutes in update { $0.intervalMinutes = minutes } })) {
                        ForEach(intervals, id: \.minutes) { Text($0.label()).tag($0.minutes) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Toggle(tr("Aléatoire", "Shuffle"), isOn: Binding(get: { playlist.shuffle },
                                                                    set: { value in update { $0.shuffle = value } }))
                }
                if module.library.videos.isEmpty {
                    Text(tr("Ajoute d'abord des vidéos à la bibliothèque.", "Add videos to the library first."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(module.library.videos) { video in
                    Toggle(video.name, isOn: Binding(
                        get: { playlist.videoIDs.contains(video.id) },
                        set: { included in
                            update { list in
                                if included { list.videoIDs.append(video.id) } else { list.videoIDs.removeAll { $0 == video.id } }
                            }
                        }))
                }
                Button(tr("Supprimer la playlist", "Delete playlist"), role: .destructive) {
                    module.removePlaylist(playlist.id)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(playlist.name).font(.system(size: 13.5, weight: .medium))
                Text(tr("\(playlist.videoIDs.count) vidéo\(playlist.videoIDs.count > 1 ? "s" : "")",
                        "\(playlist.videoIDs.count) video\(playlist.videoIDs.count == 1 ? "" : "s")"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
