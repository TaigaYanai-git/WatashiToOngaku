import GoogleMobileAds
import SwiftUI

/// タイムラインの投稿と同じ見た目のカードに入れた広告。「広告」と分かるように印を付ける
struct NativeAdCard: View {
    let ad: NativeAd

    var body: some View {
        NativeAdContent(ad: ad)
            .dlCard()
    }
}

private struct NativeAdContent: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> AdCardView {
        let adView = AdCardView()

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 18
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .subheadline).bold()
        headline.textColor = UIColor(Color.dlText)
        headline.numberOfLines = 1

        let advertiser = UILabel()
        advertiser.font = .preferredFont(forTextStyle: .caption1)
        advertiser.textColor = UIColor(Color.dlTextSub)

        let badge = UILabel()
        badge.text = S(" 広告 ", " Ad ")
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = UIColor(Color.dlTextSub)
        badge.layer.borderColor = UIColor(Color.dlTextLight).cgColor
        badge.layer.borderWidth = 1
        badge.layer.cornerRadius = 4
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let titles = UIStackView(arrangedSubviews: [headline, advertiser])
        titles.axis = .vertical
        titles.spacing = 1
        let header = UIStackView(arrangedSubviews: [icon, titles, badge])
        header.spacing = 10
        header.alignment = .center

        let media = MediaView()
        media.contentMode = .scaleAspectFill
        media.clipsToBounds = true
        media.layer.cornerRadius = 12
        media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 9.0 / 16.0).isActive = true

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.textColor = UIColor(Color.dlText)
        body.numberOfLines = 2

        let action = UIButton(type: .system)
        action.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).bold()
        action.backgroundColor = UIColor(Color.dlPrimaryBg)
        action.tintColor = UIColor(Color.dlPrimary)
        action.layer.cornerRadius = 12
        action.heightAnchor.constraint(equalToConstant: 40).isActive = true
        // タップは広告の画面全体で受ける（ボタン自身は反応させない）
        action.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [header, media, body, action])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: adView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
        ])

        adView.parts = .init(icon: icon, headline: headline, advertiser: advertiser, media: media, body: body, action: action)
        return adView
    }

    func updateUIView(_ adView: AdCardView, context: Context) {
        guard let parts = adView.parts else { return }
        parts.headline.text = ad.headline
        parts.advertiser.text = ad.advertiser
        parts.advertiser.isHidden = ad.advertiser == nil
        parts.icon.image = ad.icon?.image
        parts.icon.isHidden = ad.icon == nil
        parts.media.mediaContent = ad.mediaContent
        parts.body.text = ad.body
        parts.body.isHidden = ad.body == nil
        parts.action.setTitle(ad.callToAction, for: .normal)
        parts.action.isHidden = ad.callToAction == nil
        // 中身のない部品は広告に登録しない（隠した部品は枠の外にあると判定される）
        adView.headlineView = parts.headline
        adView.mediaView = parts.media
        adView.advertiserView = ad.advertiser == nil ? nil : parts.advertiser
        adView.iconView = ad.icon == nil ? nil : parts.icon
        adView.bodyView = ad.body == nil ? nil : parts.body
        adView.callToActionView = ad.callToAction == nil ? nil : parts.action
        adView.pendingAd = ad
        adView.setNeedsLayout()
    }

    /// 横幅に合わせた高さにする
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AdCardView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 72
        let size = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: size.height)
    }
}

/// 並べ終わって大きさが決まってから広告を結び付ける（先に結び付けると、部品が広告の枠の外にあると判定される）
final class AdCardView: NativeAdView {
    struct Parts {
        let icon: UIImageView
        let headline: UILabel
        let advertiser: UILabel
        let media: MediaView
        let body: UILabel
        let action: UIButton
    }

    var parts: Parts?
    var pendingAd: NativeAd?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let pendingAd, nativeAd !== pendingAd, bounds.width > 0, bounds.height > 0,
              let content = subviews.first, content.frame.maxY <= bounds.height + 0.5 else { return }
        // 中の部品の位置まで決めてから結び付ける
        content.layoutIfNeeded()
        guard let headline = headlineView, headline.frame.width > 0 else { return }
        nativeAd = pendingAd
    }
}

private extension UIFont {
    func bold() -> UIFont {
        UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor, size: 0)
    }
}
