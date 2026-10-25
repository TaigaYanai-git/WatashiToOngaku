import StoreKit
import SwiftUI

/// 「私と音楽 Plus」の案内と購入。値段・期間・自動更新の説明・復元は StoreKit の画面に任せる
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
                    Text(verbatim: S("私と音楽 Plus", "Me & Music Plus"))
                        .font(.title2.weight(.bold))
                        .foregroundColor(.dlText)
                    Text(verbatim: S("毎日の記録とフレンド機能は、これからも無料です。Plus では、音楽をもっと楽しむ機能が使えます。",
                                     "Daily songs and friends stay free. Plus adds more ways to enjoy your music."))
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("music.note.list", S("月・年のプレイリスト", "Monthly & yearly playlists"),
                                S("自分とフレンドが選んだ1か月・1年ぶんの曲を、Apple Music でまとめて聴けます", "Listen to a month or a year of songs from you and your friends in Apple Music"))
                        benefit("paintpalette", S("すべてのテーマカラーと背景", "All theme colors & patterns"),
                                S("9色のテーマカラーと6種類の背景から選べます", "Choose from 9 colors and 6 background patterns"))
                        benefit("app.badge", S("テーマカラーのアイコン", "Theme-colored app icon"),
                                S("ホーム画面のアイコンもテーマカラーにできます", "Match your Home Screen icon to your theme"))
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
            Text(verbatim: S("私と音楽 Plus で使えます", "Available with Me & Music Plus"))
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
