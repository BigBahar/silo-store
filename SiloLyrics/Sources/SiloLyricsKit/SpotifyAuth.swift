import Foundation
import CryptoKit

/// Spotify Authorization Code flow with PKCE. No client secret is needed or stored.
public struct SpotifyAuthConfig: Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public init(clientID: String, redirectURI: String = "silolyrics://callback",
                scopes: [String] = ["user-read-currently-playing", "user-read-playback-state"]) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public var isConfigured: Bool { !clientID.isEmpty && !clientID.hasPrefix("YOUR_") }
}

public struct PKCEPair: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public static func make() -> PKCEPair {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        let verifier = String((0..<96).map { _ in alphabet.randomElement(using: &rng)! })
        return PKCEPair(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct SpotifyTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public func isExpired(at now: Date = Date()) -> Bool { now >= expiresAt.addingTimeInterval(-60) }
}

public enum SpotifyAuthError: Error, Equatable {
    case notConfigured, stateMismatch, missingCode, denied(String), http(Int)
}

public struct SpotifyAuth: Sendable {
    public let config: SpotifyAuthConfig
    private let session: URLSession

    public init(config: SpotifyAuthConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func authorizeURL(pkce: PKCEPair, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    /// Extracts the authorization code from the redirect, checking `state`.
    public func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        if let err = value("error") { throw SpotifyAuthError.denied(err) }
        guard value("state") == expectedState else { throw SpotifyAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw SpotifyAuthError.missingCode }
        return code
    }

    public func exchange(code: String, verifier: String) async throws -> SpotifyTokens {
        try await token(form: [
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": config.redirectURI, "client_id": config.clientID,
            "code_verifier": verifier,
        ], fallbackRefresh: nil)
    }

    public func refresh(_ tokens: SpotifyTokens) async throws -> SpotifyTokens {
        try await token(form: [
            "grant_type": "refresh_token", "refresh_token": tokens.refreshToken,
            "client_id": config.clientID,
        ], fallbackRefresh: tokens.refreshToken)
    }

    private func token(form: [String: String], fallbackRefresh: String?) async throws -> SpotifyTokens {
        guard config.isConfigured else { throw SpotifyAuthError.notConfigured }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SpotifyAuthError.http(status) }
        struct Body: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let b = try JSONDecoder().decode(Body.self, from: data)
        guard let refresh = b.refresh_token ?? fallbackRefresh else { throw SpotifyAuthError.missingCode }
        return SpotifyTokens(accessToken: b.access_token, refreshToken: refresh,
                             expiresAt: Date().addingTimeInterval(b.expires_in))
    }
}
