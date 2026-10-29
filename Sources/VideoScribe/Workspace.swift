import VideoScribeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class Workspace: ObservableObject {
    @Published var urlText = ""
    @Published var localURL: URL?
    @Published var sourceMode = 0
    @Published var language = "auto"
    @Published var forceASR = false
    @Published var keepVideo = true
    @Published var maxHeight = 720
    @Published var modelPath = UserDefaults.standard.string(forKey: "modelPath") ?? ""
    @Published var busy = false
    @Published var status = "准备就绪"
    @Published var networkDescription = "跟随 macOS 系统代理（每次任务自动读取）"
    @Published var errorMessage: String?
    @Published var log = ""
    @Published var records: [Transcript] = []
    @Published var selected: UUID?
    @Published var showTime = true
    @Published var search = ""
    var runner: ProcessRunner?
    private var activeJobID: String?
    var jobs: JobService { JobService(root: root.appendingPathComponent("jobs")) }
    var current: Transcript? { records.first { $0.id == selected } }
    let root: URL
    init(rootOverride: URL? = nil) {
        root = rootOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoScribe")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent("history.json")), let items = try? JSONDecoder().decode([Transcript].self, from: data) { records = items; selected = items.first?.id }
    }
    func persist() { if let data = try? JSONEncoder().encode(records) { try? data.write(to: root.appendingPathComponent("history.json"), options: .atomic) } }
    func importMedia() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "mkv") ?? .data, UTType(filenameExtension: "webm") ?? .data]; p.canChooseDirectories = false
        if p.runModal() == .OK { localURL = p.url; sourceMode = 1 }
    }
    func chooseModel() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        if p.runModal() == .OK, let u = p.url { modelPath = u.path; UserDefaults.standard.set(modelPath, forKey: "modelPath") }
    }
    func cancel() {
        if let id = activeJobID { _ = try? jobs.cancel(id) } else { runner?.cancel() }
        status = "正在取消…"
    }
    func refreshCompletedJobs() {
        guard let completed = try? jobs.list(limit: 100) else { return }
        var changed = false
        for job in completed.reversed() where job.status == "completed" {
            if let item = try? jobs.transcript(job.id), !records.contains(where: { $0.id == item.id }) { records.insert(item, at: 0); if selected == nil { selected = item.id }; changed = true }
        }
        if changed { persist() }
    }
    func appendLog(_ text: String) { log = String((log + text).suffix(20000)) }
    func start() {
        guard !busy else { return }
        if sourceMode == 0 {
            guard let u = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { errorMessage = "请输入有效的 http 或 https 视频网址。"; return }
        } else if localURL == nil { importMedia(); return }
        busy = true; errorMessage = nil; log = ""; status = "准备素材…"
        let source = sourceMode == 0 ? urlText.trimmingCharacters(in: .whitespacesAndNewlines) : localURL!.path
        let request = JobRequest(source: source, language: language, forceTranscription: forceASR, keepVideo: keepVideo, maxHeight: maxHeight, modelPath: modelPath.isEmpty ? nil : modelPath)
        Task {
            do {
                let created = try jobs.submit(request); activeJobID = created.id
                while true {
                    let job = try jobs.get(created.id)
                    status = job.phase
                    if let network = job.network { networkDescription = network }
                    log = (try? jobs.logTail(job.id, maxBytes: 20000)) ?? ""
                    if job.status == "completed" {
                        let result = try jobs.transcript(job.id)
                        if !records.contains(where: { $0.id == result.id }) { records.insert(result, at: 0) }
                        selected = result.id; persist(); status = "已完成 · \(result.segments.count) 段文字"; break
                    }
                    if job.status == "cancelled" { status = "已取消，可重新开始"; break }
                    if job.terminal { throw ToolError(message: job.error ?? job.phase) }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch { status = "处理失败"; errorMessage = error.localizedDescription }
            activeJobID = nil; busy = false
        }
    }
    func process(runner: ProcessRunner, mode: Int, local: URL?, address: String, language: String, forced: Bool, keep: Bool, model: String, maxHeight: Int = 720) async throws -> Transcript {
        try await VideoProcessor.process(root: root, runner: runner, mode: mode, local: local, address: address, language: language, forced: forced, keep: keep, model: model, maxHeight: maxHeight,
            progress: { [weak self] value in Task { @MainActor in self?.status = value } },
            network: { [weak self] value in Task { @MainActor in self?.networkDescription = value } },
            report: { [weak self] value in Task { @MainActor in self?.appendLog(value) } })
    }
    static func normalizedLanguage(_ input: String) -> String? { VideoProcessor.normalizedLanguage(input) }
    static func subtitleMatches(_ url: URL, language: String) -> Bool { VideoProcessor.subtitleMatches(url, language: language) }
    func export(_ format: String) {
        guard let item = current else { return }
        let panel = NSSavePanel(); let ext = format == "srt" ? "srt" : format == "json" ? "json" : "txt"
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
        let suffix = format == "plain" ? "纯文字" : format == "timed" ? "带时间戳" : format
        panel.nameFieldStringValue = item.title.replacingOccurrences(of: "/", with: "-") + "-\(suffix).\(ext)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
        do {
            if format == "json" { let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; try enc.encode(item).write(to: url, options: .atomic) }
            else { try (format == "srt" ? item.srt : format == "plain" ? item.plain : item.timed).write(to: url, atomically: true, encoding: .utf8) }
            self.status = "已导出：\(url.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { self.errorMessage = "导出失败：\(error.localizedDescription)" }
        }
    }
}
