import AppTrackingTransparency
import GoogleMobileAds
import UIKit

/// 広告の識別子（IDFA）を使ってよいかを聞く（App Tracking Transparency）。
/// 広告 SDK は、ここで答えが出るまで初期化も読み込みもしない（答えの前にデータを集めないため）。
@MainActor
enum TrackingConsent {
    private static var task: Task<Void, Never>?

    /// 起動時に呼ぶ。まだ聞いていなければ、アプリが前面に出てから許可のダイアログを出す。
    /// iOS はアプリが前面でないときや他のダイアログと重なったときに何も出さずに返すことがあるので、出るまでやり直す
    static func requestIfNeeded() async {
        if let task { return await task.value }
        let task = Task { @MainActor in
            var attempts = 0
            while ATTrackingManager.trackingAuthorizationStatus == .notDetermined, attempts < 20 {
                attempts += 1
                // 前面になるまで待ち、画面が出そろうまで少し置く
                while UIApplication.shared.applicationState != .active {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                try? await Task.sleep(for: .milliseconds(800))
                guard UIApplication.shared.applicationState == .active else { continue }
                _ = await ATTrackingManager.requestTrackingAuthorization()
                if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        self.task = task
        await task.value
    }
}

/// タイムラインに挟む広告（AdMob のネイティブ広告）を読み込んでおく。Plus の人には出さない。
/// 広告はフレンドの投稿の間にだけ出す（中身のない画面やボタンのすぐ近くには出さない：AdMob のポリシー）。
/// 1つの広告は1つの画面にしか出せないので、表示する枠の数だけ読み込む
@MainActor
final class NativeAdStore: NSObject, ObservableObject {
    static let shared = NativeAdStore()

    /// 何件の投稿ごとに広告を挟むか
    static let interval = 5
    /// 一度に持っておく広告の数
    private static let maxAds = 5

    @Published private(set) var ads: [NativeAd] = []

    private var loader: AdLoader?
    /// 広告 SDK の初期化（同時に呼ばれても1回だけ行い、全員がその完了を待つ）
    private var startTask: Task<Void, Never>?

    private static var unitID: String { Bundle.main.object(forInfoDictionaryKey: "AdMobNativeUnitID") as? String ?? "" }

    /// 投稿の数に合わせて、足りない広告を読み込む
    func load(forPosts count: Int) async {
        let needed = min(Self.maxAds, count / Self.interval)
        guard !PlusStore.shared.isPlus, ads.count < needed, loader?.isLoading != true, !Self.unitID.isEmpty,
              !SocialStore.shared.isPreview else { return }
        await startIfNeeded()
        guard !PlusStore.shared.isPlus, ads.count < needed, loader?.isLoading != true else { return }
        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = needed - ads.count
        let loader = AdLoader(adUnitID: Self.unitID, rootViewController: nil, adTypes: [.native], options: [options])
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }

    private func startIfNeeded() async {
        if let startTask { return await startTask.value }
        let task = Task { @MainActor in
            // 先にトラッキングの許可を聞き、答えが出てから広告 SDK を動かす
            // （許可されなくても、興味に合わせない広告が出る）
            await TrackingConsent.requestIfNeeded()
            _ = await MobileAds.shared.start()
        }
        startTask = task
        await task.value
    }

    /// slot 番目（0 から）の枠に出す広告
    func ad(forSlot slot: Int) -> NativeAd? {
        guard !PlusStore.shared.isPlus, ads.indices.contains(slot) else { return nil }
        return ads[slot]
    }
}

extension NativeAdStore: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.ads.append(nativeAd) }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("[Ads] 広告を読み込めませんでした: \(error.localizedDescription)")
    }
}
