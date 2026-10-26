import StoreKit
import SwiftUI

/// 「Our Music Plus」の案内と購入。値段・期間・自動更新の説明・復元は StoreKit の画面に任せる
struct PlusView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var plus = PlusStore.shared

    var body: some View {
        SubscriptionStoreView(productIDs: PlusStore.productIDs) {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(LinearGradient.dlPrimary)
                        .padding(.top, 28)
                    Text(verbatim: S("Our Music Plus", "Our Music Plus"))
                        .font(.title2.weight(.bold))
                        .foregroundColor(.dlText)
                    Text(verbatim: S("毎日の記録、フレンド、すべてのテーマカラーと背景は、これからも無料です。Plus では、音楽をもっと楽しむ機能が使えます。",
                                     "Daily songs, friends and all theme colors stay free. Plus adds more ways to enjoy your music."))
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("music.note.list", S("1年のプレイリスト", "Yearly playlists"),
                                S("1年ぶんの「今日の一曲」を、Apple Music のプレイリストで聴けます", "Listen to a whole year of your songs in Apple Music"))
                        benefit("calendar.badge.clock", S("長い期間のカスタムプレイリスト", "Longer custom playlists"),
                                S("好きな期間の曲をまとめるプレイリストを、\(PlusStore.freeCustomPlaylistDays)日より長い期間でも作れます", "Make custom playlists longer than \(PlusStore.freeCustomPlaylistDays) days"))
                        benefit("heart", S("開発を応援", "Support development"),
                                S("広告なしで続けていくための力になります", "Helps keep the app ad-free"))
                    }
                    .dlCard()
                }
                .padding(.horizontal, 20)
            }
            .background(DlBackground().ignoresSafeArea())
        }
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStorePolicyDestination(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: Bundle.main.urlSetting("PRIVACY_POLICY_URL") ?? URL(string: "https://www.apple.com/legal/privacy/")!, for: .privacyPolicy)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .tint(.dlPrimary)
        .onInAppPurchaseCompletion { _, _ in await plus.refresh() }
        .onChange(of: plus.isPlus) { _, isPlus in if isPlus { dismiss() } }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dlPrimaryBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                Text(verbatim: detail).font(.caption).foregroundColor(.dlTextSub)
            }
        }
    }
}

/// Plus の機能を開いたときに、中身の代わりに出す案内
struct PlusLockedCard: View {
    let title: String
    @State private var showPlus = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.title2).foregroundColor(.dlPrimary)
            Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).multilineTextAlignment(.center)
            Text(verbatim: S("Our Music Plus で使えます", "Available with Our Music Plus"))
                .font(.caption).foregroundColor(.dlTextSub)
            Button(S("Plus について見る", "Learn About Plus")) { showPlus = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 24)
        .sheet(isPresented: $showPlus) { PlusView() }
    }
}
