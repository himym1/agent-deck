import AppKit
import Foundation

/// Drives the MCP OAuth 2.0 journey for a remote server: discover the authorization
/// server (RFC 9728 + RFC 8414), dynamically register a client (RFC 7591), run the
/// PKCE authorization-code flow through the system browser + a loopback redirect, and
/// exchange/refresh tokens. Tokens are persisted by `MCPAuthStore`.
nonisolated final class MCPOAuthService: Sendable {
    static let shared = MCPOAuthService()

    private let session: URLSession
    private let store: MCPAuthStore
    private let openURL: @Sendable (URL) -> Void

    init(session: URLSession = .shared,
         store: MCPAuthStore = .shared,
         openURL: @escaping @Sendable (URL) -> Void = { url in Task { @MainActor in NSWorkspace.shared.open(url) } }) {
        self.session = session
        self.store = store
        self.openURL = openURL
    }

    // MARK: - Public journey

    /// Runs the full Connect flow for `serverName` at `serverURLString` and stores tokens.
    func connect(serverName: String, serverURLString: String) async throws {
        guard let serverURL = URL(string: serverURLString) else {
            throw MCPError.transportFailed("invalid server URL")
        }
        var auth = await store.auth(for: serverName) ?? MCPServerAuth()

        if auth.authorizationEndpoint == nil || auth.tokenEndpoint == nil {
            let discovered = try await discover(serverURL: serverURL)
            auth.authorizationEndpoint = discovered.authorizationEndpoint
            auth.tokenEndpoint = discovered.tokenEndpoint
            auth.registrationEndpoint = discovered.registrationEndpoint
            auth.scope = auth.scope ?? discovered.scope
        }
        auth.resource = serverURL.absoluteString

        guard let authEndpoint = auth.authorizationEndpoint.flatMap(URL.init(string:)),
              let tokenEndpoint = auth.tokenEndpoint.flatMap(URL.init(string:)) else {
            throw MCPError.transportFailed("server did not advertise OAuth endpoints")
        }

        let loopback = try MCPLoopbackServer()
        let port = try await loopback.start()
        defer { loopback.stop() }
        let redirectURI = "http://127.0.0.1:\(port)/callback"

        if auth.clientID == nil {
            guard let registrationEndpoint = auth.registrationEndpoint.flatMap(URL.init(string:)) else {
                throw MCPError.transportFailed("server requires a pre-registered client (no dynamic registration endpoint)")
            }
            let registration = try await registerClient(registrationEndpoint, redirectURI: redirectURI)
            auth.clientID = registration.client_id
            auth.clientSecret = registration.client_secret
        }

        let pkce = MCPPKCE()
        let state = UUID().uuidString

        guard var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false) else {
            throw MCPError.transportFailed("invalid authorization endpoint")
        }
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: auth.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: serverURL.absoluteString) // RFC 8707
        ]
        if let scope = auth.scope, !scope.isEmpty { items.append(URLQueryItem(name: "scope", value: scope)) }
        components.queryItems = (components.queryItems ?? []) + items
        guard let authURL = components.url else { throw MCPError.transportFailed("could not build authorization URL") }

        openURL(authURL)
        let params = try await loopback.waitForCallback()
        if let error = params["error"] {
            throw MCPError.transportFailed("authorization denied: \(error)")
        }
        guard params["state"] == state else { throw MCPError.transportFailed("OAuth state mismatch") }
        guard let code = params["code"], !code.isEmpty else { throw MCPError.transportFailed("no authorization code returned") }

        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": auth.clientID ?? "",
            "code_verifier": pkce.verifier,
            "resource": serverURL.absoluteString
        ]
        if let secret = auth.clientSecret { fields["client_secret"] = secret }
        let response = try await postForm(tokenEndpoint, fields: fields, as: MCPTokenResponse.self)
        auth.tokens = response.tokens(now: Date())
        auth.scope = response.scope ?? auth.scope
        await store.setAuth(auth, for: serverName)
    }

    /// Drops stored tokens (keeps the registered client + endpoints for a fast reconnect).
    func disconnect(serverName: String) async {
        guard var auth = await store.auth(for: serverName) else { return }
        auth.tokens = nil
        await store.setAuth(auth, for: serverName)
    }

    /// A usable access token, refreshing if the stored one is expired. Nil when the
    /// server isn't connected (caller surfaces "Connect").
    func accessToken(for serverName: String) async -> String? {
        if let valid = await store.validAccessToken(for: serverName) { return valid }
        return try? await refresh(serverName: serverName)
    }

    /// Refreshes tokens using the stored refresh token. Returns the new access token.
    @discardableResult
    func refresh(serverName: String) async throws -> String? {
        guard var auth = await store.auth(for: serverName),
              let tokenEndpoint = auth.tokenEndpoint.flatMap(URL.init(string:)),
              let refreshToken = auth.tokens?.refreshToken else { return nil }
        var fields = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": auth.clientID ?? ""]
        if let secret = auth.clientSecret { fields["client_secret"] = secret }
        if let scope = auth.scope { fields["scope"] = scope }
        let response = try await postForm(tokenEndpoint, fields: fields, as: MCPTokenResponse.self)
        var tokens = response.tokens(now: Date())
        if tokens.refreshToken == nil { tokens.refreshToken = refreshToken } // reuse when not rotated
        auth.tokens = tokens
        await store.setAuth(auth, for: serverName)
        return tokens.accessToken
    }

    // MARK: - Discovery

    func discover(serverURL: URL) async throws -> MCPServerAuth {
        var auth = MCPServerAuth()
        auth.resource = serverURL.absoluteString
        let origin = Self.originURL(serverURL)

        if let metadata: MCPProtectedResourceMetadata = try? await getJSON(origin.appendingPathComponent(".well-known/oauth-protected-resource")),
           let authServer = metadata.authorization_servers?.first, let authServerURL = URL(string: authServer) {
            apply(try await fetchAuthServerMetadata(authServerURL), to: &auth)
        } else {
            // Fallback: treat the resource origin as the authorization server.
            apply(try await fetchAuthServerMetadata(origin), to: &auth)
        }
        return auth
    }

    private func fetchAuthServerMetadata(_ base: URL) async throws -> MCPAuthServerMetadata {
        if let metadata: MCPAuthServerMetadata = try? await getJSON(base.appendingPathComponent(".well-known/oauth-authorization-server")) {
            return metadata
        }
        return try await getJSON(base.appendingPathComponent(".well-known/openid-configuration"))
    }

    private func apply(_ metadata: MCPAuthServerMetadata, to auth: inout MCPServerAuth) {
        auth.authorizationEndpoint = metadata.authorization_endpoint
        auth.tokenEndpoint = metadata.token_endpoint
        auth.registrationEndpoint = metadata.registration_endpoint
        if auth.scope == nil { auth.scope = metadata.scopes_supported?.joined(separator: " ") }
    }

    private func registerClient(_ endpoint: URL, redirectURI: String) async throws -> MCPClientRegistrationResponse {
        let body: [String: Any] = [
            "client_name": "Agent Deck",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ]
        return try await postJSON(endpoint, body: body)
    }

    // MARK: - HTTP helpers

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postForm<T: Decodable>(_ url: URL, fields: [String: String], as type: T.Type = T.self) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(_ url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func ensureOK(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MCPError.transportFailed("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPError.transportFailed("HTTP \(http.statusCode): \(String(decoding: data, as: UTF8.self).prefix(200))")
        }
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    static func originURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }
}
