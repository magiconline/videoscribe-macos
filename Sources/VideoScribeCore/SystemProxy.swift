import Foundation
import CFNetwork

public struct ProxyRoute: Equatable, Sendable {
    public init(endpoint: String) { self.endpoint = endpoint }
    public let endpoint: String
    public var description: String { endpoint.isEmpty ? "系统指定直连" : "系统代理：\(endpoint)" }
    public var arguments: [String] { ["--proxy", endpoint] }
    public var environment: [String: String] {
        // Explicitly override inherited shell proxies, including no_proxy, so the system decision wins.
        Dictionary(uniqueKeysWithValues: ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"].map { ($0, endpoint) } + [("no_proxy", ""), ("NO_PROXY", "")])
    }
}
public enum SystemProxy {
    public static func resolve(for url: URL) async throws -> ProxyRoute {
        guard let raw = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            throw ToolError(message: "无法读取 macOS 系统代理设置，请检查网络设置后重试。")
        }
        // CFNetwork applies system bypass rules and selects the right proxy for this URL.
        let list = CFNetworkCopyProxiesForURL(url as CFURL, raw).takeRetainedValue() as NSArray
        guard let first = list.firstObject as? [String: Any] else { return ProxyRoute(endpoint: "") }
        let type = first[kCFProxyTypeKey as String] as? String ?? ""
        if type == kCFProxyTypeAutoConfigurationURL as String {
            guard let pacURL = first[kCFProxyAutoConfigurationURLKey as String] as? URL else { throw ToolError(message: "系统 PAC 代理地址无效。") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            configuration.timeoutIntervalForRequest = 20
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: pacURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw ToolError(message: "读取系统 PAC 失败：HTTP \(http.statusCode)。") }
            guard let script = String(data: data, encoding: .utf8) else { throw ToolError(message: "无法读取系统 PAC 脚本。") }
            return try await evaluate(script, url: url)
        }
        if type == kCFProxyTypeAutoConfigurationJavaScript as String {
            guard let script = first[kCFProxyAutoConfigurationJavaScriptKey as String] as? String else { throw ToolError(message: "系统 PAC 脚本为空。") }
            return try await evaluate(script, url: url)
        }
        return try parse(first)
    }
    private static func evaluate(_ script: String, url: URL) async throws -> ProxyRoute {
        try await Task.detached(priority: .userInitiated) {
            var error: Unmanaged<CFError>?
            guard let proxies = CFNetworkCopyProxiesForAutoConfigurationScript(script as CFString, url as CFURL, &error)?.takeRetainedValue() as? [[String: Any]], let first = proxies.first else {
                let detail = error?.takeRetainedValue().localizedDescription ?? "没有返回路由"
                throw ToolError(message: "系统 PAC 解析失败：\(detail)")
            }
            return try parse(first)
        }.value
    }
    public static func parse(_ entry: [String: Any]) throws -> ProxyRoute {
        let type = entry[kCFProxyTypeKey as String] as? String ?? ""
        if type == kCFProxyTypeNone as String { return ProxyRoute(endpoint: "") }
        guard [kCFProxyTypeHTTP as String, kCFProxyTypeHTTPS as String, kCFProxyTypeSOCKS as String].contains(type),
              let host = entry[kCFProxyHostNameKey as String] as? String, !host.isEmpty,
              let port = entry[kCFProxyPortNumberKey as String] as? NSNumber, (1...65535).contains(port.intValue) else {
            throw ToolError(message: "系统代理类型或地址不受支持，请检查 macOS 网络代理设置。")
        }
        var components = URLComponents()
        components.scheme = type == kCFProxyTypeSOCKS as String ? "socks5" : "http"
        components.host = host; components.port = port.intValue
        guard let endpoint = components.url?.absoluteString else { throw ToolError(message: "系统代理地址无效。") }
        return ProxyRoute(endpoint: endpoint)
    }
}
