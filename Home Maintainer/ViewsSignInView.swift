//
//  SignInView.swift
//  Home Maintainer
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    @State private var currentNonce = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Branding
            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("Home Maintainer")
                    .font(.largeTitle.bold())

                Text("Your AI-powered home management assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Sign in area
            VStack(spacing: 16) {
                if authService.isLoading {
                    ProgressView("Signing in...")
                        .frame(height: 50)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        currentNonce = authService.prepareSignInRequest(request)
                    } onCompletion: { result in
                        Task {
                            await authService.handleSignInResult(result, nonce: currentNonce)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)
                }

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Your data is stored privately in iCloud and is never shared.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthService())
}
