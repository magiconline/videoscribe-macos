import Foundation
import Darwin

public struct JobRequest: Codable, Sendable {
    public var source: String
    public var language: String
    public var forceTranscription: Bool
    public var keepVideo: Bool
    public var maxHeight: Int
    public var modelPath: String?
    public init(source: String, language: String = "auto", forceTranscription: Bool = false, keepVideo: Bool = true, maxHeight: Int = 720, modelPath: String? = nil) {
        self.source = source; self.language = language; self.forceTranscription = forceTranscription; self.keepVideo = keepVideo; self.maxHeight = maxHeight; self.modelPath = modelPath
    }
    public func validate() throws {
        guard ["auto", "zh", "en"].contains(language), [360,720,1080].contains(maxHeight) else { throw ToolError(message: "language must be auto/zh/en; max_height must be 360/720/1080") }
        if source.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory), !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: source) else { throw ToolError(message: "Local input must be an existing readable file") }
        } else {
            guard let url = URL(string: source), ["http","https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else { throw ToolError(message: "source must be an http(s) URL or absolute local file path") }
        }
        if let modelPath { guard modelPath.hasPrefix("/"), FileManager.default.isReadableFile(atPath: modelPath) else { throw ToolError(message: "model_path must be an existing absolute path") } }
    }
}
public struct JobRecord: Codable, Identifiable {
    public var id: String
    public var status: String = "queued"
    public var phase: String = "等待处理"
    public var created = Date()
    public var updated = Date()
    public var pid: Int32?
    public var network: String?
    public var error: String?
    public var resultPath: String?
    public var request: JobRequest
    public var terminal: Bool { ["completed","failed","cancelled","interrupted"].contains(status) }
}
public struct JobService: Sendable {
    public let root: URL
    public let executable: URL
    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["VIDEOSCRIBE_DATA_DIR"] { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoScribe/jobs")
    }
    public init(root: URL = JobService.defaultRoot, executable: URL = ToolPaths.agentExecutable) { self.root = root; self.executable = executable }
    public func directory(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw ToolError(message: "Invalid job_id") }
        return root.appendingPathComponent(uuid.uuidString, isDirectory: true)
    }
    private func withLock<T>(_ file: URL, body: () throws -> T) throws -> T {
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ToolError(message: "Cannot open job lock") }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ToolError(message: "Cannot lock job") }
        return try body()
    }
    private func write(_ record: JobRecord, directory: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }
    private func read(_ directory: URL) throws -> JobRecord { try JSONDecoder().decode(JobRecord.self, from: Data(contentsOf: directory.appendingPathComponent("state.json"))) }
    public func update(_ id: String, _ change: (inout JobRecord) -> Void) throws {
        let dir = try directory(id)
        try withLock(dir.appendingPathComponent("state.lock")) {
            var record = try read(dir); change(&record); record.updated = Date(); try write(record, directory: dir)
        }
    }
    public func submit(_ request: JobRequest) throws -> JobRecord {
        try request.validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let record: JobRecord = try withLock(root.appendingPathComponent("submit.lock")) {
            let active = try list(limit: 1000).filter { !$0.terminal }
            guard active.count < 16 else { throw ToolError(message: "Queue is full (16 unfinished jobs); wait or cancel existing jobs") }
            let record = JobRecord(id: UUID().uuidString, request: request)
            let dir = try directory(record.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try write(record, directory: dir)
            return record
        }
        do { try spawn(record.id) }
        catch { try? update(record.id) { $0.status = "failed"; $0.phase = "启动失败"; $0.error = error.localizedDescription }; throw error }
        return record
    }
    private func spawn(_ id: String) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ToolError(message: "VideoScribeAgent executable is missing") }
        let dir = try directory(id)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, dir.appendingPathComponent("worker.log").path, O_CREAT | O_WRONLY | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
        // Separate process group: closing the MCP transport must not terminate a long media job.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)); posix_spawnattr_setpgroup(&attributes, 0)
        let args = [executable.path, "worker", "--data-dir", root.path, "--job", id]
        let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        let argv = args.map { strdup($0) } + [nil], envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { av in envp.withUnsafeBufferPointer { ev in posix_spawn(&pid, executable.path, &actions, &attributes, av.baseAddress!, ev.baseAddress!) } }
        guard result == 0 else { throw ToolError(message: "Worker spawn failed: \(String(cString: strerror(result)))") }
    }
    public func get(_ id: String) throws -> JobRecord {
        let dir = try directory(id)
        var record = try read(dir)
        if !record.terminal, Date().timeIntervalSince(record.created) > 15 {
            // The held worker lock proves identity; a reused PID cannot falsely keep a dead job alive.
            let fd = open(dir.appendingPathComponent("worker.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            if fd >= 0 {
                defer { close(fd) }
                if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                    defer { flock(fd, LOCK_UN) }
                    try update(id) { state in
                        if !state.terminal { state.status = "interrupted"; state.phase = "处理进程已中断，可重试"; state.error = "Worker exited before saving a final result" }
                    }
                    record = try read(dir)
                }
            }
        }
        return record
    }
    public func list(limit: Int = 100) throws -> [JobRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return folders.compactMap { url -> JobRecord? in guard UUID(uuidString: url.lastPathComponent) != nil else { return nil }; return try? get(url.lastPathComponent) }.sorted { $0.created > $1.created }.prefix(max(1,min(limit,1000))).map { $0 }
    }
    public func cancel(_ id: String) throws -> JobRecord {
        let record = try get(id)
        if !record.terminal { try Data().write(to: directory(id).appendingPathComponent("cancel.request"), options: .atomic) }
        return try get(id)
    }
    public func retry(_ id: String) throws -> JobRecord {
        let old = try get(id)
        guard old.terminal, old.status != "completed" else { throw ToolError(message: "Only failed, cancelled or interrupted jobs can be retried") }
        return try submit(old.request)
    }
    public func transcript(_ id: String) throws -> Transcript {
        let record = try get(id)
        guard record.status == "completed", let path = record.resultPath else { throw ToolError(message: "Transcript is not ready; query get_job first") }
        return try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    public func logTail(_ id: String, maxBytes: Int = 6000) throws -> String {
        let path = try directory(id).appendingPathComponent("worker.log")
        guard let handle = try? FileHandle(forReadingFrom: path) else { return "" }
        defer { try? handle.close() }
        let end = try handle.seekToEnd(); try handle.seek(toOffset: end > maxBytes ? end - UInt64(maxBytes) : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    }
    public func export(_ id: String, format: String, output: String? = nil, overwrite: Bool = false) throws -> URL {
        guard ["plain","timed","srt","json"].contains(format) else { throw ToolError(message: "format must be plain/timed/srt/json") }
        let transcript = try transcript(id)
        let ext = format == "srt" ? "srt" : format == "json" ? "json" : "txt"
        let destination: URL
        if let output {
            guard output.hasPrefix("/") else { throw ToolError(message: "output_path must be absolute") }
            destination = URL(fileURLWithPath: output)
        } else {
            let folder = try directory(id).appendingPathComponent("exports")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            destination = folder.appendingPathComponent("transcript-\(format).\(ext)")
        }
        let data = format == "json" ? try JSONEncoder().encode(transcript) : Data((format == "plain" ? transcript.plain : format == "timed" ? transcript.timed : transcript.srt).utf8)
        if output == nil || overwrite { try data.write(to: destination, options: .atomic) }
        else { try data.write(to: destination, options: .withoutOverwriting) }
        return destination
    }
    public func work(_ id: String) async throws {
        let dir = try directory(id)
        let lockFD = open(dir.appendingPathComponent("worker.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { close(lockFD) }; return }
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        guard !(try get(id)).terminal else { return }
        try update(id) { $0.pid = getpid() }
        let runner = ProcessRunner()
        let monitor = Task.detached {
            while !Task.isCancelled {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("cancel.request").path) { runner.cancel(); return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { monitor.cancel() }
        var slotFD: Int32 = -1
        defer { if slotFD >= 0 { flock(slotFD, LOCK_UN); close(slotFD) } }
        do {
            // At most two active processors across all GUI and MCP instances sharing this store.
            while slotFD < 0 {
                try runner.check()
                for index in 0..<2 {
                    let fd = open(root.appendingPathComponent("slot-\(index).lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
                    if fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 { slotFD = fd; break }
                    if fd >= 0 { close(fd) }
                }
                if slotFD < 0 { try await Task.sleep(nanoseconds: 300_000_000) }
            }
            let request = try get(id).request
            try update(id) { $0.status = "running"; $0.phase = "准备素材" }
            let result = try await VideoProcessor.process(root: dir, runner: runner, mode: request.source.hasPrefix("/") ? 1 : 0, local: request.source.hasPrefix("/") ? URL(fileURLWithPath: request.source) : nil, address: request.source, language: request.language, forced: request.forceTranscription, keep: request.keepVideo, model: request.modelPath ?? ToolPaths.defaultModel, maxHeight: request.maxHeight,
                progress: { phase in try? self.update(id) { $0.phase = phase } },
                network: { network in try? self.update(id) { $0.network = network } },
                report: { text in FileHandle.standardError.write(Data(text.utf8)) })
            try runner.check()
            let path = dir.appendingPathComponent("result.json")
            try JSONEncoder().encode(result).write(to: path, options: .atomic)
            try update(id) { $0.status = "completed"; $0.phase = "已完成"; $0.resultPath = path.path }
        } catch is CancellationError { try update(id) { $0.status = "cancelled"; $0.phase = "已取消" } }
        catch { try update(id) { $0.status = "failed"; $0.phase = "处理失败"; $0.error = error.localizedDescription } }
    }
}
