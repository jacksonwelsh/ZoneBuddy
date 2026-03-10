import SwiftUI
import MusicKit

enum MusicPickerKind: String, CaseIterable, Identifiable {
    case playlist
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .playlist: "Playlists"
        case .album: "Albums"
        }
    }

    var emptyMessage: String {
        switch self {
        case .playlist: "No playlists in your library."
        case .album: "No albums in your library."
        }
    }
}

struct MusicPickerItem: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let artwork: Artwork?
    let kind: MusicPickerKind
}

struct PlaylistPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var items: [MusicPickerItem] = []
    @State private var searchText = ""
    @State private var selectedKind: MusicPickerKind = .playlist
    @State private var isLoading = false

    let selectedPlaylistID: String?
    let onSelect: (String, String, MusicPickerKind) -> Void
    let onRemove: () -> Void

    private var filteredItems: [MusicPickerItem] {
        let kindFiltered = items.filter { $0.kind == selectedKind }
        if searchText.isEmpty { return kindFiltered }
        return kindFiltered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .authorized:
                    itemList
                case .denied, .restricted:
                    ContentUnavailableView {
                        Label("Music Access Denied", systemImage: "music.note.list")
                    } description: {
                        Text("Grant access in Settings > Privacy & Security > Media & Apple Music.")
                    }
                default:
                    ProgressView("Requesting access…")
                }
            }
            .navigationTitle("Choose Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedPlaylistID != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
            .task {
                if authStatus != .authorized {
                    authStatus = await MusicAuthorization.request()
                }
                if authStatus == .authorized {
                    await loadLibrary()
                }
            }
        }
    }

    private var itemList: some View {
        List {
            Section {
                Picker("Type", selection: $selectedKind) {
                    ForEach(MusicPickerKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? selectedKind.emptyMessage : "No results.",
                    systemImage: "music.note"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    Button {
                        onSelect(item.id, item.name, item.kind)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            if let artwork = item.artwork {
                                ArtworkImage(artwork, width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if item.id == selectedPlaylistID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search \(selectedKind.label.lowercased())")
    }

    private func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }

        async let playlistItems = loadPlaylists()
        async let albumItems = loadAlbums()

        let (playlists, albums) = await (playlistItems, albumItems)
        items = playlists + albums
    }

    private func loadPlaylists() async -> [MusicPickerItem] {
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.name, ascending: true)
            let response = try await request.response()
            return response.items.map { playlist in
                MusicPickerItem(
                    id: playlist.id.rawValue,
                    name: playlist.name,
                    subtitle: playlist.standardDescription,
                    artwork: playlist.artwork,
                    kind: .playlist
                )
            }
        } catch {
            print("Failed to load playlists: \(error)")
            return []
        }
    }

    private func loadAlbums() async -> [MusicPickerItem] {
        do {
            var request = MusicLibraryRequest<Album>()
            request.sort(by: \.title, ascending: true)
            let response = try await request.response()
            return response.items.map { album in
                MusicPickerItem(
                    id: album.id.rawValue,
                    name: album.title,
                    subtitle: album.artistName,
                    artwork: album.artwork,
                    kind: .album
                )
            }
        } catch {
            print("Failed to load albums: \(error)")
            return []
        }
    }
}
