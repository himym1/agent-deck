import Foundation

/// Replicates `scripts/release.sh` for Agent Deck: preflight a clean, synced
/// `main`, read the latest `vX.Y` tag, then `git tag -a` + `git push` a minor or
/// major bump. The pushed tag fires `.github/workflows/release.yml`, which does
/// the actual build/sign/notarize/publish — this service only tags and pushes.
struct ReleaseService {
    /// The one repo this whole flow is scoped to. The toolbar button only shows
    /// when the selected session's repo matches this.
    nonisolated static let repository = "a-streetcoder/agent-deck"
    nonisolated static let remote = "origin"
    nonisolated static let mainBranch = "main"

    enum Bump: Hashable {
        case minor
        case major
    }

    struct Preflight: Hashable {
        let latestTag: String?
        let branch: String
        let isClean: Bool
        let ahead: Int
        let behind: Int
        let nextMinor: String
        let nextMajor: String
        /// Human-readable reason the repo can't be released right now, or nil.
        let blocker: String?

        var isReleasable: Bool { blocker == nil }

        func tag(for bump: Bump) -> String {
            switch bump {
            case .minor: return nextMinor
            case .major: return nextMajor
            }
        }
    }

    enum ReleaseError: LocalizedError {
        case tagExistsLocally(String)
        case tagExistsOnRemote(String)

        var errorDescription: String? {
            switch self {
            case let .tagExistsLocally(tag): return "Tag \(tag) already exists locally."
            case let .tagExistsOnRemote(tag): return "Tag \(tag) already exists on \(ReleaseService.remote)."
            }
        }
    }

    private let gitRepositoryService: GitRepositoryService

    init(gitRepositoryService: GitRepositoryService) {
        self.gitRepositoryService = gitRepositoryService
    }

    func preflight(projectURL: URL) async throws -> Preflight {
        // Refresh remote refs so ahead/behind and the latest tag are accurate.
        // Tolerate fetch failures (offline): the local snapshot still informs the UI.
        try? await gitRepositoryService.fetch(remote: Self.remote, branch: Self.mainBranch, in: projectURL)
        try? await gitRepositoryService.fetchTags(remote: Self.remote, in: projectURL)

        let changes = try await gitRepositoryService.loadChanges(in: projectURL)
        let latestTag = try await gitRepositoryService.latestVersionTag(in: projectURL)
        let isClean = changes.totalChangeCount == 0
        let (nextMinor, nextMajor) = Self.nextVersions(from: latestTag)

        return Preflight(
            latestTag: latestTag,
            branch: changes.branchName,
            isClean: isClean,
            ahead: changes.aheadCount,
            behind: changes.behindCount,
            nextMinor: nextMinor,
            nextMajor: nextMajor,
            blocker: Self.blocker(branch: changes.branchName, isClean: isClean, ahead: changes.aheadCount, behind: changes.behindCount)
        )
    }

    func tagAndPush(tag: String, projectURL: URL) async throws {
        if try await gitRepositoryService.localTagExists(tag, in: projectURL) {
            throw ReleaseError.tagExistsLocally(tag)
        }
        if try await gitRepositoryService.remoteTagExists(tag, remote: Self.remote, in: projectURL) {
            throw ReleaseError.tagExistsOnRemote(tag)
        }
        try await gitRepositoryService.createAnnotatedTag(tag, message: tag, in: projectURL)
        try await gitRepositoryService.pushTag(tag, remote: Self.remote, in: projectURL)
    }

    // MARK: - Version math (mirrors scripts/release.sh:53-71)

    static func nextVersions(from latestTag: String?) -> (minor: String, major: String) {
        let major: Int
        let minor: Int
        if let latestTag, let parsed = parseVersion(latestTag) {
            major = parsed.major
            minor = parsed.minor
        } else {
            // No prior tag: propose v1.0 as the minor bump.
            major = 0
            minor = 9
        }
        return ("v\(major).\(minor + 1)", "v\(major + 1).0")
    }

    static func parseVersion(_ tag: String) -> (major: Int, minor: Int)? {
        let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = trimmed.split(separator: ".")
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    // MARK: - Preflight gating (mirrors scripts/release.sh:31-49)

    static func blocker(branch: String, isClean: Bool, ahead: Int, behind: Int) -> String? {
        if branch != mainBranch { return "Must be on \(mainBranch) (currently on '\(branch)')." }
        if !isClean { return "Working tree has uncommitted changes — commit or stash first." }
        if ahead > 0 { return "\(mainBranch) is \(ahead) commit(s) ahead of \(remote)/\(mainBranch) — push first." }
        if behind > 0 { return "\(mainBranch) is \(behind) commit(s) behind \(remote)/\(mainBranch) — pull first." }
        return nil
    }

    static func actionsURL() -> URL? { URL(string: "https://github.com/\(repository)/actions") }
    static func releaseURL(tag: String) -> URL? { URL(string: "https://github.com/\(repository)/releases/tag/\(tag)") }
}
