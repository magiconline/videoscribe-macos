# VideoScribe for macOS

原生 SwiftUI 视频文字稿工具：输入视频网址或导入本地媒体，优先提取匹配语言的字幕，没有字幕时使用 whisper.cpp 离线转写。可导出纯文字 TXT、带起止时间戳 TXT、SRT 和 JSON。

[English](README.en.md) · [Agent 插件](https://github.com/magiconline/videoscribe-agent-plugin) · [使用指南](docs/USAGE.md) · [MCP 接口](docs/MCP.md)

## 安装与运行

公开发行包是**精简运行包**：包含 GUI、共享核心和 MCP/worker 可执行文件，不包含第三方工具或模型。与早期本机完整打包版本的依赖策略不同。

1. 准备 Apple Silicon Mac。源码最低目标为 macOS 14；当前发行构建仅在构建者使用的 Apple Silicon Mac 上验证，未验证所有系统版本或 Intel。
2. 安装命令行依赖：

   ```sh
   brew install yt-dlp ffmpeg whisper.cpp node
   ```

3. 从 [Releases](https://github.com/magiconline/videoscribe-macos/releases) 下载 `VideoScribe-macOS-arm64.zip`，解压并将 `VideoScribe.app` 放入 `/Applications` 或个人 Applications 目录。
4. 准备多语言 Whisper 模型。克隆本仓库后运行：

   ```sh
   git clone https://github.com/magiconline/videoscribe-macos.git
   cd videoscribe-macos
   ./scripts/download-model.sh
   ```

   脚本从公开的 whisper.cpp 模型分发源下载约 148 MB 的多语言 base 模型，并校验固定 SHA-256。默认保存在个人资源库的 `Application Support/VideoScribe/models`。也可在 GUI 设置里选择已有的 whisper.cpp 多语言 `.bin` 模型；`.en` 模型只适合英文。

5. 打开应用。设置中会显示工具与默认模型是否可用。

发行包为本地临时签名，尚未经过 Apple Developer 公证。如果系统阻止运行，请根据 macOS 的安全设置自行决定是否允许，或从源码构建；项目脚本不会关闭系统保护。

## 从源码构建

需要 Xcode / Swift 6 工具链、Python 3，以及上面的媒体工具。

```sh
git clone https://github.com/magiconline/videoscribe-macos.git
cd videoscribe-macos
swift test
./scripts/build-app.sh
open dist/VideoScribe.app
```

也可以直接在 Xcode 打开 `Package.swift`。`build-app.sh` 会映射构建路径、去除调试符号并执行临时签名，产物位于 `dist/VideoScribe.app`；不会复制本机 Homebrew 库、模型或个人配置。

## 基本操作

- **网址**：粘贴 http/https 视频链接，选择原声语言，点击“生成文字稿”。默认保留视频；仅需分析文字时可关闭。
- **本地文件**：选择视频或音频，或按 `Command+O`。明确选择中文/英文时可读取对应的 `filename.zh.srt`、`filename.en.srt` 或 VTT 外挂字幕，也会检查语言匹配的内嵌文本字幕。
- **重新识别**：勾选“强制本地转写”跳过已有字幕。自动模式无法确认原声语言时会转写，不静默改用其他语言字幕。
- **阅读与导出**：时间戳开关只改变预览/复制方式；导出菜单可分别选择纯文字、带时间戳、SRT、JSON。
- **网络**：每个网址任务主动读取 macOS 系统代理，按源网址应用例外规则；该任务的解析、字幕和下载沿用同一代理出口。不会修改系统代理设置。

更多说明见 [使用指南](docs/USAGE.md)。

## 架构

```text
SwiftUI GUI ─────┐
                ├── VideoScribeCore ── yt-dlp / FFmpeg / whisper.cpp
stdio MCP ──────┘       │
                    persistent jobs + independent workers
```

- `VideoScribeCore`：不依赖 SwiftUI 的处理核心、系统代理解析、字幕与导出、异步任务管理。
- `VideoScribe`：GUI，提交并查询同一套任务，自动显示 Agent 已完成的文字稿。
- `VideoScribeAgent`：本地 stdio MCP 和独立 worker；关闭聊天或 GUI 不会取消正在运行的 worker。

任务状态包括 `queued`、`running`、`completed`、`failed`、`cancelled`、`interrupted`。并行上限为 2，未完成任务上限为 16。重试会创建新任务，不等于检查点续传。

## 验证与限制

基础测试不需要联网。可用 `scripts/make-test-fixtures.sh` 生成非私人合成媒体，再按 [开发与测试](docs/DEVELOPMENT.md) 运行可选集成测试。

已在本地验证字幕处理、中英文转写、系统代理、MCP、断开重连、取消、重试和真实 Agent 调用。公开仓库不包含私人测试视频、文字稿、任务 ID 或本机验证日志，CI 的验证范围以工作流实际结果为准。

- 不保证 yt-dlp 支持的网站所有链接都能下载；登录、地区、反爬和 DRM 会影响结果。
- 不提供任意中英互译、画面 OCR、说话人区分或视频播放器。
- 机器文字稿可能有错字；请核对重要引文及专业术语。
- PAC 解析已实现，但真实 PAC 和认证代理环境未完成验证。
- 当前仅提供本地 stdio MCP，未提供远程 HTTP 服务。

## 隐私与许可证

本地语音转写不上传音频到转写服务；下载仍会访问原网站。任务与日志可能含网址和本地路径，请勿把资料库上传到 GitHub。详见 [安全与隐私](SECURITY.md)。

原创代码采用 [MIT](LICENSE)。外部工具和模型保留各自许可证，见 [第三方说明](THIRD_PARTY_NOTICES.md)。
