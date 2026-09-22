#!/bin/bash

set -euo pipefail

# Скрипт публикации текущей версии vot-cli-live на GitHub и npm.

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              Publishing vot-cli-live                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Проверяем что мы в правильной директории
if [ ! -f "package.json" ]; then
    echo "❌ Error: package.json not found. Run this script from project root."
    exit 1
fi

# Проверяем версию в package.json
VERSION=$(node -p "require('./package.json').version")
echo "📦 Current version: $VERSION"
echo ""

# Проверяем, что зависимости, lint и содержимое пакета корректны
echo "🔍 Running checks..."
npm install
npm run lint
npm pack --dry-run
echo ""

# 1. Push to GitHub
echo "📤 Step 1/3: Pushing main and release tag to GitHub..."
git push myfork main
git push myfork "v$VERSION"
echo ""

# 2. Ask about creating release on GitHub
echo "🎯 Step 2/3: GitHub Release"
echo "   You can create a release manually at:"
echo "   └─ https://github.com/fantomcheg/vot-cli-live/releases/new"
echo "   └─ Tag: v$VERSION"
echo "   └─ Description: Copy from RELEASE-NOTES-v$VERSION.md"
echo ""
read -p "   Press Enter to continue to npm publish..."
echo ""

# 3. Publish to npm
echo "📦 Step 3/3: Publishing to npm..."
echo "   └─ Package: vot-cli-live"
echo "   └─ Version: $VERSION"
echo ""

# Проверяем залогинены ли в npm
npm whoami > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚠️  You are not logged in to npm"
    echo "   Run: npm login"
    echo ""
    read -p "   Do you want to login now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        npm login
    else
        echo "❌ Skipping npm publish"
        exit 0
    fi
fi

echo ""
read -p "📦 Ready to publish to npm? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   └─ Publishing to npm..."
    npm publish
    if [ $? -eq 0 ]; then
        echo "   └─ ✅ Published to npm successfully!"
        echo ""
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║          🎉 PUBLICATION COMPLETED! 🎉                    ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""
        echo "✅ Version $VERSION published!"
        echo "📦 npm: https://www.npmjs.com/package/vot-cli-live"
        echo "🐙 GitHub: https://github.com/fantomcheg/vot-cli-live"
        echo ""
        echo "Install with: npm install -g vot-cli-live"
        echo ""
    else
        echo "   └─ ❌ npm publish failed"
        exit 1
    fi
else
    echo "❌ npm publish cancelled"
fi

echo ""
echo "🎯 Next steps:"
echo "1. Create GitHub release: https://github.com/fantomcheg/vot-cli-live/releases/new"
echo "2. Verify: npm view vot-cli-live@$VERSION version"
echo ""
