import Foundation
import ToriCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Nonce and PKCE helpers for the sign-in adapters (doc 36 §12.1, §12.2; RFC 7636).
public enum AuthCrypto {
    /// 32 random bytes, base64url without padding.
    public static func randomToken() -> String {
        var rng = SystemRandomNumberGenerator()
        return base64URL((0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) })
    }

    /// Apple `request.nonce`: lowercase hex SHA-256 of the raw nonce.
    public static func appleNonceHash(_ rawNonce: String) -> String { sha256Hex(Data(rawNonce.utf8)) }

    /// PKCE S256: base64url(SHA-256(verifier)).
    public static func pkceChallenge(_ verifier: String) -> String { base64URL(sha256(Data(verifier.utf8))) }

    public static func base64URL(_ bytes: some Sequence<UInt8>) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Google OAuth without the SDK (§12.2 alternative): authorization code + PKCE + nonce, code exchanged for the ID token.
public struct GoogleOAuthConfig: Sendable, Equatable {
    /// iOS OAuth client ID (public identifier, build configuration).
    public var clientID: String
    /// The reversed client ID scheme registered for the iOS client, e.g. `com.googleusercontent.apps.123`.
    public var redirectScheme: String

    public init(clientID: String, redirectScheme: String) {
        self.clientID = clientID
        self.redirectScheme = redirectScheme
    }

    public var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    public func authorizationURL(state: String, nonce: String, codeChallenge: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid"),
            .init(name: "state", value: state), .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: codeChallenge), .init(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }

    /// The `code` of the redirect, after checking `state`; nil on mismatch, error or cancel.
    public func code(fromRedirect url: URL, expectedState: String) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard value("state") == expectedState, value("error") == nil else { return nil }
        return value("code")
    }

    /// Token endpoint request body (public client: no secret).
    public func tokenRequestBody(code: String, verifier: String) -> Data {
        var c = URLComponents()
        c.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_verifier", value: verifier),
        ]
        return Data((c.percentEncodedQuery ?? "").utf8)
    }
}

public enum SignInError: Error, Equatable, Sendable {
    case cancelled
    case failed
}

#if canImport(AuthenticationServices) && !os(watchOS)
/// Sign in with Apple (§12.1): no scopes, hashed nonce; yields the E1 credential.
@MainActor
public final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<SignInCredential, any Error>?
    private var rawNonce = ""

    public override init() {}

    /// For `SignInWithAppleButton(onRequest:)`: configures the request and remembers the raw nonce.
    public func prepare(_ request: ASAuthorizationAppleIDRequest) {
        rawNonce = AuthCrypto.randomToken()
        request.requestedScopes = []
        request.nonce = AuthCrypto.appleNonceHash(rawNonce)
    }

    /// For `SignInWithAppleButton(onCompletion:)`.
    public func credential(from result: Result<ASAuthorization, any Error>) throws -> SignInCredential {
        switch result {
        case .success(let auth):
            guard let c = auth.credential as? ASAuthorizationAppleIDCredential,
                  let token = c.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                  let code = c.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else { throw SignInError.failed }
            return .apple(identityToken: token, authorizationCode: code, rawNonce: rawNonce)
        case .failure(let e):
            throw (e as? ASAuthorizationError)?.code == .canceled ? SignInError.cancelled : SignInError.failed
        }
    }

    /// Programmatic flow (no SwiftUI button).
    public func signIn() async throws -> SignInCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepare(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        return try await withCheckedThrowingContinuation { c in
            continuation = c
            controller.performRequests()
        }
    }

    public nonisolated func authorizationController(controller: ASAuthorizationController,
                                                    didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    public nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        continuation?.resume(with: Result { try credential(from: result) })
        continuation = nil
    }
}

/// Google sign-in through `ASWebAuthenticationSession` + PKCE + nonce; yields the E5 credential.
@MainActor
public final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    let config: GoogleOAuthConfig
    let anchor: @MainActor () -> ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    public init(config: GoogleOAuthConfig, anchor: @escaping @MainActor () -> ASPresentationAnchor) {
        self.config = config
        self.anchor = anchor
    }

    public func signIn() async throws -> SignInCredential {
        let verifier = AuthCrypto.randomToken(), state = AuthCrypto.randomToken(), nonce = AuthCrypto.randomToken()
        let url = config.authorizationURL(state: state, nonce: nonce, codeChallenge: AuthCrypto.pkceChallenge(verifier))
        let redirect: URL = try await withCheckedThrowingContinuation { c in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: config.redirectScheme) { url, error in
                if let url { c.resume(returning: url) } else {
                    c.resume(throwing: (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                             ? SignInError.cancelled : SignInError.failed)
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = true
            session = s
            s.start()
        }
        guard let code = config.code(fromRedirect: redirect, expectedState: state) else { throw SignInError.failed }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = config.tokenRequestBody(code: code, verifier: verifier)
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Token: Decodable { var id_token: String }
        guard let token = try? JSONDecoder().decode(Token.self, from: data) else { throw SignInError.failed }
        // Google's access token is dropped (§12.2).
        return .google(idToken: token.id_token, nonce: nonce)
    }

    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor() }
    }
}
#endif
