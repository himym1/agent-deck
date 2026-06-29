import Foundation

struct GitHubIssueService {
    private let apiClient: GitHubAPIClient

    init(apiClient: GitHubAPIClient) {
        self.apiClient = apiClient
    }

    func fetchDetail(for item: GitHubWorkItem, bypassCache: Bool = false) async throws -> GitHubIssueDetail {
        let repo = try parseRepository(item.repository)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        async let issueTask = apiClient.get(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)",
            queryItems: [],
            bypassCache: bypassCache
        )
        async let commentsTask = apiClient.get(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/comments",
            queryItems: [],
            bypassCache: bypassCache
        )
        async let parentTask: GitHubIssueReference? = fetchOptionalReference(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/parent",
            decoder: decoder,
            bypassCache: bypassCache
        )
        async let subIssuesTask = fetchReferences(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/sub_issues",
            decoder: decoder,
            bypassCache: bypassCache
        )
        async let blockedByTask = fetchReferences(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/dependencies/blocked_by",
            decoder: decoder,
            bypassCache: bypassCache
        )
        async let blockingTask = fetchReferences(
            path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/dependencies/blocking",
            decoder: decoder,
            bypassCache: bypassCache
        )

        let (issueData, _) = try await issueTask
        let issue = try decoder.decode(GitHubIssuePayload.self, from: issueData)

        let (commentsData, _) = try await commentsTask
        let comments = try decoder.decode([GitHubCommentPayload].self, from: commentsData)

        return GitHubIssueDetail(
            item: item,
            body: issue.body ?? "",
            state: issue.state,
            stateReason: issue.stateReason,
            type: issue.type?.name,
            author: issue.user?.login,
            assignees: issue.assignees.map(\.login),
            labels: issue.labels.map { GitHubLabel(name: $0.name, color: $0.color) },
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            closedAt: issue.closedAt,
            parent: try await parentTask,
            subIssues: try await subIssuesTask,
            blockedBy: try await blockedByTask,
            blocking: try await blockingTask,
            comments: comments.map {
                GitHubIssueComment(
                    id: $0.id,
                    author: $0.user.login,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    url: $0.htmlURL
                )
            }
        )
    }

    func postComment(body: String, for item: GitHubWorkItem) async throws {
        let repo = try parseRepository(item.repository)
        let payload = try JSONEncoder().encode(["body": body])
        _ = try await apiClient.post(path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)/comments", body: payload)
    }

    func closeIssue(_ item: GitHubWorkItem, reason: GitHubIssueCloseReason = .completed) async throws {
        let repo = try parseRepository(item.repository)
        let payload = try JSONEncoder().encode(["state": "closed", "state_reason": reason.rawValue])
        do {
            _ = try await apiClient.patch(path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)", body: payload)
        } catch let error as GitHubAPIClient.APIError {
            if case .requestFailed = error {
                let fallback = try JSONEncoder().encode(["state": "closed"])
                _ = try await apiClient.patch(path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)", body: fallback)
                return
            }
            throw error
        }
    }

    func reopenIssue(_ item: GitHubWorkItem) async throws {
        let repo = try parseRepository(item.repository)
        let payload = try JSONEncoder().encode(["state": "open"])
        _ = try await apiClient.patch(path: "/repos/\(repo.owner)/\(repo.name)/issues/\(item.number)", body: payload)
    }

    private func fetchReferences(path: String, decoder: JSONDecoder, bypassCache: Bool) async throws -> [GitHubIssueReference] {
        let (data, _) = try await apiClient.get(path: path, queryItems: [], bypassCache: bypassCache)
        let payload = try decoder.decode([GitHubIssueRelationshipPayload].self, from: data)
        return payload.map(relationshipReference(from:))
    }

    private func fetchOptionalReference(path: String, decoder: JSONDecoder, bypassCache: Bool) async throws -> GitHubIssueReference? {
        do {
            let (data, _) = try await apiClient.get(path: path, queryItems: [], bypassCache: bypassCache)
            let payload = try decoder.decode(GitHubIssueRelationshipPayload.self, from: data)
            return relationshipReference(from: payload)
        } catch let error as GitHubAPIClient.APIError {
            if case let .requestFailed(statusCode, _) = error, statusCode == 404 {
                return nil
            }
            throw error
        }
    }

    private func relationshipReference(from payload: GitHubIssueRelationshipPayload) -> GitHubIssueReference {
        GitHubIssueReference(
            id: payload.id,
            number: payload.number,
            title: payload.title,
            repository: payload.repositoryName,
            url: payload.htmlURL,
            state: payload.state,
            type: payload.type?.name
        )
    }

    private func parseRepository(_ value: String) throws -> (owner: String, name: String) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw GitHubAPIClient.APIError.requestFailed(statusCode: 0, message: "Invalid repository identifier: \(value)")
        }
        return (parts[0], parts[1])
    }
}

private struct GitHubIssuePayload: Decodable {
    struct User: Decodable { let login: String }
    struct Label: Decodable {
        let name: String
        let color: String?
    }
    struct TypeInfo: Decodable { let name: String }

    let state: String
    let stateReason: String?
    let type: TypeInfo?
    let body: String?
    let user: User?
    let assignees: [User]
    let labels: [Label]
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case state
        case stateReason = "state_reason"
        case type
        case body
        case user
        case assignees
        case labels
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
    }
}

private struct GitHubIssueRelationshipPayload: Decodable {
    struct TypeInfo: Decodable { let name: String }

    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let repositoryURL: String
    let state: String
    let type: TypeInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
        case state
        case type
    }

    var repositoryName: String {
        repositoryURL.replacingOccurrences(of: "https://api.github.com/repos/", with: "")
    }
}

private struct GitHubCommentPayload: Decodable {
    struct User: Decodable { let login: String }

    let id: Int
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL
    let user: User

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
        case user
    }
}

struct GiteaIssueService {
    enum GiteaError: LocalizedError {
        case missingToken(host: String)
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case let .missingToken(host):
                return "Set GITEA_TOKEN or GITEA_TOKEN_\(Self.tokenSuffix(for: host)) in Agent Deck's environment to browse Gitea issues for \(host)."
            case .invalidResponse:
                return "Gitea returned an invalid response."
            case let .requestFailed(statusCode, message):
                return message.isEmpty ? "Gitea request failed with status \(statusCode)." : "Gitea request failed with status \(statusCode): \(message)"
            }
        }

        private static func tokenSuffix(for host: String) -> String {
            host.uppercased().map { character in
                character.isLetter || character.isNumber ? character : "_"
            }.map(String.init).joined()
        }
    }

    private let remote: GitHubRemote
    private let token: String
    private var urlSession: URLSession = .shared

    init(remote: GitHubRemote, environment: [String: String]) throws {
        self.remote = remote
        guard let token = Self.token(for: remote.host, environment: environment) else {
            throw GiteaError.missingToken(host: remote.host)
        }
        self.token = token
    }

    func fetchRepositoryIssues(
        state: GitHubIssueStateFilter,
        bypassCache: Bool = false
    ) async throws -> GitHubBoardSnapshot {
        let stateValue: String?
        switch state {
        case .open: stateValue = "open"
        case .closed: stateValue = "closed"
        case .all: stateValue = nil
        }

        let queryItems = [
            stateValue.map { URLQueryItem(name: "state", value: $0) },
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "page", value: "1")
        ].compactMap { $0 }

        let (data, response) = try await request(
            path: "/api/v1/repos/\(remote.owner)/\(remote.repo)/issues",
            method: "GET",
            queryItems: queryItems,
            body: nil,
            bypassCache: bypassCache
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let issues = try decoder.decode([GiteaIssuePayload].self, from: data)
        let items = issues.filter { $0.pullRequest == nil }.map(workItem(from:))

        return GitHubBoardSnapshot(
            columns: makeColumns(for: items),
            totalCount: response.value(forHTTPHeaderField: "X-Total-Count").flatMap(Int.init) ?? items.count,
            shownCount: items.count,
            incompleteResults: false,
            queryDescription: "Issues · \(state.rawValue) · \(remote.nameWithOwner)",
            rateLimitRemaining: response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
            rateLimitResetAt: response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        )
    }

    func fetchDetail(for item: GitHubWorkItem, bypassCache: Bool = false) async throws -> GitHubIssueDetail {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        async let issueTask = request(
            path: "/api/v1/repos/\(remote.owner)/\(remote.repo)/issues/\(item.number)",
            method: "GET",
            queryItems: [],
            body: nil,
            bypassCache: bypassCache
        )
        async let commentsTask = request(
            path: "/api/v1/repos/\(remote.owner)/\(remote.repo)/issues/\(item.number)/comments",
            method: "GET",
            queryItems: [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "page", value: "1")],
            body: nil,
            bypassCache: bypassCache
        )

        let (issueData, _) = try await issueTask
        let issue = try decoder.decode(GiteaIssuePayload.self, from: issueData)
        let (commentsData, _) = try await commentsTask
        let comments = try decoder.decode([GiteaCommentPayload].self, from: commentsData)

        return GitHubIssueDetail(
            item: workItem(from: issue),
            body: issue.body ?? "",
            state: issue.state,
            stateReason: nil,
            type: nil,
            author: issue.user?.login,
            assignees: issue.assignees.map(\.login),
            labels: issue.labels.map { GitHubLabel(name: $0.name, color: $0.color) },
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            closedAt: issue.closedAt,
            parent: nil,
            subIssues: [],
            blockedBy: [],
            blocking: [],
            comments: comments.map { comment in
                GitHubIssueComment(
                    id: comment.id,
                    author: comment.user.login,
                    body: comment.body,
                    createdAt: comment.createdAt,
                    updatedAt: comment.updatedAt,
                    url: comment.htmlURL
                )
            }
        )
    }

    func postComment(body: String, for item: GitHubWorkItem) async throws {
        let payload = try JSONEncoder().encode(["body": body])
        _ = try await request(
            path: "/api/v1/repos/\(remote.owner)/\(remote.repo)/issues/\(item.number)/comments",
            method: "POST",
            queryItems: [],
            body: payload
        )
    }

    func closeIssue(_ item: GitHubWorkItem) async throws {
        try await setIssueState(item, state: "closed")
    }

    func reopenIssue(_ item: GitHubWorkItem) async throws {
        try await setIssueState(item, state: "open")
    }

    private func setIssueState(_ item: GitHubWorkItem, state: String) async throws {
        let payload = try JSONEncoder().encode(["state": state])
        _ = try await request(
            path: "/api/v1/repos/\(remote.owner)/\(remote.repo)/issues/\(item.number)",
            method: "PATCH",
            queryItems: [],
            body: payload
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?,
        bypassCache: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = remote.host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GiteaError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw GiteaError.requestFailed(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, httpResponse)
    }

    private func workItem(from issue: GiteaIssuePayload) -> GitHubWorkItem {
        GitHubWorkItem(
            id: "\(remote.repositoryKey)#\(issue.number)",
            number: issue.number,
            title: issue.title,
            repository: remote.nameWithOwner,
            url: issue.htmlURL,
            isPullRequest: false,
            state: issue.state,
            stateReason: nil,
            type: nil,
            labels: issue.labels.map { GitHubLabel(name: $0.name, color: $0.color) },
            assignees: issue.assignees.map(\.login),
            author: issue.user?.login,
            body: issue.body ?? "",
            commentCount: issue.comments,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            closedAt: issue.closedAt,
            subIssuesSummary: nil,
            issueDependenciesSummary: nil
        )
    }

    private func makeColumns(for items: [GitHubWorkItem]) -> [GitHubBoardColumn] {
        let grouped = Dictionary(grouping: items, by: { $0.state.lowercased() == "closed" ? "Closed" : "Open" })
        let preferredOrder = ["Open", "Closed"]
        return grouped.map { title, groupedItems in
            GitHubBoardColumn(title: title, items: groupedItems.sorted { $0.updatedAt > $1.updatedAt })
        }.sorted { lhs, rhs in
            (preferredOrder.firstIndex(of: lhs.title) ?? Int.max) < (preferredOrder.firstIndex(of: rhs.title) ?? Int.max)
        }
    }

    private static func token(for host: String, environment: [String: String]) -> String? {
        let suffix = host.uppercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }.map(String.init).joined()
        return ["GITEA_TOKEN_\(suffix)", "GITEA_TOKEN"]
            .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct GiteaIssuePayload: Decodable {
    struct User: Decodable { let login: String }
    struct Label: Decodable {
        let name: String
        let color: String?
    }
    struct PullRequestMarker: Decodable {}

    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlURL: URL
    let user: User?
    let assignees: [User]
    let labels: [Label]
    let comments: Int
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case body
        case state
        case htmlURL = "html_url"
        case user
        case assignees
        case labels
        case comments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case pullRequest = "pull_request"
    }
}

private struct GiteaCommentPayload: Decodable {
    struct User: Decodable { let login: String }

    let id: Int
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL
    let user: User

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
        case user
    }
}
