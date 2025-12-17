# Release v1.7.5 - Quiet & JSON Output Modes + Translation Polling

**Release Date:** December 17, 2024

## 🎯 Overview

This release adds **machine-readable output modes** (`--quiet` and `--json`) for seamless integration with external tools and scripts, plus **automatic translation polling** for videos that require processing time.

---

## ✨ New Features

### 1. **`--quiet` Mode** (Issue #1)

Minimal output mode designed for scripts and pipes:

- **stdout**: Only the audio URL
- **stderr**: Only errors
- **No UI**: All visual elements disabled

**Use Case - mpv Integration:**
```bash
#!/usr/bin/env bash
url="$1"
vot_audio=$(vot-cli-live --quiet "$url")
mpv --fs "$url" --external-file="$vot_audio" --lavfi-complex='[aid1]volume=0.5[vol1];[aid2]volume=3dB[vol2];[vol1][vol2]amix[ao]'
```

**Use Case - Batch Processing:**
```bash
while read url; do
  audio=$(vot-cli-live --quiet "$url" 2>/dev/null)
  [ $? -eq 0 ] && echo "$url -> $audio"
done < urls.txt
```

### 2. **`--json` Mode**

Structured JSON output for programmatic processing:

```json
[
  {
    "url": "https://youtu.be/jNQXAC9IVRw",
    "platform": "youtube",
    "videoTitle": "Me_at_the_zoo",
    "success": true,
    "audioUrl": "https://vtrans.s3-private.mds.yandex.net/...",
    "error": null,
    "voiceType": "live"
  }
]
```

**Use Case - jq Processing:**
```bash
# Extract all successful audio URLs
vot-cli-live --json "$url1" "$url2" "$url3" | jq '.[] | select(.success) | .audioUrl'

# Get failed videos
vot-cli-live --json "$url1" "$url2" | jq '.[] | select(.success == false) | {url, error}'
```

### 3. **Translation Polling Mechanism**

Automatic waiting for translation completion:

- **Max attempts**: 30 (5 minutes total)
- **Interval**: 10 seconds between attempts
- **Progress display**: Shows elapsed time and attempt number
- **Works for all platforms**: Especially important for VK videos

**Before:**
```
❌ The translation will take a few minutes
(user had to manually retry)
```

**After:**
```
⏳ Translation in progress... (30s elapsed, attempt 3/30)
⏳ Translation in progress... (40s elapsed, attempt 4/30)
✅ Translation ready!
```

---

## 🐛 Bug Fixes

- Fixed UI output in quiet/json modes (listr renderer set to 'silent')
- Added `VOT_CLI_QUIET` environment variable for child modules
- Fixed exit code logic in quiet mode (returns 0 if at least one video succeeds)
- Suppressed duration logs in quiet/json modes

---

## 📊 Technical Details

### Output Mode Comparison

| Feature | Normal | `--quiet` | `--json` |
|---------|--------|-----------|----------|
| Banner | ✅ | ❌ | ❌ |
| Progress bars | ✅ | ❌ | ❌ |
| Audio URL | Console | stdout | JSON |
| Errors | Console | stderr | JSON |
| Multiple videos | UI | One URL per line | JSON array |

### Exit Codes

| Scenario | Normal | `--quiet` | `--json` |
|----------|--------|-----------|----------|
| All success | 0 | 0 | 0 |
| Partial success | 0 | 0 | 0 |
| All failed | 1 | 1 | 1 |
| Invalid args | 1 | 1 | 1 |

---

## 🎊 Use Cases

### 1. **mpv Player Integration**

Watch YouTube with translation overlay:

```bash
#!/usr/bin/env bash
url="${1:-$(xclip -o)}"
vot_audio=$(vot-cli-live --quiet "$url")
mpv --fs "$url" --external-file="$vot_audio"
```

### 2. **FreeTube External Player**

```bash
#!/usr/bin/env bash
choice=$(echo -e "play\ntranslate" | dmenu -l 2)

case $choice in
  translate)
    vot_audio=$(vot-cli-live --quiet "$1")
    mpv "$1" --external-file="$vot_audio" --lavfi-complex='[aid1]volume=0.5[vol1];[aid2]volume=3dB[vol2];[vol1][vol2]amix[ao]'
    ;;
esac
```

### 3. **Batch Processing with JSON**

```bash
#!/usr/bin/env bash
urls=(
  "https://www.youtube.com/watch?v=VIDEO1"
  "https://www.youtube.com/watch?v=VIDEO2"
  "https://www.youtube.com/watch?v=VIDEO3"
)

vot-cli-live --json "${urls[@]}" | jq -r '.[] | "\(.videoTitle): \(.audioUrl // .error)"'
```

### 4. **Python Integration**

```python
import subprocess
import json

url = "https://www.youtube.com/watch?v=VIDEO_ID"
result = subprocess.run(
    ["vot-cli-live", "--json", url],
    capture_output=True,
    text=True
)

data = json.loads(result.stdout)
for video in data:
    if video['success']:
        print(f"Audio URL: {video['audioUrl']}")
    else:
        print(f"Error: {video['error']}")
```

---

## 📝 Documentation Updates

- Added `--quiet` and `--json` to README (Russian and English)
- Updated "What's New" table with output modes
- Added use case examples for mpv, vlc, and scripting
- Updated HELP_MESSAGE with new parameters

---

## 🎯 Benefits

✅ **Easy integration** with external players (mpv, vlc, smplayer)  
✅ **Script-friendly** output (no need for grep/sed filtering)  
✅ **Automatic polling** (no manual retries needed)  
✅ **Structured data** for programmatic processing  
✅ **Closes Issue #1** - "красивый ui" problem solved

---

## 🚀 Upgrade Instructions

```bash
# Update via npm
npm update -g vot-cli-live

# Or reinstall
npm install -g vot-cli-live@latest

# Verify version
vot-cli-live --version
# Should show: 1.7.5
```

---

## 🔗 Links

- **Issue #1**: https://github.com/fantomcheg/vot-cli-live/issues/1
- **Changelog**: [changelog.md](./changelog.md)
- **Examples**: [EXAMPLES.md](./EXAMPLES.md)
- **Full Documentation**: [Wiki](https://github.com/fantomcheg/vot-cli-live/wiki)

---

## 🙏 Credits

Special thanks to [@tyusha0](https://github.com/tyusha0) for the use case examples and feature request!

---

**Full Changelog**: v1.7.4...v1.7.5
