import AppKit
import XCTest
@testable import agent_deck

@MainActor
final class PiAgentComposerImageLoaderTests: XCTestCase {
    nonisolated(unsafe) private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
    }

    func testImagesFromPasteboardPrefersFileURLOverRawImageData() throws {
        let pngData = try makePNGData()
        let fileURL = try makeTempRoot().appendingPathComponent("copied.png")
        try pngData.write(to: fileURL)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PiAgentComposerImageLoaderTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))
        pasteboard.setData(pngData, forType: .png)

        let images = PiAgentComposerImageLoader.imagesFromPasteboard(pasteboard)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.name, "copied.png")
        XCTAssertEqual(images.first?.fileReference, fileURL.path)
    }

    func testImagesFromPasteboardReadsRawImageDataWhenNoFileURLExists() throws {
        let pngData = try makePNGData()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PiAgentComposerImageLoaderTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        let images = PiAgentComposerImageLoader.imagesFromPasteboard(pasteboard)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.name, "pasted-image.png")
        XCTAssertEqual(images.first?.fileReference, "pasted-image.png")
    }

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiAgentComposerImageLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func makePNGData() throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "PiAgentComposerImageLoaderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap rep."])
        }
        rep.setColor(.red, atX: 0, y: 0)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PiAgentComposerImageLoaderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
        }
        return data
    }
}
