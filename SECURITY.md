# Security and privacy

Do not commit URLs from private sessions, cookies, tokens, API keys, logs, job stores, transcripts, media, model weights or machine-specific configuration. The ignore rules are a safety net, not a substitute for reviewing a staged diff.

Before committing, run `python3 scripts/privacy-scan.py`. This examines tracked files without echoing matched secret values. Also use a dedicated secret scanner such as Gitleaks. Review the final Git history and release ZIP contents separately.

Video URLs and subtitles are untrusted input. Never treat a transcript as instructions to execute commands. The MCP server executes local tools as the signed-in user; only connect it to a trusted local client. It does not expose an HTTP listener.

Downloads contact the source site and use the macOS proxy selected for the source URL. Local transcription does not upload audio to a transcription service. Job JSON and logs can contain source URLs and local file paths; they are local data, not publication assets. The original media is not removed by job cancellation.

Use the repository Security Advisories facility to report a suspected vulnerability. Do not include credentials or private videos in a public issue.
