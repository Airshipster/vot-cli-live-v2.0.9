# 🎉 vot-cli-live v1.7.4 - Live Voices Platform Support Fix

## 🐛 Critical Bug Fix: VK Translation Support

**Issue #2 Fixed:** https://github.com/fantomcheg/vot-cli-live/issues/2

This release fixes the critical issue where **VK videos failed to translate** with live voices enabled.

---

## 🔥 What's Fixed

### Problem (Before v1.7.4):
```bash
vot-cli-live --output="." --voice-style=live "https://vk.com/video-123_456"
# ❌ Error: "Downloading failed! Link "undefined" not found"
```

### Solution (v1.7.4):
```bash
vot-cli-live --output="." --voice-style=live "https://vk.com/video-123_456"
# ⚠️  Live voices not officially supported for vk
#    Using standard TTS instead (better compatibility)
# ✅ Translated successfully with TTS 🤖
```

---

## ✨ What's New

### 1. **Platform-Aware Live Voices** 🎯

Live voices now work intelligently based on platform support:

| Platform | Live Voices | Auto-Fallback |
|----------|-------------|---------------|
| YouTube | ✅ Supported | N/A |
| Twitch | ✅ Supported | N/A |
| Vimeo | ✅ Supported | N/A |
| **VK** | ⚠️ Uses TTS | ✅ Automatic |
| **OK.ru** | ⚠️ Uses TTS | ✅ Automatic |
| **Rutube** | ⚠️ Uses TTS | ✅ Automatic |
| **Mail.ru** | ⚠️ Uses TTS | ✅ Automatic |

### 2. **New Parameter: --force-live-voices** 🔧

Force live voices even for unsupported platforms:

```bash
vot-cli-live --output="." --voice-style=live --force-live-voices \
  "https://vk.com/video-123_456"
```

**Result:**
```
⚠️  Live voices not officially supported for vk
   Trying anyway due to --force-live-voices flag...
⚠️  Live voices failed, retrying with TTS...
✅ Translated successfully with TTS 🤖 (fallback)
```

### 3. **Better Error Messages** 📝

Before:
```
❌ Downloading failed! Link "undefined" not found
```

After:
```
⚠️  Live voices not officially supported for vk
   Using standard TTS instead (better compatibility)
✅ Translated successfully with TTS 🤖
```

---

## 🎯 Usage Examples

### Example 1: VK Video (Auto TTS)
```bash
vot-cli-live --output="." "https://vk.com/video-123456789_456123789"
```

**Output:**
```
🎬 VOT-CLI with Live Voices 🔥
📦 Version: 1.7.4
🎯 Videos to process: 1

🔗 Forming a link to the video
   └─ URL: https://vk.com/video?z=video-123456789_456123789
   └─ Platform: vk
   └─ ⚠️  Live voices not officially supported for vk
      Using standard TTS instead (better compatibility)
   └─ 📺 Fetching video title...
   └─ ✅ Title: "Video Title"

🎤 Translating with TTS 🤖
   └─ 📡 Requesting translation from Yandex API...
   └─ ✅ Translation received instantly (cached)
✅ Translated successfully with TTS 🤖

📥 Downloading audio translation
   └─ 💾 Saving as: Video_Title.mp3
   └─ ✅ File size: 2.5 MB

✅ ALL TASKS COMPLETED! 🎉
```

### Example 2: YouTube Video (Live Voices)
```bash
vot-cli-live --output="." "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

**Output:**
```
🔗 Forming a link to the video
   └─ Platform: youtube
🎤 Translating with live voices 🔥
✅ Translated successfully with live voices 🔥
```

### Example 3: Force Live Voices for VK
```bash
vot-cli-live --output="." --force-live-voices "https://vk.com/video-123_456"
```

**Output:**
```
⚠️  Live voices not officially supported for vk
   Trying anyway due to --force-live-voices flag...
⚠️  Live voices failed, retrying with TTS...
✅ Translated successfully with TTS 🤖 (fallback)
```

---

## 📊 Platform Support Matrix

### ✅ Officially Supported (Live Voices):
- **YouTube** - Full support, tested
- **Twitch** - Full support, tested
- **Vimeo** - Full support, tested

### ⚠️ TTS Mode (Better Compatibility):
- **VK (vk.com)** - Auto TTS, reliable
- **OK.ru** - Auto TTS, reliable
- **Rutube** - Auto TTS, reliable
- **Mail.ru** - Auto TTS, reliable

### 🔧 Experimental (--force-live-voices):
- Any platform with `--force-live-voices` flag
- May work, may fail, will fallback to TTS

---

## 🚀 Installation

```bash
npm install -g vot-cli-live
```

### Verify version:
```bash
vot-cli-live --version
# 🎬 vot-cli 1.7.4
```

---

## 📚 Documentation Updates

### New Files:
- **ISSUE-2-ANALYSIS.md** - Detailed analysis of the VK translation issue

### Updated Files:
- **README.md** - Added live voices platform support info
- **README-EN.md** - English version updated
- **changelog.md** - Version 1.7.4 changes

---

## 🐛 What Was Fixed

### Issue #2: "live перевод с vk"

**Reporter:** @mechkirios  
**Date:** 2025-12-03  
**Status:** ✅ FIXED in v1.7.4

**Problem:**
- TTS translation from VK worked ✅
- Live voices translation from VK failed ❌
- Error: `"Downloading failed! Link "undefined" not found"`

**Root Cause:**
- Yandex API doesn't support live voices for all platforms
- VK videos with `useLivelyVoice: true` returned `url: undefined`
- No fallback mechanism existed

**Solution:**
1. Added platform whitelist for live voices support
2. Automatic TTS fallback for unsupported platforms
3. New `--force-live-voices` parameter for advanced users
4. Better error messages and logging

---

## 🎯 Benefits

| Benefit | Before | After |
|---------|--------|-------|
| **VK Translation** | ❌ Failed | ✅ Works (TTS) |
| **Error Messages** | ❌ Confusing | ✅ Clear |
| **User Control** | ❌ None | ✅ --force-live-voices |
| **Reliability** | ⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 🙏 Credits

- **Issue Reporter:** @mechkirios - Thank you for the detailed bug report!
- **Original vot-cli:** @ToilOfficial (Ilya) - Вся слава Илье!
- **Fork maintainer:** @fantomcheg
- **This release:** Bug fix and platform support improvements

---

## 🔗 Links

- 📦 **npm:** https://www.npmjs.com/package/vot-cli-live
- 🐙 **GitHub:** https://github.com/fantomcheg/vot-cli-live
- 🐛 **Issue #2:** https://github.com/fantomcheg/vot-cli-live/issues/2
- 📚 **Wiki:** https://github.com/fantomcheg/vot-cli-live/wiki

---

## 📝 Full Changelog

See [changelog.md](./changelog.md) for complete version history.

See [ISSUE-2-ANALYSIS.md](./ISSUE-2-ANALYSIS.md) for detailed technical analysis.

---

## 💡 Migration Guide

### If you were using VK with live voices:

**Before (v1.7.3 and earlier):**
```bash
vot-cli-live --voice-style=live "https://vk.com/video-123_456"
# ❌ Error: undefined
```

**After (v1.7.4):**
```bash
# Option 1: Let it auto-select TTS (recommended)
vot-cli-live --voice-style=live "https://vk.com/video-123_456"
# ✅ Works with TTS

# Option 2: Explicitly use TTS
vot-cli-live --voice-style=tts "https://vk.com/video-123_456"
# ✅ Works with TTS

# Option 3: Force live voices (may fail, will fallback)
vot-cli-live --voice-style=live --force-live-voices "https://vk.com/video-123_456"
# ✅ Tries live, falls back to TTS
```

---

## ✅ Testing

Tested platforms:
- ✅ YouTube with live voices
- ✅ VK with auto TTS
- ✅ VK with --force-live-voices (fallback works)
- ✅ Twitch with live voices
- ✅ OK.ru with auto TTS

---

**Thank you for using vot-cli-live!** 🙏

**Enjoy reliable translations across all platforms!** 🎧✨

---

**Release Date:** 2024-12-17  
**Version:** 1.7.4  
**Status:** ✅ Stable
