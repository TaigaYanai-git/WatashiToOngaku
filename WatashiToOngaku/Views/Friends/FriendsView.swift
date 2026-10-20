import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// フレンドの追加（招待リンク・QRコード・フレンドコード）と一覧
struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @State private var codeInput = ""
    @State private var showScanner = false
    @State private var showMyQR = false
    @State private var message: String?
    @State private var removing: Friend?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    myCard
                    addCard
                    friendList
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
                    Task { await add { await social.addFriend(shareURL: url) } }
                }
            }
            .sheet(isPresented: $showMyQR) { MyQRSheet() }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
            .confirmationDialog(Text(verbatim: removing.map { S("\($0.nickname)さん", $0.nickname) } ?? ""),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { friend in
                Button(S("フレンドをやめる", "Remove Friend"), role: .destructive) { Task { await social.remove(friend, block: false) } }
                Button(S("ブロックする", "Block"), role: .destructive) { Task { await social.remove(friend, block: true) } }
            } message: { _ in
                Text(verbatim: S("お互いの曲が見えなくなります。ブロックすると、もう一度フレンドになることもできなくなります。",
                                 "You'll stop seeing each other's songs. Blocking also prevents becoming friends again."))
            }
        }
    }

    private var myCard: some View {
        VStack(spacing: 12) {
            Text(verbatim: S("あなたのフレンドコード", "Your Friend Code"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.dlTextSub)
            Text(social.friendCode.isEmpty ? "--------" : social.friendCode)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(.dlText)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                if let url = social.shareURL {
                    ShareLink(item: url,
                              subject: Text(verbatim: S("私と音楽", "Me & Music")),
                              message: Text(verbatim: S("「私と音楽」でフレンドになろう！フレンドコード：\(social.friendCode)",
                                                        "Be my friend on Me & Music! Code: \(social.friendCode)"))) {
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
            Text(verbatim: S("フレンドを追加", "Add a Friend"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            HStack(spacing: 10) {
                TextField(S("フレンドコード（8文字）", "Friend code (8 characters)"), text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(DarkTextFieldStyle())
                Button(S("追加", "Add")) {
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

    private var friendList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: S("フレンド（\(social.friends.count)人）", "Friends (\(social.friends.count))"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            if social.friends.isEmpty {
                Text(verbatim: S("まだフレンドがいません。招待リンクを送るか、コードを入力しましょう。",
                                 "No friends yet. Send an invite or enter a code."))
                    .font(.caption)
                    .foregroundColor(.dlTextLight)
            }
            ForEach(social.friends) { friend in
                HStack(spacing: 12) {
                    Text(String(friend.nickname.prefix(1)))
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(LinearGradient.dlPrimary).clipShape(Circle())
                    Text(friend.nickname).font(.subheadline).foregroundColor(.dlText)
                    Spacer()
                    Button { removing = friend } label: {
                        Image(systemName: "ellipsis").foregroundColor(.dlTextSub).frame(width: 30, height: 30)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func add(_ action: () async -> Bool) async {
        if await action() {
            codeInput = ""
            message = S("フレンドになりました！", "You're now friends!")
        } else {
            message = social.lastError ?? S("追加できませんでした", "Couldn't add friend")
        }
    }
}

/// 自分の招待リンクの QR コード
private struct MyQRSheet: View {
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text(verbatim: S("このQRコードを読み取ってもらうと、フレンドになれます", "Have a friend scan this code"))
                .font(.subheadline).foregroundColor(.dlTextSub).multilineTextAlignment(.center)
            if let url = social.shareURL, let image = Self.qrImage(url.absoluteString) {
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
                      url.scheme == "https" else { continue }
                done = true
                scanner.stopScanning()
                onFound(url)
            }
        }
    }
}
