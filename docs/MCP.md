# Local MCP / CLI

For packaged agent setup use [videoscribe-agent-plugin](https://github.com/magiconline/videoscribe-agent-plugin). To connect directly, launch the absolute path of `VideoScribe.app/Contents/MacOS/VideoScribeAgent` with the argument `mcp`. It communicates through newline-delimited JSON-RPC on stdio, not an HTTP port. Logs are kept away from protocol stdout.

| Tool | Required arguments | Purpose |
|---|---|---|
| `get_capabilities` | none | Check tools, default model and store |
| `submit_video` | `source` | Start a job; optional `language`, `force_transcription`, `keep_video`, `max_height`, `model_path` |
| `get_job` | `job_id` | Get persistent status; optional `include_log` |
| `list_jobs` | none | List jobs; optional `limit` |
| `cancel_job` | `job_id` | Request cancellation; poll terminal status |
| `retry_job` | `job_id` | New job from a failed/cancelled/interrupted record |
| `get_transcript` | `job_id` | Page with `offset`/`limit`; optionally filter `start_seconds`/`end_seconds` |
| `export_transcript` | `job_id`, `format` | `plain` / `timed` / `srt` / `json`; optional absolute `output_path` and `overwrite` |

`source` must be an HTTP(S) URL or absolute readable local path. Language is `auto`, `zh` or `en`; retained-video maximum height is 360, 720 or 1080. `get_transcript` accepts at most 200 segments per page. Submission is not completion: read/export only after `completed`.

Worker records persist in the application data store and are independent of MCP connection lifetime. Retry returns a different ID; it does not promise checkpoint resumption. Persisted Swift Codable date fields use seconds since 2001-01-01; use the explicit status/phase fields rather than guessing from a timestamp.

## Environment overrides

| Variable | Meaning |
|---|---|
| `VIDEOSCRIBE_DATA_DIR` | Independent job-store directory |
| `VIDEOSCRIBE_RESOURCES` | Explicit application resource root |
| `VIDEOSCRIBE_TOOL_DIR` | First directory searched for tool executables |
| `VIDEOSCRIBE_MODEL_PATH` | Explicit default model file |
| `VIDEOSCRIBE_AGENT_EXECUTABLE` | Worker path override for GUI development |

The application searches its bundled Tools directory, then standard Homebrew locations. Overrides are optional and must refer to resources you trust.

## JSON-file CLI

```sh
"/Applications/VideoScribe.app/Contents/MacOS/VideoScribeAgent" call --tool get_capabilities
```

For other tools, put arguments in a JSON file and pass `--arguments-file request.json`. This is the same implementation as MCP, not a second processing engine. Read the tool result and exit status; printing a submitted ID is not proof of a successful transcript.
