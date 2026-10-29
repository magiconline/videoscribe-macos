# VideoScribe for macOS

VideoScribe 是一款用 SwiftUI 编写的 macOS 视频文字稿工具。粘贴视频网址或导入本地文件，就能提取字幕；没有匹配语言的字幕时，会用 whisper.cpp 在本机转写。文字稿可导出为纯文字 TXT、带起止时间戳的 TXT、SRT 或 JSON。

[English](README.en.md) · [Agent 插件](https://github.com/magiconline/videoscribe-agent-plugin) · [使用指南](docs/USAGE.md) · [MCP 接口](docs/MCP.md)

## 安装与运行

发行包包含 GUI、共享核心和 MCP/worker 程序。下载工具和语音模型需要单独安装，步骤如下。

1. 需要一台 Apple Silicon Mac。源码最低支持目标是 macOS 14，发行包目前只在开发者使用的 Mac 上测试过，尚未验证其他系统版本和 Intel Mac。
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

   脚本会下载约 148 MB 的 whisper.cpp 多语言 base 模型，核对固定的 SHA-256 后，保存到个人资源库的 `Application Support/VideoScribe/models`。如果已有 whisper.cpp 多语言 `.bin` 模型，也可以在应用设置里选择它。注意，`.en` 模型只能识别英文。

5. 打开应用。设置中会显示工具与默认模型是否可用。

应用使用临时签名，尚未通过 Apple Developer 公证。如果 macOS 阻止打开，请在了解来源后通过系统安全设置决定是否允许运行，也可以自行从源码构建。项目脚本不会关闭系统保护。

## 从源码构建

需要 Xcode / Swift 6 工具链、Python 3，以及上面的媒体工具。

```sh
git clone https://github.com/magiconline/videoscribe-macos.git
cd videoscribe-macos
swift test
./scripts/build-app.sh
open dist.noindex/VideoScribe.app
```

也可以用 Xcode 打开 `Package.swift`。`build-app.sh` 会映射构建路径、去除调试符号，并给应用添加临时签名。生成的应用位于 `dist.noindex/VideoScribe.app`，其中不包含本机的 Homebrew 库、模型或个人配置。

构建目录带有 `.noindex` 后缀，避免开发副本出现在应用搜索中。日常使用时，请把应用移到 `/Applications`。

## 基本操作

- 粘贴 http/https 视频链接，选择原声语言，点击“生成文字稿”。默认保留视频；仅需分析文字时可关闭。
- 选择视频或音频，或按 `Command+O`。明确选择中文/英文时可读取对应的 `filename.zh.srt`、`filename.en.srt` 或 VTT 外挂字幕，也会检查语言匹配的内嵌文本字幕。
- 勾选“强制本地转写”跳过已有字幕。自动模式下，如果无法确认原声语言，应用会转写音频，避免误用其他语言的字幕。
- 时间戳开关只改变预览/复制方式；导出菜单可分别选择纯文字、带时间戳、SRT、JSON。
- 每个网址任务主动读取 macOS 系统代理，按源网址应用例外规则；该任务的解析、字幕和下载沿用同一代理出口。不会修改系统代理设置。

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

任务状态包括 `queued`、`running`、`completed`、`failed`、`cancelled`、`interrupted`。最多同时处理 2 个任务，最多允许 16 个任务处于未完成状态。重试会创建一个新任务，从头处理，不会从上次中断的位置续传或继续转写。

## 验证与限制

基础测试不需要联网。可用 `scripts/make-test-fixtures.sh` 生成非私人合成媒体，再按 [开发与测试](docs/DEVELOPMENT.md) 运行可选集成测试。

本地测试覆盖了字幕处理、中英文转写、系统代理、MCP 断开重连、取消和重试，也完成了真实 Agent 调用。私人测试视频、文字稿、任务 ID 和本机日志没有放进公开仓库。CI 检查了哪些内容，请以工作流和运行结果为准。

- 不保证 yt-dlp 支持的网站所有链接都能下载；登录、地区、反爬和 DRM 会影响结果。
- 不提供任意中英互译、画面 OCR、说话人区分或视频播放器。
- 机器文字稿可能有错字；请核对重要引文及专业术语。
- PAC 解析已实现，但真实 PAC 和认证代理环境未完成验证。
- 当前仅提供本地 stdio MCP，未提供远程 HTTP 服务。

## 隐私与许可证

语音转写在本机完成，不会把音频上传到转写服务。下载视频仍需访问原网站。任务记录和日志可能包含网址、本地文件路径，请勿将文字稿资料库上传到 GitHub。详见 [安全与隐私](SECURITY.md)。

原创代码采用 [MIT](LICENSE)。外部工具和模型保留各自许可证，见 [第三方说明](THIRD_PARTY_NOTICES.md)。
