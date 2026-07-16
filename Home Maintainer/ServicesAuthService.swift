//
//  AuthService.swift
//  Home Maintainer
//

import Foundation
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

// MARK: - Subscription Data Model

struct UserSubscriptionData {
    let tier: String
    let monthlyTokensUsed: Int
    let tierLimit: Int
    let tierResetDate: Date

    var usagePercentage: Double {
        guard tierLimit > 0 else { return 0 }
        return min(1.0, Double(monthlyTokensUsed) / Double(tierLimit))
    }

    var isAtLimit: Bool { monthlyTokensUsed >= tierLimit }
    var tierDisplayName: String { tier.capitalized }

    // Must match TIER_LIMITS in Cloud Function index.ts
    static let tierLimits: [String: Int] = [
        "free": 100_000,
        "standard": 1_000_000,
        "pro": 5_000_000,
    ]

    static let free = UserSubscriptionData(
        tier: "free",
        monthlyTokensUsed: 0,
        tierLimit: tierLimits["free"]!,
        tierResetDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    )
}

// MARK: - Auth Service

@Observable
class AuthService {
    var currentUser: FirebaseAuth.User?
    var isLoading = false
    var errorMessage: String?
    var subscriptionData: UserSubscriptionData = .free

    var isSignedIn: Bool { currentUser != nil }
    var displayName: String {
        currentUser?.displayName ?? currentUser?.email ?? "User"
    }

    private var stateListenerHandle: AuthStateDidChangeListenerHandle?
    private var subscriptionListener: ListenerRegistration?

    init() {
        // iOS Keychain data survives app deletion and device backups, so a stale
        // Firebase token can exist on a fresh install and let the user past the
        // sign-in screen with an invalid session. Force sign-out once per fresh
        // install (UserDefaults is cleared on reinstall; Keychain is not).
        if !UserDefaults.standard.bool(forKey: "hasCompletedSignIn") {
            try? Auth.auth().signOut()
        }
        currentUser = Auth.auth().currentUser
        if let user = currentUser {
            startSubscriptionListener(for: user)
        }
        stateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                if let user {
                    self?.startSubscriptionListener(for: user)
                } else {
                    self?.subscriptionListener?.remove()
                    self?.subscriptionListener = nil
                    self?.subscriptionData = .free
                }
            }
        }
    }

    deinit {
        if let handle = stateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        subscriptionListener?.remove()
    }

    // MARK: - Public API

    /// Called by SignInView to configure the Apple ID request (sets nonce).
    /// Returns the raw nonce so it can be passed to handleSignInResult.
    func prepareSignInRequest(_ request: ASAuthorizationAppleIDRequest) -> String {
        let nonce = randomNonceString()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return nonce
    }

    /// Called by SignInView with the result from SignInWithAppleButton.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>, nonce: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in isLoading = false }
        }

        switch result {
        case .failure(let error):
            // Ignore user cancellation
            if (error as? ASAuthorizationError)?.code != .canceled {
                await MainActor.run { errorMessage = error.localizedDescription }
            }

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                await MainActor.run { errorMessage = "Invalid Apple ID credential." }
                return
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            do {
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                UserDefaults.standard.set(true, forKey: "hasCompletedSignIn")
                await createUserRecordIfNeeded(for: result.user)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Firestore User Record

    private func createUserRecordIfNeeded(for user: FirebaseAuth.User) async {
        let db = Firestore.firestore()
        let ref = db.collection("users").document(user.uid)

        do {
            let snapshot = try await ref.getDocument()
            guard !snapshot.exists else { return }

            let now = Date()
            let resetDate = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now

            try await ref.setData([
                "uid": user.uid,
                "displayName": user.displayName ?? "",
                "tier": "free",
                "monthlyTokensUsed": 0,
                "tierResetDate": Timestamp(date: resetDate),
                "createdAt": Timestamp(date: now),
            ])
        } catch {
            // Non-fatal — user can still use the app
            print("[AuthService] Could not create user record: \(error)")
        }
    }

    // MARK: - Subscription Listener

    private func startSubscriptionListener(for user: FirebaseAuth.User) {
        subscriptionListener?.remove()
        let db = Firestore.firestore()
        subscriptionListener = db.collection("users").document(user.uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data() else { return }
                let tier = data["tier"] as? String ?? "free"
                let used = data["monthlyTokensUsed"] as? Int ?? 0
                let limit = UserSubscriptionData.tierLimits[tier] ?? UserSubscriptionData.tierLimits["free"]!
                let resetDate = (data["tierResetDate"] as? Timestamp)?.dateValue() ?? Date()

                Task { @MainActor in
                    self?.subscriptionData = UserSubscriptionData(
                        tier: tier,
                        monthlyTokensUsed: used,
                        tierLimit: limit,
                        tierResetDate: resetDate
                    )
                }
            }
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) == errSecSuccess else { continue }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
