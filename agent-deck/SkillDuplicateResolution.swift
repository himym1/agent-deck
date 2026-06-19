import Foundation

/// Source-aware removal of duplicate skill copies during conflict resolution.
///
/// Duplicate resolution is different from normal skill deletion: the skill
/// *name* stays assigned to projects / defaults / agents, only the losing
/// physical/source copy is removed. Callers must therefore not run the
/// standard `removeSkillReferences(named:)` cleanup that clears name-based
/// assignments.
enum SkillDuplicateResolution {
    /// Details captured when resolving a duplicate so the UI can show a
    /// confirmation summarizing exactly what will happen.
    struct ResolutionSummary {
        let keptSkill: SkillRecord
        let removedSkills: [SkillRecord]
        let descriptions: [String]
    }

    /// Errors specific to duplicate-resolution validation.
    enum Error: Swift.Error, LocalizedError {
        case mismatchedSkillNames
        case cannotRemoveBundledOrPackageSkill(SkillRecord)
        case cannotDeleteSkill(SkillRecord)

        var errorDescription: String? {
            switch self {
            case .mismatchedSkillNames:
                return "All duplicate copies must share the same skill name."
            case let .cannotRemoveBundledOrPackageSkill(skill):
                return "\"\(skill.name)\" from \(skill.source.kind.rawValue) cannot be removed. Choose a different copy to keep."
            case let .cannotDeleteSkill(skill):
                return "\"\(skill.name)\" at \(skill.filePath) could not be deleted."
            }
        }
    }

    /// Builds a human-readable summary of what resolving a duplicate will do.
    static func summary(
        keeping keptSkill: SkillRecord,
        removing removedSkills: [SkillRecord],
        isImported: (SkillRecord) -> Bool
    ) throws -> ResolutionSummary {
        let name = keptSkill.name
        guard removedSkills.allSatisfy({ $0.name == name }) else {
            throw Error.mismatchedSkillNames
        }

        let descriptions = removedSkills.map { skill in
            if isImported(skill) {
                return "Remove the imported/synced copy at \(skill.filePath) from the catalog"
            }
            return "Move the local copy at \(skill.filePath) to the Trash"
        }

        return ResolutionSummary(keptSkill: keptSkill, removedSkills: removedSkills, descriptions: descriptions)
    }

    /// Whether every skill in `removedSkills` can be removed by
    /// `removeDuplicateCopies` given the supplied capabilities.
    static func canResolve(
        keeping keptSkill: SkillRecord,
        removing removedSkills: [SkillRecord],
        canDelete: (SkillRecord) -> Bool,
        isImported: (SkillRecord) -> Bool
    ) -> Bool {
        guard removedSkills.allSatisfy({ $0.name == keptSkill.name }) else { return false }
        return removedSkills.allSatisfy { skill in
            switch skill.source.kind {
            case .builtin, .package:
                return false
            case .global, .project, .legacyProject, .override, .library:
                return isImported(skill) || canDelete(skill)
            }
        }
    }

    /// Removes every duplicate copy except `keptSkill`.
    ///
    /// - Parameters:
    ///   - keptSkill: The canonical copy that will remain.
    ///   - removedSkills: The other copies sharing the same name.
    ///   - canDelete: Whether the copy can be moved to trash.
    ///   - delete: Closure that moves a local copy to trash.
    ///   - isImported: Whether the copy came from an imported catalog path.
    ///   - removeExternalPath: Closure that drops the imported path from the
    ///     catalog without deleting files.
    ///   - unlistFromSyncedRepository: Closure that removes a synced-repo copy
    ///     from its repository's tracked set and reconciles sparse checkout.
    ///
    /// This helper intentionally has no "remove name-based references" closure,
    /// because assignments/global defaults/agent skills keyed by name must be
    /// preserved.
    static func removeDuplicateCopies(
        keeping keptSkill: SkillRecord,
        removing removedSkills: [SkillRecord],
        canDelete: (SkillRecord) -> Bool,
        delete: (SkillRecord) throws -> Void,
        isImported: (SkillRecord) -> Bool,
        removeExternalPath: (SkillRecord) -> Void,
        unlistFromSyncedRepository: (SkillRecord) -> Void
    ) throws {
        let name = keptSkill.name
        guard removedSkills.allSatisfy({ $0.name == name }) else {
            throw Error.mismatchedSkillNames
        }
        guard !removedSkills.contains(where: { $0.id == keptSkill.id }) else {
            throw Error.mismatchedSkillNames
        }

        // Preflight so we never partially resolve a duplicate.
        for skill in removedSkills {
            switch skill.source.kind {
            case .builtin, .package:
                throw Error.cannotRemoveBundledOrPackageSkill(skill)
            case .global, .project, .legacyProject, .override, .library:
                if !isImported(skill), !canDelete(skill) {
                    throw Error.cannotDeleteSkill(skill)
                }
            }
        }

        for skill in removedSkills {
            switch skill.source.kind {
            case .builtin, .package:
                // Built-in and package skills are read-only; the caller should
                // prevent picking one as the loser. If we get here, fail loudly
                // rather than silently leave a duplicate behind.
                throw Error.cannotRemoveBundledOrPackageSkill(skill)

            case .global, .project, .legacyProject, .override, .library:
                if isImported(skill) {
                    // Imported/synced skill: keep files, drop catalog entry and
                    // repo tracking so the next sync doesn't re-import it.
                    removeExternalPath(skill)
                    unlistFromSyncedRepository(skill)
                } else {
                    // Local skill: move to trash after confirming it's deletable.
                    guard canDelete(skill) else {
                        throw Error.cannotDeleteSkill(skill)
                    }
                    try delete(skill)
                }
            }
        }
    }
}
