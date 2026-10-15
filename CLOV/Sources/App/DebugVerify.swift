import UIKit
import Supabase

#if DEBUG
/// Exercises the real API layer (the same code CreateFitCheckView and
/// GroupsView call) end-to-end against the live backend, headlessly.
/// Only runs when launched with `--debugVerify` — never on a normal
/// launch. Writes its result to Documents/debug-verify.log.
///
/// Creates its own disposable account via real Supabase Auth signUp
/// rather than depending on whatever session (if any) is active in the
/// interactive UI — keeps this runnable standalone, and doubles as a
/// smoke test of the signup path itself.
enum DebugVerify {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--debugVerify") else { return }
        Task {
            var log = "DEBUG VERIFY START\n"
            do {
                let email = "debug-verify-\(Int.random(in: 100_000...999_999))@example.com"
                let password = "debugVerifyPass123"

                let authResponse = try await SupabaseManager.client.auth.signUp(email: email, password: password)
                guard case .session(let session) = authResponse else {
                    log += "✗ signUp did not return a session — email confirmation is likely required on this project (Authentication > Sign In / Providers > Email > \"Confirm email\"). Can't verify further without a real session.\n"
                    writeLog(log)
                    return
                }
                let uid = session.user.id
                log += "✓ signUp -> uid=\(uid)\n"

                try await API.saveOnboarding(nickname: "debugverify\(Int.random(in: 1000...9999))", styles: ["Streetwear"])
                log += "✓ saveOnboarding succeeded\n"

                let group = try await API.createGroup(name: "DebugGroup-\(Int.random(in: 1000...9999))", creatorId: uid)
                log += "✓ createGroup -> id=\(group.id) code=\(group.inviteCode)\n"

                let isMemberAfterCreate = try await API.isMember(groupId: group.id, profileId: uid)
                log += "✓ isMember after create: \(isMemberAfterCreate)\n"

                let rejoined = try await API.joinGroup(code: group.inviteCode)
                log += "✓ joinGroup (idempotent re-join) -> id=\(rejoined.id)\n"

                let members = try await API.fetchGroupMembers(groupId: group.id)
                log += "✓ fetchGroupMembers -> count=\(members.count)\n"

                let images = [UIColor.systemPink, .systemGreen, .systemBlue].map { makeSolidImage(color: $0) }

                try await API.createFitCheck(creatorId: uid, caption: "debug verify — public post", groupId: nil, votingDuration: 24 * 3600, photos: images)
                log += "✓ createFitCheck (public) succeeded\n"

                try await API.createFitCheck(creatorId: uid, caption: "debug verify — group post", groupId: group.id, votingDuration: 24 * 3600, photos: images)
                log += "✓ createFitCheck (group-scoped) succeeded\n"

                let publicFeed = try await API.fetchFeed()
                log += "✓ fetchFeed -> \(publicFeed.count) public item(s)\n"

                let groupFeed = try await API.fetchGroupFeed(groupId: group.id)
                log += "✓ fetchGroupFeed -> \(groupFeed.count) item(s) in group\n"

                // Bad-code join should fail cleanly, not crash.
                do {
                    _ = try await API.joinGroup(code: "ZZZZZZ")
                    log += "✗ joinGroup with bogus code unexpectedly succeeded\n"
                } catch {
                    log += "✓ joinGroup with bogus code correctly failed: \(error.localizedDescription)\n"
                }

                try await SupabaseManager.client.auth.signOut()
                log += "✓ signOut succeeded\n"

                log += "DEBUG VERIFY SUCCESS\n"
            } catch {
                log += "✗ DEBUG VERIFY FAILED: \(error)\n"
            }
            writeLog(log)
        }
    }

    private static func makeSolidImage(color: UIColor, size: CGSize = CGSize(width: 300, height: 400)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func writeLog(_ text: String) {
        print(text)
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug-verify.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
