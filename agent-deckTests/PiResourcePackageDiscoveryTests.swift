import XCTest
@testable import agent_deck

final class PiResourcePackageDiscoveryTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
    }

    func testPackageSkillsSupportDirectSkillDirectoryAndManifestGlob() throws {
        let home = try makeTempRoot()
        let packageRef = "git:github.com/himym1/CodeStable@pi-first-v0.1"
        let package = home.appendingPathComponent(".pi/agent/git/github.com/himym1/CodeStable", isDirectory: true)
        try writeSettings(home: home, packages: [packageRef])
        try writePackageManifest(
            at: package,
            pi: ["skills": ["./cs", "./cs-*"]]
        )
        try writeSkill(at: package.appendingPathComponent("cs", isDirectory: true), name: "cs")
        try writeFile(package.appendingPathComponent("cs/reference.md"), contents: "---\nname: cs\ndescription: reference only\n---\n# Reference\n")
        try writeSkill(at: package.appendingPathComponent("cs-feat", isDirectory: true), name: "cs-feat")
        try writeSkill(at: package.appendingPathComponent("cs-onboard", isDirectory: true), name: "cs-onboard")
        try writeSkill(at: package.appendingPathComponent("browser-bridge", isDirectory: true), name: "browser-bridge")

        let snapshot = PiScanner(homeDirectory: home).scan(projectRoot: nil)
        let packageSkillNames = Set(snapshot.skills.filter { $0.source.kind == .package }.map(\.name))

        XCTAssertTrue(packageSkillNames.contains("cs"))
        XCTAssertTrue(packageSkillNames.contains("cs-feat"))
        XCTAssertTrue(packageSkillNames.contains("cs-onboard"))
        XCTAssertFalse(packageSkillNames.contains("browser-bridge"))
        let csRecords = snapshot.skills.filter { $0.source.kind == .package && $0.name == "cs" }
        XCTAssertEqual(csRecords.count, 1)
        XCTAssertTrue(csRecords.first?.filePath.hasSuffix("/cs/SKILL.md") == true)
    }

    func testLegacySkillsScanNestedSkillRoots() throws {
        let home = try makeTempRoot()
        try writeSkill(at: home.appendingPathComponent(".agents/skills/document-skills/docx", isDirectory: true), name: "docx")
        try writeSkill(at: home.appendingPathComponent(".agents/skills/document-skills/pdf", isDirectory: true), name: "pdf")
        try writeSkill(at: home.appendingPathComponent(".agents/skills/node_modules/hidden", isDirectory: true), name: "hidden")

        let snapshot = PiScanner(homeDirectory: home).scan(projectRoot: nil)
        let legacySkillNames = Set(snapshot.skills.filter { $0.source.kind == .global }.map(\.name))

        XCTAssertTrue(legacySkillNames.contains("docx"))
        XCTAssertTrue(legacySkillNames.contains("pdf"))
        XCTAssertFalse(legacySkillNames.contains("hidden"))
    }

    func testPackageExtensionDiscoverySupportsJavaScriptEntriesAndManifestGlobs() throws {
        let home = try makeTempRoot()
        let packageRef = "npm:@spences10/pi-redact"
        let package = home.appendingPathComponent(".pi/agent/npm/node_modules/@spences10/pi-redact", isDirectory: true)
        try writeSettings(home: home, packages: [packageRef])
        try writePackageManifest(
            at: package,
            pi: ["extensions": ["./dist/index.js", "./extensions/*.ts", "!./extensions/legacy.ts"]]
        )
        try writeFile(package.appendingPathComponent("dist/index.js"), contents: "export default function () {}\n")
        try writeFile(package.appendingPathComponent("extensions/alpha.ts"), contents: "export default function () {}\n")
        try writeFile(package.appendingPathComponent("extensions/legacy.ts"), contents: "export default function () {}\n")

        let candidates = PiExtensionDiscoveryService(homeDirectory: home).discover(projectRoot: nil)
        let launchSources = candidates.map(\.launchSource)

        XCTAssertTrue(launchSources.contains { $0.hasSuffix("/dist/index.js") })
        XCTAssertTrue(launchSources.contains { $0.hasSuffix("/extensions/alpha.ts") })
        XCTAssertFalse(launchSources.contains { $0.hasSuffix("/extensions/legacy.ts") })
    }

    func testPackageScannerSkipsMissingPackageDeclaredResourceDirectories() throws {
        let home = try makeTempRoot()
        let packageRef = "npm:pi-btw"
        let package = home.appendingPathComponent(".pi/agent/npm/node_modules/pi-btw", isDirectory: true)
        try writeSettings(home: home, packages: [packageRef])
        try writePackageManifest(
            at: package,
            pi: ["extensions": ["./extensions/btw.ts"], "skills": ["./skills"], "prompts": ["./prompts"]]
        )
        try writeFile(package.appendingPathComponent("extensions/btw.ts"), contents: "export default function () {}\n")

        let snapshot = PiScanner(homeDirectory: home).scan(projectRoot: nil)
        let packageWarnings = snapshot.warnings.filter { warning in
            warning.message.contains("pi-btw")
                || warning.message.contains("Package pi-btw declares")
        }

        XCTAssertTrue(packageWarnings.isEmpty, packageWarnings.map(\.message).joined(separator: "\n"))
    }

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiResourcePackageDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func writeSettings(home: URL, packages: [String]) throws {
        try writeJSON(["packages": packages], to: home.appendingPathComponent(".pi/agent/settings.json"))
    }

    private func writePackageManifest(at package: URL, pi: [String: Any]) throws {
        try writeJSON(["name": "test-package", "pi": pi], to: package.appendingPathComponent("package.json"))
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func writeSkill(at directory: URL, name: String) throws {
        try writeFile(
            directory.appendingPathComponent("SKILL.md"),
            contents: """
            ---
            name: \(name)
            description: \(name) skill.
            ---

            # \(name)
            """
        )
    }

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
