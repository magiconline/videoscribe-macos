import VideoScribeCore
import XCTest
import CFNetwork
@testable import VideoScribe
final class ProxyTests: XCTestCase {
    func testHTTPAndHTTPSProxy() throws {
        for type in [kCFProxyTypeHTTP, kCFProxyTypeHTTPS] {
            let p = try SystemProxy.parse([kCFProxyTypeKey as String: type as String, kCFProxyHostNameKey as String: "127.0.0.1", kCFProxyPortNumberKey as String: NSNumber(value: 18080)])
            XCTAssertEqual(p.arguments, ["--proxy", "http://127.0.0.1:18080"])
            XCTAssertEqual(p.environment["https_proxy"], "http://127.0.0.1:18080")
            XCTAssertEqual(p.environment["NO_PROXY"], "")
        }
    }
    func testSOCKSAndDirect() throws {
        let socks = try SystemProxy.parse([kCFProxyTypeKey as String: kCFProxyTypeSOCKS as String, kCFProxyHostNameKey as String: "127.0.0.1", kCFProxyPortNumberKey as String: NSNumber(value: 1080)])
        XCTAssertEqual(socks.endpoint, "socks5://127.0.0.1:1080")
        let direct = try SystemProxy.parse([kCFProxyTypeKey as String: kCFProxyTypeNone as String])
        XCTAssertEqual(direct.arguments, ["--proxy", ""])
        XCTAssertTrue(direct.environment.values.allSatisfy(\.isEmpty))
    }
    func testInvalidProxyDoesNotSilentlyGoDirect() {
        XCTAssertThrowsError(try SystemProxy.parse([kCFProxyTypeKey as String: "unknown"]))
        XCTAssertThrowsError(try SystemProxy.parse([kCFProxyTypeKey as String: kCFProxyTypeHTTP as String, kCFProxyHostNameKey as String: "localhost", kCFProxyPortNumberKey as String: NSNumber(value: 0)]))
    }
    func testLiveSystemProxyAndBypass() async throws {
        guard let expected = ProcessInfo.processInfo.environment["VIDEOSCRIBE_EXPECTED_PROXY"] else { throw XCTSkip("Live macOS proxy test is opt-in") }
        let external = try await SystemProxy.resolve(for: URL(string: "https://example.com/video")!)
        XCTAssertEqual(external.endpoint, expected)
        let local = try await SystemProxy.resolve(for: URL(string: "http://127.0.0.1:8080/download.mp4")!)
        XCTAssertEqual(local.endpoint, "")
    }
}
