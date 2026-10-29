import VideoScribeCore
import XCTest
@testable import VideoScribe
@MainActor final class PipelineTests: XCTestCase {
    func fixture(_ name: String) throws -> URL {
        guard let root = ProcessInfo.processInfo.environment["VIDEOSCRIBE_TEST_ROOT"] else { throw XCTSkip("Set VIDEOSCRIBE_TEST_ROOT for local media tests") }
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw XCTSkip("Generate the optional media fixture first: \(name)") }
        return url
    }
    func workspace() throws -> Workspace {
        guard let base = ProcessInfo.processInfo.environment["VIDEOSCRIBE_TEST_ROOT"] else { throw XCTSkip("Set VIDEOSCRIBE_TEST_ROOT to run media integration tests") }
        return Workspace(rootOverride: URL(fileURLWithPath: base).appendingPathComponent(UUID().uuidString))
    }
    func testSubtitleLanguageSelection() {
        XCTAssertEqual(Workspace.normalizedLanguage("en-US"), "en")
        XCTAssertEqual(Workspace.normalizedLanguage("zho"), "zh")
        XCTAssertNil(Workspace.normalizedLanguage("und"))
        XCTAssertTrue(Workspace.subtitleMatches(URL(fileURLWithPath: "media.en.srt"), language: "en"))
        XCTAssertFalse(Workspace.subtitleMatches(URL(fileURLWithPath: "media.zh-Hans.srt"), language: "en"))
    }
    func testChineseASR() async throws {
        let w = try workspace()
        let path = try fixture("chinese.aiff")
        let t = try await w.process(runner: ProcessRunner(), mode: 1, local: path, address: "", language: "zh", forced: true, keep: true, model: ToolPaths.defaultModel)
        XCTAssertTrue(t.plain.contains("中文"), t.plain)
        try t.plain.write(to: w.root.appendingPathComponent("verified-chinese.txt"), atomically: true, encoding: .utf8)
    }
    func testLocalASR() async throws {
        let w = try workspace()
        let t = try await w.process(runner: ProcessRunner(), mode: 1, local: try fixture("english.wav"), address: "", language: "en", forced: true, keep: true, model: ToolPaths.defaultModel)
        XCTAssertTrue(t.plain.lowercased().contains("country"), t.plain)
        XCTAssertTrue(t.segments.count > 0)
        try t.plain.write(to: w.root.appendingPathComponent("verified-plain.txt"), atomically: true, encoding: .utf8)
        try t.timed.write(to: w.root.appendingPathComponent("verified-timed.txt"), atomically: true, encoding: .utf8)
    }
    func testEmbeddedSubtitles() async throws {
        let w = try workspace()
        let path = try fixture("embedded.mkv")
        let t = try await w.process(runner: ProcessRunner(), mode: 1, local: path, address: "", language: "zh", forced: false, keep: true, model: ToolPaths.defaultModel)
        XCTAssertEqual(t.method, "本地内嵌文本字幕"); XCTAssertTrue(t.plain.contains("中文")); XCTAssertTrue(t.srt.contains("00:00:01,000"))
    }
    func testSidecarSubtitles() async throws {
        let w = try workspace()
        let path = try fixture("sidecar.wav")
        let t = try await w.process(runner: ProcessRunner(), mode: 1, local: path, address: "", language: "zh", forced: false, keep: true, model: ToolPaths.defaultModel)
        XCTAssertEqual(t.method, "本地外挂字幕"); XCTAssertTrue(t.plain.contains("中文"))
    }
    func testVideoURLDownload() async throws {
        guard let address = ProcessInfo.processInfo.environment["VIDEOSCRIBE_TEST_VIDEO_URL"] else { throw XCTSkip("Local video URL fixture is opt-in") }
        let w = try workspace()
        let t = try await w.process(runner: ProcessRunner(), mode: 0, local: nil, address: address, language: "en", forced: false, keep: true, model: ToolPaths.defaultModel)
        XCTAssertTrue(t.plain.lowercased().contains("country"), t.plain)
        XCTAssertTrue(t.mediaPath.map { FileManager.default.fileExists(atPath: $0) } ?? false)
        XCTAssertEqual(t.mediaPath.map { URL(fileURLWithPath: $0).pathExtension }, "mp4")
    }
    func testURLDownload() async throws {
        guard let address = ProcessInfo.processInfo.environment["VIDEOSCRIBE_TEST_URL"] else { throw XCTSkip("Set VIDEOSCRIBE_TEST_URL for an explicit network test") }
        let w = try workspace()
        let t = try await w.process(runner: ProcessRunner(), mode: 0, local: nil, address: address, language: "auto", forced: false, keep: false, model: ToolPaths.defaultModel)
        XCTAssertFalse(t.segments.isEmpty); XCTAssertNil(t.mediaPath)
    }
    func testCancelledRunnerDoesNotLaunch() async throws {
        _ = try workspace()
        let r = ProcessRunner(); r.cancel()
        do { _ = try await r.run(URL(fileURLWithPath: "/usr/bin/true"), []); XCTFail("Should cancel") } catch is CancellationError {} 
    }
}
