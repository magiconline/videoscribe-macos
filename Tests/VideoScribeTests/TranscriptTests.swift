import VideoScribeCore
import XCTest
@testable import VideoScribe
final class TranscriptTests: XCTestCase {
    func testSRTAndExports() {
        let text = "1\r\n00:00:01,250 --> 00:00:03,500\r\n你好 &amp; hello\r\n\r\n2\r\n00:00:03,500 --> 00:00:05,000\r\n第二行\r\n"
        let s = SubtitleParser.parse(text)
        XCTAssertEqual(s.count, 2); XCTAssertEqual(s[0].start, 1.25); XCTAssertEqual(s[0].text, "你好 & hello")
        let t = Transcript(title: "测试", source: "local", method: "test", segments: s)
        XCTAssertEqual(SubtitleParser.parse(t.srt).map(\.text), s.map(\.text))
        XCTAssertFalse(t.plain.contains("00:00")); XCTAssertTrue(t.timed.contains("00:00:01"))
    }
    func testVTTDuplicateAndTags() {
        let s = SubtitleParser.parse("WEBVTT\n\n00:01.000 --> 00:02.000 align:start\n<c>Hello</c>\n\n00:02.000 --> 00:03.000\nHello\n\n00:03.000 --> 00:04.000\nWorld\n")
        XCTAssertEqual(s.count, 2); XCTAssertEqual(s[0].end, 3); XCTAssertEqual(s[0].text, "Hello")
    }
    func testRejectInvalidAndLongTimes() {
        XCTAssertTrue(SubtitleParser.parse("not subtitles").isEmpty)
        XCTAssertTrue(SubtitleParser.parse("00:02.000 --> 00:01.000\ninvalid\n").isEmpty)
        XCTAssertEqual(Transcript.clock(3661.125, millis: true), "01:01:01,125")
    }
}
