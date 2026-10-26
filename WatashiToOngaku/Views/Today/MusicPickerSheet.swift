import AVFoundation
import MusicKit
import SwiftUI

// Apple Music のカタログから曲を検索して「今日の一曲」を選ぶ（V-Diary の画面を元にしたもの）。
// 選んだときに曲名・アーティスト・ジャケット・試聴 URL だけ保存するので、
// Apple Music の契約がなくても検索と試聴ができる。

struct MusicPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hasSelection: Bool
    let onSelect: (PickedSong) -> Void
    let onClear: () -> Void

    @State private var authStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var searchText = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchErrorMessage: String?
    /// 選んだ曲。流す30秒を選ぶ画面に進む
    @State private var picked: PickedSong?
    @ObservedObject private var player = PreviewPlayer.shared

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .authorized: resultsList
                case .notDetermined: permissionRequestView
                default: permissionDeniedView
                }
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("今日の一曲を選ぶ", "Pick Today's Song")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }
                        .foregroundColor(.dlPrimary)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: S("曲名やアーティスト名で検索", "Search songs or artists"))
            .onChange(of: searchText) { _, newValue in scheduleSearch(newValue) }
            .navigationDestination(item: $picked) { song in
                ClipRangeView(song: song) { final in
                    onSelect(final)
                    dismiss()
                }
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: - 許可

    private var permissionRequestView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note").font(.system(size: 40)).foregroundColor(.dlPrimary)
            Text(S("Apple Musicから曲を検索するにはアクセスを許可してください",
                   "Allow access to search songs from Apple Music"))
                .multilineTextAlignment(.center)
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 32)
            Button(S("Apple Musicへのアクセスを許可", "Allow Apple Music Access")) {
                Task { authStatus = await MusicAuthorization.request() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list").font(.system(size: 40)).foregroundColor(.dlTextLight)
            Text(S("Apple Musicへのアクセスが許可されていません。\n設定アプリから許可してください",
                   "Apple Music access isn't allowed. Please enable it in Settings"))
                .multilineTextAlignment(.center)
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 32)
            Button(S("設定を開く", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 検索結果

    private var resultsList: some View {
        List {
            if hasSelection {
                Section {
                    Button(role: .destructive) {
                        player.stop()
                        onClear()
                        dismiss()
                    } label: {
                        Label(S("この日の曲を外す", "Remove This Day's Song"), systemImage: "xmark.circle")
                    }
                }
            }
            Section {
                ForEach(results, id: \.id) { songRow($0) }
            } footer: {
                if !results.isEmpty {
                    Text(S("ジャケットをタップすると試聴、曲名をタップすると選べます",
                           "Tap the artwork to preview, tap the title to choose"))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isSearching {
                ProgressView().tint(.dlPrimary)
            } else if let message = searchErrorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundColor(.orange)
                    Text(S("検索に失敗しました", "Search failed"))
                        .font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                    Text(message).font(.caption).foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            } else if searchText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title).foregroundColor(.dlTextLight)
                    Text(S("今日の気分に合う曲を探しましょう", "Find a song that fits today"))
                        .font(.subheadline).foregroundColor(.dlTextSub)
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 12) {
            PlayableArtwork(id: song.id.rawValue,
                            artworkURL: song.artwork?.url(width: 120, height: 120)?.absoluteString ?? "",
                            previewURL: song.previewAssets?.first?.url?.absoluteString,
                            size: 52, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                Text(song.artistName).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
            }
            Spacer()
            Image(systemName: "plus.circle").font(.title3).foregroundColor(.dlPrimary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { select(song) }
        .listRowBackground(Color.clear)
    }

    // MARK: - 検索

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            searchErrorMessage = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 入力が止まってから検索する
            guard !Task.isCancelled else { return }
            await performSearch(query)
        }
    }

    @MainActor
    private func performSearch(_ query: String) async {
        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            guard !Task.isCancelled else { return }
            results = Array(response.songs)
        } catch {
            results = []
            searchErrorMessage = error.localizedDescription
        }
    }

    private func select(_ song: Song) {
        player.stop()
        picked = PickedSong(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            albumTitle: song.albumTitle ?? "",
            artworkURL: song.artwork?.url(width: 600, height: 600)?.absoluteString ?? "",
            previewURL: song.previewAssets?.first?.url?.absoluteString,
            appleMusicURL: song.url?.absoluteString,
            duration: song.duration ?? 0
        )
    }
}
