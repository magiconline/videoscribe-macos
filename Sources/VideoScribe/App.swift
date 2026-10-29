import VideoScribeCore
import SwiftUI

@main struct VideoScribeApp: App {
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(workspace).frame(minWidth: 980, minHeight: 680)
        }.defaultSize(width: 1180, height: 790)
        .commands { CommandGroup(replacing: .newItem) { Button("导入视频或音频…") { workspace.importMedia() }.keyboardShortcut("o") } }
        Settings { SettingsView().environmentObject(workspace) }
    }
}
struct ContentView: View {
    @EnvironmentObject var w: Workspace
    @State private var showLog = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Label("VideoScribe", systemImage: "waveform").font(.title2.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 22)
                Text("文字稿资料库").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 8)
                List(selection: $w.selected) {
                    ForEach(w.records) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).lineLimit(2).font(.body.weight(.medium))
                            Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(item.id)
                    }
                }.listStyle(.sidebar)
                Divider()
                Button { NSWorkspace.shared.open(w.root) } label: { Label("打开工作目录", systemImage: "folder") }.buttonStyle(.plain).padding(18)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 320)
        } detail: {
            VStack(spacing: 0) {
                inputSection.padding(24).background(.background)
                Divider()
                if let item = w.current {
                    transcriptSection(item)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "text.document").font(.system(size: 46, weight: .light)).foregroundStyle(.tint)
                        Text("把视频，变成可阅读的文字").font(.title2.weight(.semibold))
                        Text("粘贴网址或导入本地文件。优先提取字幕，\n没有字幕时，在这台 Mac 上离线转写。").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                        Text("支持中文、英文 · 可导出带时间戳或纯文字版本").font(.callout).foregroundStyle(.secondary).padding(.top, 4)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack(spacing: 10) {
                    if w.busy { ProgressView().controlSize(.small) } else { Image(systemName: w.status == "处理失败" ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(.secondary) }
                    Text(w.status).font(.callout).lineLimit(1)
                    Spacer()
                    Button(showLog ? "收起日志" : "处理日志") { showLog.toggle() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.vertical, 12)
                if showLog { ScrollView { Text(w.log.isEmpty ? "开始处理后在这里查看详细日志。" : w.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14) }.frame(height: 145).background(Color(nsColor: .textBackgroundColor)) }
            }
        }
        .task {
            while !Task.isCancelled {
                w.refreshCompletedJobs()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .alert("需要处理", isPresented: Binding(get: { w.errorMessage != nil }, set: { if !$0 { w.errorMessage = nil } })) { Button("好") { w.errorMessage = nil; showLog = true } } message: { Text(w.errorMessage ?? "") }
    }
    var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("新建文字稿").font(.title2.weight(.semibold))
                Spacer()
                SettingsLink { Image(systemName: "gearshape").font(.title3) }.buttonStyle(.plain).help("模型与依赖设置")
            }
            Picker("素材来源", selection: $w.sourceMode) { Text("视频网址").tag(0); Text("本地文件").tag(1) }.pickerStyle(.segmented).frame(width: 250).disabled(w.busy)
            HStack(spacing: 10) {
                if w.sourceMode == 0 {
                    TextField("粘贴视频链接，例如 https://www.youtube.com/watch?v=…", text: $w.urlText).textFieldStyle(.roundedBorder).controlSize(.large).onSubmit { w.start() }.disabled(w.busy)
                } else {
                    Button { w.importMedia() } label: {
                        HStack { Image(systemName: "film"); Text(w.localURL?.lastPathComponent ?? "选择视频或音频文件…").lineLimit(1); Spacer(); Image(systemName: "folder") }.padding(9)
                    }.disabled(w.busy)
                }
                if w.busy { Button("取消", role: .cancel) { w.cancel() }.controlSize(.large) }
                else { Button("生成文字稿") { w.start() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command) }
            }
            HStack(spacing: 18) {
                Picker("原声语言", selection: $w.language) { Text("自动检测").tag("auto"); Text("中文").tag("zh"); Text("英文").tag("en") }.frame(width: 200)
                Toggle("强制本地转写", isOn: $w.forceASR).help("跳过现成字幕，重新识别音轨")
                if w.sourceMode == 0 { Toggle("保留视频", isOn: $w.keepVideo).help("关闭后只按需下载音频，完成后清理音频") }
                Spacer(minLength: 0)
            }.font(.callout).disabled(w.busy)
        }
    }
    func transcriptSection(_ item: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled).lineLimit(2)
                HStack {
                    Text("\(item.segments.count) 段 · \(item.method)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.showTime ? item.timed : item.plain, forType: .string) } label: { Label("复制", systemImage: "doc.on.doc") }
                    Menu { Button("纯文字 TXT…") { w.export("plain") }; Button("带时间戳 TXT…") { w.export("timed") }; Button("字幕 SRT…") { w.export("srt") }; Button("分段 JSON…") { w.export("json") } } label: { Label("导出", systemImage: "square.and.arrow.up") }.fixedSize()
                }
                HStack {
                    Toggle("显示时间戳", isOn: $w.showTime).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    TextField("搜索文字", text: $w.search).textFieldStyle(.roundedBorder).frame(width: 210)
                }.font(.callout)
            }.padding(22)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(item.segments.filter { w.search.isEmpty || $0.text.localizedCaseInsensitiveContains(w.search) }) { segment in
                        HStack(alignment: .top, spacing: 18) {
                            if w.showTime {
                                Text(Transcript.clock(segment.start)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 76, alignment: .leading).padding(.top, 4)
                            }
                            Text(segment.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 13).padding(.horizontal, 24)
                        Divider().padding(.leading, w.showTime ? 118 : 24)
                    }
                }
            }.background(Color(nsColor: .textBackgroundColor))
        }
    }

}
struct SettingsView: View {
    @EnvironmentObject var w: Workspace
    var body: some View {
        Form {
            Section("本地转写") {
                Text("本地多语言 Whisper 模型可离线识别中文和英文。长视频及专业术语建议另选 small / medium 模型。")
                LabeledContent("当前模型", value: w.modelPath.isEmpty ? (FileManager.default.isReadableFile(atPath: ToolPaths.defaultModel) ? "默认 base · 多语言" : "未安装 · 请运行模型安装脚本") : URL(fileURLWithPath: w.modelPath).lastPathComponent)
                HStack { Button("选择 ggml 模型…") { w.chooseModel() }; Button("使用默认模型") { w.modelPath = ""; UserDefaults.standard.removeObject(forKey: "modelPath") } }.disabled(w.busy)
            }
            Section("视频下载") {
                Picker("最高画质", selection: $w.maxHeight) {
                    Text("360p · 节省流量").tag(360)
                    Text("720p · 推荐").tag(720)
                    Text("1080p").tag(1080)
                }.disabled(w.busy)
            }
            Section("网络") {
                Text(w.networkDescription)
                Text("网址解析、字幕获取和视频下载会主动读取并使用系统代理；系统例外列表指定的地址直连。无需在应用中重复填写代理。").font(.caption).foregroundStyle(.secondary)
            }
            Section("处理工具") {
                ForEach(["yt-dlp", "ffmpeg", "ffprobe", "whisper-cli", "node"], id: \.self) { name in
                    LabeledContent(name) { Text((try? ToolPaths.tool(name)) != nil ? "可用" : "缺失").foregroundStyle((try? ToolPaths.tool(name)) != nil ? .green : .red) }
                }
                Text("转写在本机完成；网址解析和下载需要联网。当前版本不包含中英互译。登录或受保护的视频可能无法直接下载。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 540, height: 620)
    }
}
