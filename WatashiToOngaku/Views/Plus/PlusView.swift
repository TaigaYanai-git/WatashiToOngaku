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
                    Text(verbatim: S("毎日の記録、フレンド、9色のテーマカラーと背景は、これからも無料です。Plus では、音楽をもっと楽しむ機能が使えます。",
                                     "Daily songs, friends, the 9 theme colors and backgrounds stay free. Plus adds more ways to enjoy your music.",
                                     "매일의 기록, 친구, 9가지 테마 색상과 배경은 앞으로도 무료입니다. Plus에서는 음악을 더 즐길 수 있는 기능을 사용할 수 있습니다."))
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("rectangle.stack", S("タイムラインを5つ追加", "5 more timelines", "타임라인 5개 추가"),
                                S("「大学」「家族」のように、入れるフレンドを選んだタイムラインを作って切り替えられます",
                                  "Make timelines with the friends you choose, like \"College\" or \"Family\", and switch between them",
                                  "'대학', '가족'처럼 친구를 골라 타임라인을 만들고 전환할 수 있습니다"))
                        benefit("clock.arrow.circlepath", S("1年前まで遡れるタイムライン", "A year of timeline history", "1년 전까지 보는 타임라인"),
                                S("無料では2週間分。Plus なら1年前までのフレンドの投稿を見られます",
                                  "Free shows two weeks. With Plus, scroll back through a year of friends' posts",
                                  "무료는 2주. Plus는 1년 전까지 친구 게시물을 볼 수 있습니다"))
                        benefit("music.note.list", S("フレンドの月・年のプレイリスト", "Friends' monthly & yearly playlists", "친구의 월·연 플레이리스트"),
                                S("1か月や1年のあいだにフレンドが選んだ曲を、Apple Music でまとめて聴けます",
                                  "Listen to a month or a year of your friends' songs in Apple Music",
                                  "한 달, 1년 동안 친구들이 고른 곡을 Apple Music으로 모아 들을 수 있습니다"))
                        benefit("paintpalette", S("カスタムカラーとアイコンの固定", "Custom colors & a fixed app icon", "사용자 지정 색상과 아이콘 고정"),
                                S("テーマカラーを好きな色にできます（アイコンには反映されません）。アイコンはダークモードやテーマに左右されないものに固定できます",
                                  "Pick any theme color (not applied to the icon), and keep an icon that doesn't change with dark mode or theme",
                                  "테마 색상을 원하는 색으로 바꿀 수 있습니다（아이콘에는 반영되지 않음）. 아이콘은 다크 모드나 테마와 상관없이 고정할 수 있습니다"))
                        benefit("rectangle.slash", S("広告なし", "No ads", "광고 없음"),
                                S("タイムラインと今日の一曲に広告が出なくなります", "Removes ads from the timeline and Today", "타임라인과 오늘의 한 곡에 광고가 표시되지 않습니다"))
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
