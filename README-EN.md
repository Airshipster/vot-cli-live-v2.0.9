# VOT-CLI Live v2.1.0 for Windows

**First read the [upstream README](https://github.com/fantomcheg/vot-cli-live/blob/main/README.md).** This fork extends fantomcheg/vot-cli-live, which originates from FOSWLY/vot-cli by Toil / @ToilOfficial. See the full [Russian README](README.md) and [change summary](LOCAL-CHANGES.md).

Install PowerShell 7, download and extract this repository, then open `Start-VOT.cmd`. Missing dependencies are prepared locally. Output is a translated MP4 on the current user's Desktop; each user supplies their own account access if required.

- YouTube videos, channels, playlists and mixed batches; exclusions, duplicate removal, saved queues and resume.
- Local video selection using the Windows file picker. Translation is online; Yandex accesses the selected file through a temporary HTTPS tunnel.
- Yandex standard voices, Yandex live voices for English to Russian, Microsoft Edge neural voices. Edge mode relies on timed subtitles.
- Automatic source-language detection and supported language-pair selection.
- Best quality per video, resolution limits, H.264/MP4 preferences per frame size, optional unfiltered formats, no artificial 1080p cap.
- Gradual mode by default: fetch formats before each video, sequential fragments, 10-second intervals. Preflight mode scans the list first and processes videos one by one with four fragment streams.
- Original audio 15%, translation 100%, optional YouTube thumbnail as the first frame using `number 000` at the quality prompt.
- Single-line progress, queue totals, bounded retries and diagnostics with secret redaction.

No user credentials, sessions, private queues or downloaded media are included. Optional Yandex access is stored locally with Windows DPAPI; see [privacy notes](PRIVACY.md). The upstream OAuth application is named **Text To Morse**. This is the upstream login mechanism, not an embedded account.

External services may reject requests; gradual mode does not guarantee error-free processing. The repository URL retains `v2.0.9` from its creation; this release is **2.1.0**.
