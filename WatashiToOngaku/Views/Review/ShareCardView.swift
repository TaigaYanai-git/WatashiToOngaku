import SwiftUI

/// ふりかえりをストーリーズなどにシェアする画像（ジャケットを並べたカード）。
/// シェアされた画像からアプリを知ってもらえるよう、下にアプリ名を入れる
struct ShareCardSheet: View {
    let title: String
    let entries: [SongEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview(title, image: Image(uiImage: image))) {
                        Label(S("シェアする", "Share"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                } else {
                    ProgressView().tint(.dlPrimary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("シェア画像", "Share Image")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .task { image = await render() }
        }
    }

    /// ジャケットを先に読み込んでから描く（ImageRenderer は AsyncImage の読み込みを待たないため）
    private func render() async -> UIImage? {
        let picks = Array(entries.sorted { $0.dayKey > $1.dayKey }.prefix(9))
        var artworks: [String: UIImage] = [:]
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for entry in picks {
                group.addTask {
                    guard let url = URL(string: entry.artworkURL), url.scheme?.hasPrefix("http") == true,
                          let (data, _) = try? await URLSession.shared.data(from: url) else { return (entry.artworkURL, nil) }
                    return (entry.artworkURL, UIImage(data: data))
                }
            }
            for await (url, image) in group { artworks[url] = image }
        }
        let card = ShareCard(title: title, entries: picks, artworks: artworks,
                             count: entries.count, topArtist: SongStats.topArtists(entries, limit: 1).first?.artist)
            .environment(\.colorScheme, ThemeStore.shared.isDark ? .dark : .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct ShareCard: View {
    let title: String
    let entries: [SongEntry]
    let artworks: [String: UIImage]
    let count: Int
    let topArtist: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(verbatim: title).font(.system(size: 26, weight: .bold)).foregroundColor(.dlText)
                Text(verbatim: S("\(count)曲の記録", "\(count) songs")).font(.system(size: 14)).foregroundColor(.dlTextSub)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 3), spacing: 8) {
                ForEach(entries) { entry in
                    Group {
                        if let image = artworks[entry.artworkURL] {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            ArtworkView(url: entry.artworkURL.hasPrefix("sample:") ? entry.artworkURL : "", cornerRadius: 0)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            if let topArtist {
                VStack(spacing: 2) {
                    Text(verbatim: S("よく選んだアーティスト", "Top Artist")).font(.system(size: 11)).foregroundColor(.dlTextSub)
                    Text(verbatim: topArtist).font(.system(size: 17, weight: .semibold)).foregroundColor(.dlText).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Image("TodayTabIcon").resizable().renderingMode(.template).frame(width: 14, height: 14)
                Text(verbatim: S("Our Music ・ 1日1曲の音楽日記", "Our Music · one song a day"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.dlPrimary)
        }
        .padding(28)
        .frame(width: 360, height: 560)
        .background(DlBackground())
    }
}
