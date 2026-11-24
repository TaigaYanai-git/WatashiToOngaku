import CloudKit
import UserNotifications

/// フレンドの通知が届いたら、合図に入っている暗号化された名前を開いて「〇〇さんが…」に書き換える。
/// 開けないとき（古い版からの合図・鍵がない）は、届いた汎用の文（「フレンドが…」）のまま出す
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        if let note = CKNotification(fromRemoteNotificationDictionary: request.content.userInfo) as? CKQueryNotification,
           let body = PingCrypto.body(tag: note.recordFields?["tag"] as? String,
                                      sealedName: note.recordFields?["nickname"] as? String) {
            content.body = body
        }
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {}
}
