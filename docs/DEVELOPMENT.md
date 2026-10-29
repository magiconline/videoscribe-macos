# Development and tests

`swift test` runs parsing, language-selection, proxy and validation tests. Media and live network tests are opt-in and skipped if their environment is absent. A green basic run is not a claim that every downloader website works.

Generate non-private synthetic fixtures:

```sh
./scripts/make-test-fixtures.sh test-fixtures
VIDEOSCRIBE_TEST_ROOT="$PWD/test-fixtures" swift test
```

English speech is generated with macOS `say` if its requested voice is installed. Chinese speech is optional: list voices with `say -v '?'`, then pass a locally available voice as `VOICE_ZH`. Missing optional speech fixtures are skipped. Generated media, transcripts, logs and model files are ignored by Git.

For a user-selected network test, set `VIDEOSCRIBE_TEST_URL` and `VIDEOSCRIBE_TEST_ROOT`. For a local HTTP video test, set `VIDEOSCRIBE_TEST_VIDEO_URL`. For actual system-proxy verification, set `VIDEOSCRIBE_EXPECTED_PROXY` to your current proxy URL; the repository contains no live proxy endpoint.

Build a minimal distributable with `scripts/build-app.sh`. Build artifacts are ignored. Do not copy the development workspace, user data store, account configuration or Homebrew installation into a release. Verify signing with `codesign --verify --deep --strict dist/VideoScribe.app`.

Before publishing:

```sh
git add Package.swift Sources Tests scripts docs README.md README.en.md LICENSE SECURITY.md THIRD_PARTY_NOTICES.md VERSION .gitignore .github
python3 scripts/privacy-scan.py
```

Use Gitleaks to inspect both the staged source and resulting commit history. Do not publish raw local test logs or screenshots containing private content. Release archives require a separate content scan.
