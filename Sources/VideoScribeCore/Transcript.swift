import Foundation

public struct Segment: Codable, Identifiable, Equatable {
    public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
    public var id: UUID = UUID()
    public var start: Double
    public var end: Double
    public var text: String
}
public struct Transcript: Codable, Identifiable {
    public init(title: String, source: String, method: String, segments: [Segment], mediaPath: String? = nil) { self.title = title; self.source = source; self.method = method; self.segments = segments; self.mediaPath = mediaPath }
    public var id = UUID()
    public var title: String
    public var source: String
    public var method: String
    public var date = Date()
    public var segments: [Segment]
    public var mediaPath: String?
    public var plain: String { segments.map(\.text).joined(separator: "\n") }
    public var timed: String { segments.map { "[\(Self.clock($0.start)) → \(Self.clock($0.end))] \($0.text)" }.joined(separator: "\n\n") }
    public var srt: String { segments.enumerated().map { "\($0.offset + 1)\n\(Self.clock($0.element.start, millis: true)) --> \(Self.clock($0.element.end, millis: true))\n\($0.element.text)\n" }.joined(separator: "\n") }
    public static func clock(_ seconds: Double, millis: Bool = false) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        let base = String(format: "%02d:%02d:%02d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60)
        return millis ? base + String(format: ",%03d", ms % 1000) : base
    }
}
public enum SubtitleParser {
    public static func time(_ input: String) -> Double? {
        let parts = input.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts { guard let n = Double(part) else { return nil }; total = total * 60 + n }
        return total
    }
    public static func parse(_ raw: String) -> [Segment] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var output: [Segment] = [], index = 0
        while index < lines.count {
            let timing = lines[index].components(separatedBy: "-->")
            guard timing.count == 2,
                  let start = time(timing[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let endToken = timing[1].split(whereSeparator: \.isWhitespace).first,
                  let end = time(String(endToken)), end >= start else { index += 1; continue }
            index += 1
            var text: [String] = []
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                if lines[index].contains("-->") { break }
                text.append(lines[index]); index += 1
            }
            var clean = text.joined(separator: " ").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (a,b) in [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&nbsp;"," ")] { clean = clean.replacingOccurrences(of: a, with: b) }
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if let last = output.last, last.text == clean, start <= last.end + 0.15 {
                output[output.count - 1].end = max(last.end, end)
            } else { output.append(Segment(start: start, end: end, text: clean)) }
        }
        return output
    }
}
