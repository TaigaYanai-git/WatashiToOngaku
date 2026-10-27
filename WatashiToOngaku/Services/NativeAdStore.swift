import AppTrackingTransparency
import GoogleMobileAds
import UIKit

/// タイムラインに挟む広告（AdMob のネイティブ広告）を読み込んでおく。Plus の人には出さない。
/// 1つの広告は1つの画面にしか出せないので、表示する枠の数だけ読み込む
@MainActor
final class NativeAdStore: NSObject, ObservableObject {
    static let shared = NativeAdStore()

    /// 何件の投稿ごとに広告を挟むか
    static let interval = 5
    /// 一度に持っておく広告の数
    private static let maxAds = 5

    @Published private(set) var ads: [NativeAd] = []
    /// 「今日の一曲」で曲を選ぶ前の画面の下に出す広告（タイムラインとは別に1つ持つ）
    @Published private(set) var todayAd: NativeAd?

    private var loader: AdLoader?
    private var todayLoader: AdLoader?
    private var started = false

    private static var unitID: String { Bundle.main.object(forInfoDictionaryKey: "AdMobNativeUnitID") as? String ?? "" }

    /// 投稿の数に合わせて、足りない広告を読み込む
    func load(forPosts count: Int) async {
        let needed = min(Self.maxAds, count / Self.interval)
        guard !PlusStore.shared.isPlus, ads.count < needed, loader?.isLoading != true, !Self.unitID.isEmpty,
              !SocialStore.shared.isPreview else { return }
        await startIfNeeded()
        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = needed - ads.count
        let loader = AdLoader(adUnitID: Self.unitID, rootViewController: nil, adTypes: [.native], options: [options])
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }

    /// 「今日の一曲」の広告を読み込む
    func loadToday() async {
        guard !PlusStore.shared.isPlus, todayAd == nil, todayLoader?.isLoading != true, !Self.unitID.isEmpty,
              !SocialStore.shared.isPreview else { return }
        await startIfNeeded()
        let loader = AdLoader(adUnitID: Self.unitID, rootViewController: nil, adTypes: [.native], options: nil)
        loader.delegate = self
        todayLoader = loader
        loader.load(Request())
    }

    private func startIfNeeded() async {
        guard !started else { return }
        started = true
        // 広告の識別子を使ってよいか聞く（許可されなくても、興味に合わせない広告が出る）
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        _ = await MobileAds.shared.start()
    }

    /// slot 番目（0 から）の枠に出す広告
    func ad(forSlot slot: Int) -> NativeAd? {
        guard !PlusStore.shared.isPlus, ads.indices.contains(slot) else { return nil }
        return ads[slot]
    }
}

extension NativeAdStore: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        let source = ObjectIdentifier(adLoader)
        Task { @MainActor in
            if let todayLoader = self.todayLoader, ObjectIdentifier(todayLoader) == source {
                self.todayAd = nativeAd
            } else {
                self.ads.append(nativeAd)
            }
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("[Ads] 広告を読み込めませんでした: \(error.localizedDescription)")
    }
}
