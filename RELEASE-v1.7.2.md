# 🎉 vot-cli-live v1.7.2 - Documentation Update

## 📚 Documentation Update: Troubleshooting Guide

This is a **DOCUMENTATION RELEASE** with comprehensive troubleshooting guide for all users!

## 🆕 What's New

### 📖 TROUBLESHOOTING.md (500+ lines)

Added a complete troubleshooting guide covering **all known issues** and their solutions:

#### 🔧 Version Conflicts After Update
**Problem:** After `npm install -g vot-cli-live`, `--version` shows old version

**Solution:** Conflict between system installations (`/usr/bin`, `/bin`) and nvm installations

```bash
# Find all installations
which -a vot-cli-live

# Remove old system installations
sudo rm -f /usr/bin/vot-cli-live /bin/vot-cli-live

# Clear shell cache
hash -r

# Verify
vot-cli-live --version
```

#### 🌐 ECONNRESET Network Errors
**Problem:** `AxiosError: ECONNRESET` when translating videos

**Solution:** Use proxy to bypass network restrictions

```bash
vot-cli-live --proxy="http://proxy.example.com:8080" \
  --output="." \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

#### ⏰ Timeout Issues
**Problem:** `yt-dlp timeout` or `ffmpeg timeout` errors

**Current timeouts:**
- Yandex API: **60 seconds**
- Translation retry: **5 minutes** (10 attempts × 30s)
- yt-dlp download: **10 minutes**
- ffmpeg processing: **15 minutes**

**Solution:** For very long videos (>30 min), download audio separately and merge manually

#### 🔒 3 Vulnerabilities Warning
**Problem:** `npm install` shows "3 vulnerabilities"

**Solution:** Most vulnerabilities are not critical for CLI tools. Run `npm audit` to check details.

#### 🐙 GitHub Release Creation Fails
**Problem:** `gh release create` fails with "Bad credentials"

**Solution:**
```bash
gh auth login
# Follow interactive prompts
```

Or create manually at: `https://github.com/YOUR_USERNAME/vot-cli-live/releases/new`

#### 📦 Large Git Repository (>200MB)
**Problem:** `.git` folder is huge due to accidentally committed media files

**Solution:** Clean history with `git filter-branch` (see TROUBLESHOOTING.md for full instructions)

---

## 📝 Updated README.md

Added direct link to TROUBLESHOOTING.md with quick reference to most common issues:
- ❌ Old version after update
- ❌ ECONNRESET errors
- ⏰ Timeout issues
- 🔒 npm vulnerabilities

---

## 🔗 All Issues Covered

Every problem mentioned in GitHub Issue #60 now has:
- ✅ Clear explanation
- ✅ Step-by-step solution
- ✅ Alternative approaches
- ✅ Prevention tips

---

## 📦 Installation

```bash
npm install -g vot-cli-live
```

If you see old version after install, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

---

## 🙏 Credits

- **Original vot-cli:** [@ToilOfficial](https://github.com/ilyhalight) (Ilya) - Вся слава Илье!
- **Fork maintainer:** [@fantomcheg](https://github.com/fantomcheg)
- **This release:** Documentation improvements

---

## 📚 Full Documentation

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Complete troubleshooting guide
- [IMPROVEMENTS.md](./IMPROVEMENTS.md) - Technical details (v1.7.0)
- [UI-IMPROVEMENTS.md](./UI-IMPROVEMENTS.md) - UI/UX documentation (v1.7.0)
- [changelog.md](./changelog.md) - Version history

---

## 🔗 Links

- 📦 **npm:** https://www.npmjs.com/package/vot-cli-live
- 🐙 **GitHub:** https://github.com/fantomcheg/vot-cli-live
- 📚 **Wiki:** https://github.com/fantomcheg/vot-cli-live/wiki
- 🐛 **Issues:** https://github.com/fantomcheg/vot-cli-live/issues

---

**Need help?** Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) first! 🔧
