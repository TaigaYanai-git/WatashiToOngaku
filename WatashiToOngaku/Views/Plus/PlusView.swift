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
                        benefit("rectangle.stack", S("タイムラインを5つまで", "Up to 5 timelines", "타임라인 최대 5개"),
                                S("「大学」「家族」のように、入れるフレンドを選んだタイムラインを作って切り替えられます",
                                  "Make timelines with the friends you choose, like \"College\" or \"Family\", and switch between them",
                                  "'대학', '가족'처럼 친구를 골라 타임라인을 만들고 전환할 수 있습니다"))
                        benefit("rectangle.slash", S("広告なし", "No ads", "광고 없음"),
                                S("タイムラインと今日の一曲に広告が出なくなります", "Removes ads from the timeline and Today", "타임라인과 오늘의 한 곡에 광고가 표시되지 않습니다"))
                        benefit("heart", S("開発を応援", "Support development"),
                                S("アプリを続けていくための力になります", "Helps keep the app going"))
                    }
                    .dlCard()
                }
                .padding(.horizontal, 20)
            }
            .background(DlBackground().ignoresSafeArea())
        }
        .compactPlanPicker()
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStorePolicyDestination(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: Bundle.main.urlSetting("PRIVACY_POLICY_URL") ?? URL(string: "https://www.apple.com/legal/privacy/")!, for: .privacyPolicy)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .tint(.dlPrimary)
        .onInAppPurchaseCompletion { _, _ in await plus.refresh() }
        .onChange(of: plus.isPlus) { _, isPlus in if isPlus { dismiss() } }
        // 「登録する」などの StoreKit の文言も、アプリで選んだ言語にそろえる
        .environment(\.locale, .app)
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

private extension View {
    /// プランを横並びの小さな選択肢にして、上の Plus の説明が隠れないようにする（iOS 18 から）
    @ViewBuilder
    func compactPlanPicker() -> some View {
        if #available(iOS 18.0, *) {
            subscriptionStoreControlStyle(.compactPicker)
        } else {
            self
        }
    }
}
