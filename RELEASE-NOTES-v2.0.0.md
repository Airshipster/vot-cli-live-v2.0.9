# vot-cli-live 2.0.0

This release restores compatibility with the current Yandex VOT API.

## Highlights

- Migrated translation and subtitle requests to maintained `vot.js` 2.4.x.
- Fixed cold translation startup failures, HTTP 400 responses, and stale
  `Translation not available` results caused by the old request protocol.
- Added Yandex OAuth support for lively voices.
- Preserved `--merge-video`, audio mixing, quiet output, JSON output, and the
  existing 1.x CLI argument names.
- Increased translation polling timeout to 60 minutes and added
  `--translation-timeout`.

## Lively voices

Lively voices now require a Yandex OAuth token and work only for English to
Russian translation:

```bash
export YANDEX_OAUTH_TOKEN="your-token"
vot-cli-live --voice-style=live --lang=en --reslang=ru "URL"
```

Without a token, the CLI automatically falls back to standard TTS.

## Upgrade

```bash
npm uninstall -g vot-cli-live
npm install -g vot-cli-live@2.0.0
vot-cli-live --version
```

See `README.md` and `TROUBLESHOOTING.md` for details.
