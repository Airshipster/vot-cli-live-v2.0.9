# VOT-CLI Live 2.0

[![npm version](https://img.shields.io/npm/v/vot-cli-live)](https://www.npmjs.com/package/vot-cli-live)
[![GitHub](https://img.shields.io/github/stars/fantomcheg/vot-cli-live)](https://github.com/fantomcheg/vot-cli-live)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A CLI for downloading Yandex VOT translations and subtitles. This fork keeps
lively voices, quiet/JSON output, and translated video creation with `yt-dlp`
and `ffmpeg`.

Version 2.0 replaces the obsolete hand-written protobuf requests with the
current [`vot.js`](https://github.com/FOSWLY/vot.js) client. This fixes the
`Translation not available`, HTTP 400, and cold-start failures caused by recent
Yandex API changes.

> This project is intended for research and personal use only. It is not
> affiliated with Yandex.

## Important changes

- Standard TTS does not require authentication.
- Lively voices require a Yandex OAuth token and support only `en → ru`.
- Without a token, the CLI falls back to standard TTS with a warning.
- Existing `--output`, `--output-file`, and `--voice-style` scripts remain compatible.
- Translation polling now waits up to 60 minutes by default.

## Installation

```bash
npm install -g vot-cli-live
```

Requirements: Node.js 22.19+, optional `yt-dlp`, and `ffmpeg` for `--merge-video`.

From source:

```bash
git clone https://github.com/fantomcheg/vot-cli-live.git
cd vot-cli-live
npm install
npm link
```

## Quick start

Standard TTS:

```bash
vot-cli-live --voice-style=tts --output=. "https://www.youtube.com/watch?v=VIDEO_ID"
```

Lively voices:

```bash
export YANDEX_OAUTH_TOKEN="your-token"
vot-cli-live --voice-style=live --output=. "https://www.youtube.com/watch?v=VIDEO_ID"
```

You may also use `--api-token`, but an environment variable is safer because it
does not expose the token in shell history or the process list. See the
[official Yandex ID instructions](https://yandex.ru/dev/id/doc/en/tokens/debug-token)
for manual token creation. Never commit or publish your token.

## Create a translated video

```bash
vot-cli-live \
  --output=. \
  --merge-video \
  --original-volume=0.3 \
  --translation-volume=1.5 \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

To replace the original audio:

```bash
vot-cli-live --output=. --merge-video --keep-original-audio=false "URL"
```

## Automation

Plain output:

```bash
vot-cli-live --quiet "URL"
```

JSON output:

```bash
vot-cli-live --json "URL"
```

## Subtitles

```bash
vot-cli-live --subs --output=. --reslang=ru "URL"
vot-cli-live --subs-srt --output=. --reslang=ru "URL"
```

## Main options

| Option | Purpose |
| --- | --- |
| `--output=<path>` | Output directory |
| `--output-file=<name>` | Output filename |
| `--lang=<code>` | Source language, default `en` |
| `--reslang=<code>` | Translation language, default `ru` |
| `--voice-style=live\|tts` | Voice type |
| `--api-token=<token>` | OAuth token for lively voices |
| `--translation-timeout=<sec>` | Maximum wait, default `3600` |
| `--proxy=<URL>` | HTTP/HTTPS proxy |
| `--merge-video` | Download video and embed translation |
| `--keep-original-audio` | Mix original and translated audio |
| `--normalize-audio` | Normalize the mixed track |
| `--original-volume=0..2` | Original track volume |
| `--translation-volume=0..2` | Translation volume |
| `--quiet` | Print only the result |
| `--json` | Structured JSON output |
| `--subs`, `--subs-srt` | Download subtitles |

## Limitations

- Yandex does not translate videos longer than four hours; split them first.
- Lively voices are limited to `en → ru` and require a valid OAuth token.
- Yandex determines whether a particular video is available for translation.
- Video merging depends on the installed `yt-dlp` version supporting the URL.

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) and
[changelog.md](./changelog.md) for more details.
