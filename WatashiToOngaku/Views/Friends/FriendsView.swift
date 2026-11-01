import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// フレンドの申請（招待リンク・QRコード・フレンドコード）・届いた申請の承認と、フレンドの一覧
struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @State private var codeInput = ""
    @State private var showScanner = false
    @State private var showMyQR = false
    @State private var message: String?
    @State private var declining: PendingFriend?
    @State private var confirmingOfficial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !social.incomingRequests.isEmpty { incomingCard }
                    myCard
                    // 開発者とはまだフレンドでなければ、誘う
                    if let official = social.official, !social.followsOfficial, !social.isOfficialOwner { OfficialCard(official: official) }
                    addCard
                    if !social.outgoingRequests.isEmpty { outgoingCard }
                    FriendListCard()
                }
                .padding(20)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("フレンド", "Friends")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { url in
                    showScanner = false
                    Task { await add { await social.addFriend(url: url) } }
                }
            }
            .sheet(isPresented: $showMyQR) { MyQRSheet() }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
            .confirmationDialog(Text(verbatim: declining.map { S("\($0.nickname)さんからの申請", "Request from \($0.nickname)", "\($0.nickname)님의 신청") } ?? ""),
                                isPresented: Binding(get: { declining != nil }, set: { if !$0 { declining = nil } }),
                                titleVisibility: .visible, presenting: declining) { request in
                Button(S("申請を断る", "Decline"), role: .destructive) { social.decline(request, block: false) }
                Button(S("断ってブロックする", "Decline and Block"), role: .destructive) { social.decline(request, block: true) }
            } message: { _ in
                Text(verbatim: S("相手には知らせません。ブロックすると、この人からの申請はもう届きません。",
                                 "They won't be notified. Blocking stops further requests from them."))
            }
            .officialFriendConfirmation(isPresented: $confirmingOfficial) { message = $0 }
            .refreshable { await social.refresh() }
            .task { await social.refresh() }
        }
    }

    private var myCard: some View {
        VStack(spacing: 12) {
            ProfileHeader()
            Divider()
            Text(verbatim: S("あなたのフレンドコード", "Your Friend Code"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.dlTextSub)
            Text(social.friendCode.isEmpty ? "--------" : social.friendCode)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(.dlText)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                if let url = social.inviteURL {
                    ShareLink(item: url,
                              subject: Text(verbatim: S("Our Music", "Our Music")),
                              message: Text(verbatim: S("「Our Music」でフレンドになろう！フレンドコード：\(social.friendCode)",
                                                        "Be my friend on Our Music! Code: \(social.friendCode)", "Our Music에서 친구가 되어요! 친구 코드: \(social.friendCode)"))) {
                        Label(S("招待リンクを送る", "Send Invite"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button { showMyQR = true } label: {
                    Image(systemName: "qrcode").font(.headline).foregroundColor(.dlPrimary)
                        .frame(width: 52, height: 52).background(Color.dlPrimaryBg).cornerRadius(18)
                }
                .accessibilityLabel(S("自分のQRコード", "My QR Code"))
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .dlCard()
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: S("フレンドを申請", "Add a Friend"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            HStack(spacing: 10) {
                TextField(S("フレンドコード（8文字）", "Friend code (8 characters)"), text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(DarkTextFieldStyle())
                Button(S("申請", "Request")) {
                    let code = codeInput
                    Task { await add { await social.addFriend(code: code) } }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .disabled(codeInput.count < 8)
            }
            Button { showScanner = true } label: {
                Label(S("QRコードを読み取る", "Scan QR Code"), systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(SecondaryButtonStyle())
            .font(.subheadline)
        }
        .dlCard()
    }

    /// 届いた申請。承認するとお互いの曲が見えるようになる
    private var incomingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: S("フレンド申請（\(social.incomingRequests.count)件）", "Friend Requests (\(social.incomingRequests.count))", "친구 신청 (\(social.incomingRequests.count)건)"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            ForEach(social.incomingRequests) { request in
                HStack(spacing: 12) {
                    AvatarView(code: request.code, version: request.avatarVersion, nickname: request.nickname)
                    Text(request.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                    Spacer()
                    Button(S("断る", "Decline")) { declining = request }
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                    Button(S("承認", "Accept")) {
                        Task {
                            message = await social.approve(request)
                                ? S("\(request.nickname)さんとフレンドになりました！", "You and \(request.nickname) are now friends!", "\(request.nickname)님과 친구가 되었습니다!")
                                : (social.lastError ?? S("承認できませんでした", "Couldn't accept"))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.dlPrimary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    /// 送って、承認を待っている申請
    private var outgoingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: S("承認待ち", "Pending"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            ForEach(social.outgoingRequests) { request in
                HStack(spacing: 12) {
                    AvatarView(code: request.code, version: request.avatarVersion, nickname: request.nickname)
                    Text(request.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                    Spacer()
                    Button(S("取り消す", "Cancel")) { Task { await social.cancelRequest(request) } }
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                }
            }
            Text(verbatim: S("相手が承認すると、フレンドになります。", "You'll become friends once they accept."))
                .font(.caption)
                .foregroundColor(.dlTextLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func add(_ action: () async -> SocialStore.AddResult?) async {
        guard let result = await action() else {
            message = social.lastError ?? S("申請できませんでした", "Couldn't send the request")
            return
        }
        codeInput = ""
        if result == .confirmOfficial {
            confirmingOfficial = true
        } else {
            message = SocialStore.message(for: result)
        }
    }
}

/// 開発者とフレンドになる誘い。申請はすぐ通り、開発者の毎日の一曲がタイムラインに流れる
struct OfficialCard: View {
    let official: Friend
    @ObservedObject private var social = SocialStore.shared
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(friend: official, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(official.nickname).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                    OfficialBadge()
                }
                Text(verbatim: S("開発者とフレンドになると、毎日の一曲がタイムラインに流れます。あなたが共有した曲も開発者に届き、いいねが付くことがあります",
                                 "Be friends with the developer to see their daily song. Your shared songs also reach the developer, who may like them",
                                 "개발자와 친구가 되면 매일의 한 곡이 타임라인에 흐릅니다. 공유한 곡도 개발자에게 전달되며, 좋아요를 받을 수 있습니다"))
                    .font(.caption).foregroundColor(.dlTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                confirming = true
            } label: {
                Text(verbatim: S("フレンドになる", "Add Friend", "친구 되기"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.dlPrimary))
            }
        }
        .dlCard()
        .officialFriendConfirmation(isPresented: $confirming) { message = $0 }
        .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }
}

extension View {
    /// 開発者とフレンドになる前の確認。「フレンドになる」を選んだら befriendOfficial を呼び、結果の文を渡す
    func officialFriendConfirmation(isPresented: Binding<Bool>, done: @escaping (String) -> Void) -> some View {
        alert(Text(verbatim: SocialStore.officialConfirmTitle), isPresented: isPresented) {
            Button(S("キャンセル", "Cancel", "취소"), role: .cancel) {}
            Button(S("フレンドになる", "Add Friend", "친구 되기")) {
                Task { done(SocialStore.message(for: await SocialStore.shared.befriendOfficial())) }
            }
        } message: {
            Text(verbatim: SocialStore.officialConfirmMessage)
        }
    }
}

/// 公式アカウント（開発者）の印
struct OfficialBadge: View {
    var body: some View {
        Text(verbatim: S("開発者", "Developer", "개발자"))
            .font(.caption2.weight(.semibold))
            .foregroundColor(.dlPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.dlPrimaryBg))
            // 名前が長くても、印は縮めない
            .fixedSize()
    }
}

/// 自分の招待リンクの QR コード
private struct MyQRSheet: View {
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            if let url = social.inviteURL, let image = Self.qrImage(url.absoluteString) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(16).background(Color.white).cornerRadius(20)
            }
            Text(social.friendCode).font(.system(.title3, design: .monospaced).weight(.bold)).foregroundColor(.dlText)
            Button(S("閉じる", "Close")) { dismiss() }.buttonStyle(SecondaryButtonStyle()).padding(.horizontal, 60)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DlBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// QR コードの読み取り（招待リンクの URL を読む）
private struct QRScannerSheet: View {
    let onFound: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScannerRepresentable(onFound: onFound).ignoresSafeArea()
                } else {
                    Text(verbatim: S("この端末ではカメラでの読み取りが使えません。フレンドコードを入力してください。",
                                     "Scanning isn't available on this device. Please enter a friend code."))
                        .font(.subheadline).foregroundColor(.dlTextSub).multilineTextAlignment(.center).padding(32)
                }
            }
            .navigationTitle(Text(verbatim: S("QRコードを読み取る", "Scan QR Code")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button(S("閉じる", "Close")) { dismiss() } }
            }
        }
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (URL) -> Void
        private var done = false
        init(onFound: @escaping (URL) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                guard !done, let text = code.payloadStringValue, let url = URL(string: text),
                      SocialStore.code(in: url) != nil else { continue }
                done = true
                scanner.stopScanning()
                onFound(url)
            }
        }
    }
}

/// フレンドの一覧。「…」からフレンドをやめる・ブロックする（フレンド画面と設定で使う）
struct FriendListCard: View {
    @ObservedObject private var social = SocialStore.shared
    @State private var removing: Friend?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let friends = social.allFriends
            Text(verbatim: S("フレンド（\(friends.count)人）", "Friends (\(friends.count))", "친구 (\(friends.count)명)"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            if friends.isEmpty {
                Text(verbatim: S("まだフレンドがいません。招待リンクを送るか、コードを入力しましょう。",
                                 "No friends yet. Send an invite or enter a code."))
                    .font(.caption)
                    .foregroundColor(.dlTextLight)
            }
            ForEach(friends) { friend in
                HStack(spacing: 12) {
                    AvatarView(friend: friend)
                    Text(friend.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                    if friend.isOfficial || friend.isDeveloper { OfficialBadge() }
                    Spacer()
                    Button { removing = friend } label: {
                        Image(systemName: "ellipsis").foregroundColor(.dlTextSub).frame(width: 30, height: 30)
                    }
                }
            }
            // 持ち主：開発者としてフレンドになってくれた人は、多くなるので人数だけ出す
            if social.isOfficialOwner, social.publishesOfficial {
                Divider()
                HStack(spacing: 6) {
                    OfficialBadge()
                    Text(verbatim: S("開発者としてのフレンド \(social.followers.count)人",
                                     "Friends as the developer: \(social.followers.count)",
                                     "개발자로서의 친구 \(social.followers.count)명"))
                        .font(.subheadline)
                        .foregroundColor(.dlText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
        .confirmationDialog(Text(verbatim: removing.map { S("\($0.nickname)さん", $0.nickname, "\($0.nickname)님") } ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { friend in
            if friend.isOfficial {
                Button(S("フレンドをやめる", "Remove Friend"), role: .destructive) { Task { await social.setFollowsOfficial(false) } }
            } else {
                Button(S("フレンドをやめる", "Remove Friend"), role: .destructive) { Task { await social.remove(friend, block: false) } }
                Button(S("ブロックする", "Block"), role: .destructive) { Task { await social.remove(friend, block: true) } }
            }
        } message: { friend in
            Text(verbatim: friend.isOfficial
                 ? S("開発者の曲がタイムラインに流れなくなり、あなたの曲も開発者に届かなくなります。コード「\(SocialStore.officialCode)」でいつでもまたフレンドになれます。",
                     "You'll stop seeing the developer's songs, and yours will no longer reach them. Enter \(SocialStore.officialCode) anytime to be friends again.",
                     "개발자의 곡이 타임라인에 표시되지 않고, 내 곡도 개발자에게 전달되지 않습니다. 코드 \(SocialStore.officialCode)로 언제든 다시 친구가 될 수 있습니다.")
                 : S("フレンドをやめる：お互いの曲が見えなくなります。あなたのフレンドコードは新しくなるので、また申請し合えばフレンドに戻れます。\nブロックする：この人からの申請も届かなくなります。設定の「ブロックしたユーザー」で解除できます。",
                     "Remove: you'll stop seeing each other's songs. Your friend code changes, so you can become friends again by sending a new request.\nBlock: you also won't get requests from them. You can unblock in Settings > Blocked Users.",
                     "친구 끊기: 서로의 곡이 보이지 않게 됩니다. 내 친구 코드가 새로 바뀌므로, 다시 신청하면 친구가 될 수 있습니다.\n차단: 이 사람의 신청도 받지 않습니다. 설정의 '차단한 사용자'에서 해제할 수 있습니다."))
        }
    }

}
