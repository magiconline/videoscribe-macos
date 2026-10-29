import Foundation

/// UI-independent media processing. All executables use argument arrays; no shell interpolation.
public enum VideoProcessor {
    public static func process(root: URL, runner: ProcessRunner, mode: Int, local: URL?, address: String, language: String, forced: Bool, keep: Bool, model: String, maxHeight: Int = 720,
        progress: @escaping @Sendable (String) -> Void = { _ in }, network: @escaping @Sendable (String) -> Void = { _ in }, report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Transcript {
        let dir = root.appendingPathComponent("Tasks/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: dir) } }
        let ffmpeg = try ToolPaths.tool("ffmpeg")
        var title = local?.deletingPathExtension().lastPathComponent ?? "视频文字稿", source = local?.path ?? address
        var originalLanguage: String?
        var media = local, segments: [Segment] = [], method = ""
        if mode == 0 {
            let ytdlp = try ToolPaths.tool("yt-dlp")
            let runtime = try ToolPaths.tool("node")
            progress("读取系统代理…")
            guard let sourceURL = URL(string: address) else { throw ToolError(message: "视频网址无效。") }
            let proxy = try await SystemProxy.resolve(for: sourceURL)
            network(proxy.description)
            report("网络路径：\(proxy.description)\n")
            let common = proxy.arguments + ["--js-runtimes", "node:\(runtime.path)", "--ignore-config", "--no-playlist", "--no-progress", "--socket-timeout", "20", "--retries", "2", "--concurrent-fragments", "4", "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path, "-o", dir.appendingPathComponent("media.%(ext)s").path]
            progress("读取视频信息…")
            let metadata = try await runner.run(ytdlp, common + ["--skip-download", "--write-info-json", "--", address], environment: proxy.environment, log: report)
            _ = metadata
            let infoPath = dir.appendingPathComponent("media.info.json")
            if let info = try? JSONSerialization.jsonObject(with: Data(contentsOf: infoPath)) as? [String: Any] { title = info["title"] as? String ?? title; source = info["webpage_url"] as? String ?? address; originalLanguage = Self.normalizedLanguage(info["language"] as? String ?? "") }
            if !forced, let subtitleLanguage = language == "auto" ? originalLanguage : Self.normalizedLanguage(language) {
                progress("提取匹配原声语言的字幕…")
                do {
                    _ = try await runner.run(ytdlp, common + ["--skip-download", "--write-subs", "--write-auto-subs", "--sub-langs", "\(subtitleLanguage).*", "--sub-format", "srt/vtt/best", "--convert-subs", "srt", "--", address], environment: proxy.environment, log: report)
                } catch is CancellationError { throw CancellationError() }
                catch { report("\n字幕获取未完成，将检查已有结果并按需转写。\n") }
                let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { ["srt", "vtt"].contains($0.pathExtension.lowercased()) }
                let ranked = files.filter { Self.subtitleMatches($0, language: subtitleLanguage) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                for file in ranked {
                    let parsed = SubtitleParser.parse(try String(contentsOf: file, encoding: .utf8))
                    if !parsed.isEmpty { segments = parsed; method = "平台字幕（\(file.lastPathComponent)；可能包含自动字幕）"; break }
                }
            }
            if keep || segments.isEmpty {
                progress(keep ? "下载视频…" : "下载转写所需音频…")
                let format = keep ? "bv*[height<=\(maxHeight)]+ba/b[height<=\(maxHeight)]/b" : "bestaudio/best"
                _ = try await runner.run(ytdlp, common + ["-f", format, "--merge-output-format", "mkv", "--", address], environment: proxy.environment, log: report)
                media = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { !["json", "srt", "vtt", "part", "ytdl"].contains($0.pathExtension) && $0.lastPathComponent.hasPrefix("media.") }
            }
        } else if let local, !forced {
            progress("检查外挂 / 内嵌字幕…")
            // Only reuse sidecars whose language is explicit; unlabelled files may be translations.
            let sidecarLanguage = Self.normalizedLanguage(language)
            for ext in sidecarLanguage.map({ ["\($0).srt", "\($0).vtt"] }) ?? [] {
                let sub = local.deletingPathExtension().appendingPathExtension(ext)
                if let text = try? String(contentsOf: sub, encoding: .utf8) { segments = SubtitleParser.parse(text); if !segments.isEmpty { method = "本地外挂字幕"; break } }
            }
            if segments.isEmpty {
                let ffprobe = try ToolPaths.tool("ffprobe")
                let output = try await runner.run(ffprobe, ["-v", "error", "-show_entries", "stream=index,codec_name,codec_type:stream_tags=language", "-of", "json", local.path], log: report)
                if let data = output.data(using: .utf8), let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let streams = info["streams"] as? [[String: Any]] {
                    let textCodecs = ["subrip", "ass", "ssa", "webvtt", "mov_text", "text"]
                    let audioLanguage = streams.first { $0["codec_type"] as? String == "audio" }.flatMap { ($0["tags"] as? [String: String])?["language"] }.flatMap { Self.normalizedLanguage($0) }
                    let target = language == "auto" ? audioLanguage : Self.normalizedLanguage(language)
                    let textStreams = streams.filter { textCodecs.contains($0["codec_name"] as? String ?? "") }
                    let ordered = textStreams.filter { stream in
                        if let target { return Self.normalizedLanguage((stream["tags"] as? [String: String])?["language"] ?? "") == target }
                        return false
                    }
                    for stream in ordered where textCodecs.contains(stream["codec_name"] as? String ?? "") {
                        guard let index = stream["index"] as? Int else { continue }
                        let sub = dir.appendingPathComponent("embedded.srt")
                        do {
                            _ = try await runner.run(ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", local.path, "-map", "0:\(index)", "-c:s", "srt", sub.path], log: report)
                            segments = SubtitleParser.parse(try String(contentsOf: sub, encoding: .utf8))
                            if !segments.isEmpty { method = "本地内嵌文本字幕"; break }
                        } catch is CancellationError { throw CancellationError() } catch { report("无法读取此字幕轨道，尝试下一轨道。\n") }
                    }
                }
            }
        }
        if segments.isEmpty {
            guard FileManager.default.fileExists(atPath: model) else { throw ToolError(message: "找不到转写模型。请在设置中选择 whisper.cpp 多语言 ggml .bin 模型。") }
            guard let media else { throw ToolError(message: "未找到可转写的媒体文件。") }
            progress("提取音频…")
            let wav = dir.appendingPathComponent("speech.wav")
            _ = try await runner.run(ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", media.path, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav.path], log: report)
            progress("本地转写中 · 首次加载模型可能较慢…")
            let prefix = dir.appendingPathComponent("transcription")
            _ = try await runner.run(try ToolPaths.tool("whisper-cli"), ["-m", model, "-l", language, "-f", wav.path, "-osrt", "-of", prefix.path, "-pp"], log: report)
            segments = SubtitleParser.parse(try String(contentsOf: prefix.appendingPathExtension("srt"), encoding: .utf8))
            method = "本地 Whisper · \(URL(fileURLWithPath: model).lastPathComponent)"
            try? FileManager.default.removeItem(at: wav)
        }
        guard !segments.isEmpty else { throw ToolError(message: "没有识别到有效文字。请检查音轨，或更换更大的多语言模型。") }
        var result = Transcript(title: title, source: source, method: method, segments: segments, mediaPath: media?.path)
        if mode == 0 && !keep, let media { try? FileManager.default.removeItem(at: media); result.mediaPath = nil }
        try JSONEncoder().encode(result).write(to: dir.appendingPathComponent("transcript.json"), options: .atomic)
        success = true
        return result
    }
    public static func normalizedLanguage(_ input: String) -> String? {
        let code = input.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        if ["zh", "zho", "chi"].contains(code) { return "zh" }
        if ["en", "eng"].contains(code) { return "en" }
        return nil
    }
    public static func subtitleMatches(_ url: URL, language: String) -> Bool {
        let code = url.deletingPathExtension().pathExtension
        return normalizedLanguage(code) == language
    }
}
