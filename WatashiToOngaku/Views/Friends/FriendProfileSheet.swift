import SwiftUI

/// タイムラインでフレンドのアイコンを押したときのプロフィール。その人のフレンドの一覧から、まだフレンドでない人に申請できる
struct FriendProfileSheet: View {
    let friend: Friend
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var working: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                // その人のフレンドの一覧は、表示のたびに1回だけ組み立てる
                let entries = social.friendsOf(friend)
                VStack(spacing: 18) {
                    header(entries)
                    friendList(entries)
                }
                .padding(20)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: friend.nickname))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func header(_ entries: [SocialStore.FriendOfFriendEntry]?) -> some View {
        let mutualCount = (entries ?? []).filter { if case .friend = $0 { return true } else { return false } }.count
        return VStack(spacing: 8) {
            AvatarView(friend: friend, size: 84)
            Text(verbatim: friend.nickname).font(.title3.weight(.bold)).foregroundColor(.dlText).lineLimit(1)
            if let entries {
                Text(verbatim: S("フレンド \(entries.count)人 ・ 共通 \(mutualCount)人",
                                 "\(entries.count) friends · \(mutualCount) mutual",
                                 "친구 \(entries.count)명 · 함께 아는 친구 \(mutualCount)명"))
                    .font(.subheadline)
                    .foregroundColor(.dlTextSub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func friendList(_ entries: [SocialStore.FriendOfFriendEntry]?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: S("\(friend.nickname)さんのフレンド", "\(friend.nickname)'s Friends", "\(friend.nickname)님의 친구"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            if let entries {
                if entries.isEmpty {
                    note(S("ほかに表示できるフレンドはいません", "No other friends to show", "표시할 다른 친구가 없습니다"))
                }
                ForEach(entries) { entry in row(entry) }
            } else {
                note(S("\(friend.nickname)さんのフレンドはまだ表示できません。\(friend.nickname)さんが新しいバージョンの Our Music を開くと表示されます。",
                       "\(friend.nickname)'s friends will appear after they open the latest version of Our Music.",
                       "\(friend.nickname)님이 최신 버전의 Our Music을 열면 친구 목록이 표시됩니다."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundColor(.dlTextLight)
    }

    @ViewBuilder
    private func row(_ entry: SocialStore.FriendOfFriendEntry) -> some View {
        switch entry {
        case .me:
            HStack(spacing: 12) {
                AvatarView(code: social.friendCode, version: social.avatarVersion, nickname: social.nickname)
                Text(verbatim: social.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                Spacer(minLength: 0)
                label(S("あなた", "You", "나"))
            }
        case .friend(let mutual):
            HStack(spacing: 12) {
                AvatarView(friend: mutual)
                Text(verbatim: mutual.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                Spacer(minLength: 0)
                label(S("フレンド", "Friend", "친구"))
            }
        case .other(let person):
            HStack(spacing: 12) {
                AvatarView(code: person.code, version: person.avatarVersion, nickname: person.nickname)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: person.nickname).font(.subheadline).foregroundColor(.dlText).lineLimit(1)
                    // 共通のフレンドがほかにもいれば添える
                    let others = person.via.filter { $0 != friend.nickname }
                    if !others.isEmpty {
                        Text(verbatim: S("\(others.joined(separator: "、"))さんともフレンド", "Also friends with \(others.joined(separator: ", "))",
                                         "\(others.joined(separator: ", "))님과도 친구"))
                            .font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                requestButton(person)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.dlTextSub)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.dlPrimaryBg))
    }

    @ViewBuilder
    private func requestButton(_ person: FriendSuggestion) -> some View {
        switch social.status(of: person) {
        case .requested:
            label(S("申請済み", "Requested", "신청함"))
        case .canRequest, .incoming:
            let incoming = social.status(of: person) == .incoming
            Button {
                working = person.code
                Task {
                    let result = await social.addFriend(code: person.code)
                    working = nil
                    message = result.map(SocialStore.message(for:)) ?? (social.lastError ?? S("申請できませんでした", "Couldn't send the request"))
                }
            } label: {
                Group {
                    if working == person.code {
                        ProgressView().tint(.white)
                    } else {
                        Text(verbatim: incoming ? S("承認", "Accept") : S("申請", "Request"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(LinearGradient.dlPrimary))
            }
            .disabled(working != nil)
        }
    }
}

/// コメント欄でフレンドでない人（投稿した人のフレンド）のアイコンを押したときのプロフィール。
/// その人のフレンドの一覧は読めない（フレンドの鍵がない）ので、名前と申請ボタンだけ
struct CommenterProfileSheet: View {
    let person: FriendSuggestion
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                AvatarView(code: person.code, version: person.avatarVersion, nickname: person.nickname, size: 84)
                Text(verbatim: person.nickname).font(.title3.weight(.bold)).foregroundColor(.dlText).lineLimit(1)
                if !person.via.isEmpty {
                    Text(verbatim: S("\(person.via.joined(separator: "、"))さんのフレンド", "Friends with \(person.via.joined(separator: ", "))",
                                     "\(person.via.joined(separator: ", "))님의 친구"))
                        .font(.subheadline).foregroundColor(.dlTextSub).lineLimit(2)
                }
                requestButton.padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: person.nickname))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var requestButton: some View {
        if social.blocked.contains(person.code) {
            EmptyView()
        } else if social.status(of: person) == .requested {
            Text(verbatim: S("申請済み", "Requested", "신청함"))
                .font(.subheadline.weight(.semibold)).foregroundColor(.dlTextSub)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.dlCardTint))
        } else {
            let incoming = social.status(of: person) == .incoming
            Button {
                working = true
                Task {
                    let result = await social.addFriend(code: person.code)
                    working = false
                    message = result.map(SocialStore.message(for:)) ?? (social.lastError ?? S("申請できませんでした", "Couldn't send the request"))
                }
            } label: {
                Group {
                    if working { ProgressView().tint(.white) }
                    else { Text(verbatim: incoming ? S("フレンド申請を承認", "Accept request", "친구 신청 수락") : S("フレンド申請", "Send friend request", "친구 신청")) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(LinearGradient.dlPrimary))
            }
            .disabled(working)
        }
    }
}
