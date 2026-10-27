import SwiftUI

/// ふりかえりをストーリーズなどにシェアする画像（よく選んだアーティストのランキング）。
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
        let ranking = SongStats.topArtists(entries)
        var artworks: [String: UIImage] = [:]
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for item in ranking {
                group.addTask {
                    guard let url = URL(string: item.artworkURL), url.scheme?.hasPrefix("http") == true,
                          let (data, _) = try? await URLSession.shared.data(from: url) else { return (item.artworkURL, nil) }
                    return (item.artworkURL, UIImage(data: data))
                }
            }
            for await (url, image) in group { artworks[url] = image }
        }
        let card = ShareCard(title: title, ranking: ranking, artworks: artworks, count: entries.count)
            .environment(\.colorScheme, ThemeStore.shared.isDark ? .dark : .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// 「よく選んだアーティスト」のランキング。1位は大きなジャケットで、2位からは一覧で並べる
private struct ShareCard: View {
    let title: String
    let ranking: [SongStats.ArtistCount]
    let artworks: [String: UIImage]
    let count: Int

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(verbatim: title).font(.system(size: 26, weight: .bold)).foregroundColor(.dlText)
                Text(verbatim: S("よく選んだアーティスト", "Top Artists")).font(.system(size: 14)).foregroundColor(.dlTextSub)
            }
            if let first = ranking.first {
                VStack(spacing: 8) {
                    artwork(first.artworkURL, size: 132, cornerRadius: 14)
                        .overlay(alignment: .topLeading) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.dlPrimary)
                                .clipShape(Circle())
                                .offset(x: -10, y: -10)
                        }
                    Text(verbatim: first.artist).font(.system(size: 19, weight: .bold)).foregroundColor(.dlText).lineLimit(1)
                    Text(verbatim: songCount(first.count)).font(.system(size: 13)).foregroundColor(.dlTextSub)
                }
            }
            VStack(spacing: 8) {
                ForEach(Array(ranking.dropFirst().enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text(verbatim: "\(index + 2)")
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundColor(.dlTextSub)
                            .frame(width: 18)
                        artwork(item.artworkURL, size: 36, cornerRadius: 7)
                        Text(verbatim: item.artist).font(.system(size: 14, weight: .semibold)).foregroundColor(.dlText).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: songCount(item.count)).font(.system(size: 12)).foregroundColor(.dlTextSub)
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(verbatim: S("\(count)曲の記録", "\(count) songs", "\(count)곡의 기록")).font(.system(size: 11)).foregroundColor(.dlTextSub)
                HStack(spacing: 6) {
                    Image("TodayTabIcon").resizable().renderingMode(.template).frame(width: 14, height: 14)
                    Text(verbatim: S("Our Music ・ 1日1曲の音楽日記", "Our Music · one song a day"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.dlPrimary)
            }
        }
        .padding(28)
        .frame(width: 360, height: 560)
        .background(DlBackground())
    }

    private func songCount(_ n: Int) -> String {
        S("\(n)曲", n == 1 ? "1 song" : "\(n) songs", "\(n)곡")
    }

    @ViewBuilder
    private func artwork(_ url: String, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let image = artworks[url] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ArtworkView(url: url.hasPrefix("sample:") ? url : "", cornerRadius: 0)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
