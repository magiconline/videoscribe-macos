import Foundation

public struct ToolError: LocalizedError { public init(message: String) { self.message = message }; let message: String; public var errorDescription: String? { message } }
public final class ProcessRunner: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if let p, p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } }
    }
    public func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
    public func run(_ executable: URL, _ args: [String], environment: [String: String] = [:], log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.check()
                    let p = Process(), pipe = Pipe()
                    p.executableURL = executable; p.arguments = args
                    var env = ProcessInfo.processInfo.environment
                    let bundledBackends = executable.deletingLastPathComponent().appendingPathComponent("lib")
                    if FileManager.default.fileExists(atPath: bundledBackends.appendingPathComponent("libggml-metal.so").path) {
                        env["GGML_BACKEND_PATH"] = bundledBackends.path
                    }
                    env["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    for (key, value) in environment { env[key] = value }
                    p.environment = env; p.standardOutput = pipe; p.standardError = pipe
                    p.standardInput = FileHandle.nullDevice
                    self.lock.lock()
                    if self.cancelled { self.lock.unlock(); throw CancellationError() }
                    self.process = p
                    do { try p.run() } catch { self.process = nil; self.lock.unlock(); throw error }
                    self.lock.unlock()
                    var all = Data()
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        all.append(data)
                        if let s = String(data: data, encoding: .utf8) { log(s) }
                    }
                    p.waitUntilExit()
                    self.lock.lock(); self.process = nil; self.lock.unlock()
                    try self.check()
                    let result = String(decoding: all, as: UTF8.self)
                    guard p.terminationStatus == 0 else { throw ToolError(message: "\(executable.lastPathComponent) 处理失败（\(p.terminationStatus)）\n" + String(result.suffix(2400))) }
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
public struct ToolPaths {
    public static var resources: URL { ProcessInfo.processInfo.environment["VIDEOSCRIBE_RESOURCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath) }
    public static func tool(_ name: String) throws -> URL {
        let override = ProcessInfo.processInfo.environment["VIDEOSCRIBE_TOOL_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
        let candidates = [override, resources.appendingPathComponent("Tools/\(name)").path, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw ToolError(message: "缺少 \(name)，请在设置中检查依赖。") }
        return URL(fileURLWithPath: path)
    }
    public static var agentExecutable: URL {
        if let value = ProcessInfo.processInfo.environment["VIDEOSCRIBE_AGENT_EXECUTABLE"] { return URL(fileURLWithPath: value) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/VideoScribeAgent")
    }
    public static var defaultModel: String {
        if let path = ProcessInfo.processInfo.environment["VIDEOSCRIBE_MODEL_PATH"] { return path }
        let bundled = resources.appendingPathComponent("Models/ggml-base.bin")
        if FileManager.default.isReadableFile(atPath: bundled.path) { return bundled.path }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoScribe/models/ggml-base.bin").path
    }
}
