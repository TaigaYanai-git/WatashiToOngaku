import SwiftUI

/// ブロックしたユーザーの一覧と、ブロックの解除
struct BlockedUsersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @State private var unblocking: PendingFriend?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if social.blockedUsers.isEmpty {
                        Text(verbatim: S("ブロックしたユーザーはいません", "You haven't blocked anyone"))
                            .font(.subheadline)
                            .foregroundColor(.dlTextSub)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    ForEach(social.blockedUsers) { user in
                        HStack(spacing: 12) {
                            AvatarView(code: user.code, version: 0, nickname: user.nickname)
                            Text(user.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                            Spacer()
                            Button(S("解除", "Unblock")) { unblocking = user }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.dlPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dlCard()
                .padding(20)

                Text(verbatim: S("ブロックした人には、あなたの投稿は見えません。また、その人からのフレンド申請は届きません。解除してもフレンドには戻らないので、フレンドになるにはもう一度申請してください。",
                                 "Blocked people can't see your posts or send you requests. Unblocking doesn't make you friends again; send a new request to reconnect."))
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                    .padding(.horizontal, 24)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("ブロックしたユーザー", "Blocked Users")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .confirmationDialog(Text(verbatim: unblocking.map { S("\($0.nickname)さんのブロックを解除しますか？", "Unblock \($0.nickname)?") } ?? ""),
                                isPresented: Binding(get: { unblocking != nil }, set: { if !$0 { unblocking = nil } }),
                                titleVisibility: .visible, presenting: unblocking) { user in
                Button(S("ブロックを解除", "Unblock")) { social.unblock(user) }
            }
        }
    }
}
