#!/bin/bash

# 🧪 Тестовый скрипт для проверки улучшений аудио-микширования v1.7.3

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     🧪 Testing Audio Improvements v1.7.3                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Создаём тестовую директорию
TEST_DIR="./test-audio-v1.7.3"
mkdir -p "$TEST_DIR"

echo -e "${CYAN}📁 Test directory: ${TEST_DIR}${NC}"
echo ""

# Тестовое видео (короткое, 19 секунд)
TEST_URL="https://www.youtube.com/watch?v=jNQXAC9IVRw"
VIDEO_TITLE="Me_at_the_zoo"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}Test 1: С нормализацией (по умолчанию)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Command: node src/index.js --output=\"$TEST_DIR\" --merge-video \"$TEST_URL\""
echo ""

node src/index.js --output="$TEST_DIR" --merge-video "$TEST_URL"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Test 1 PASSED${NC}"
    
    # Проверяем размер файла
    if [ -f "$TEST_DIR/${VIDEO_TITLE}.mp4" ]; then
        FILE_SIZE=$(du -h "$TEST_DIR/${VIDEO_TITLE}.mp4" | cut -f1)
        echo -e "${CYAN}📦 File size: ${FILE_SIZE}${NC}"
        
        # Проверяем длительность через ffprobe
        if command -v ffprobe &> /dev/null; then
            DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEST_DIR/${VIDEO_TITLE}.mp4" 2>/dev/null)
            if [ ! -z "$DURATION" ]; then
                echo -e "${CYAN}⏱️  Duration: ${DURATION}s${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ Output file not found!${NC}"
    fi
else
    echo ""
    echo -e "${RED}❌ Test 1 FAILED${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}Test 2: Без нормализации (быстрее)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Command: node src/index.js --output=\"$TEST_DIR\" --merge-video --normalize-audio=false \"$TEST_URL\""
echo ""

# Удаляем предыдущий файл
rm -f "$TEST_DIR/${VIDEO_TITLE}.mp4"

node src/index.js --output="$TEST_DIR" --merge-video --normalize-audio=false "$TEST_URL"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Test 2 PASSED${NC}"
    
    # Проверяем размер файла
    if [ -f "$TEST_DIR/${VIDEO_TITLE}.mp4" ]; then
        FILE_SIZE=$(du -h "$TEST_DIR/${VIDEO_TITLE}.mp4" | cut -f1)
        echo -e "${CYAN}📦 File size: ${FILE_SIZE}${NC}"
    else
        echo -e "${RED}❌ Output file not found!${NC}"
    fi
else
    echo ""
    echo -e "${RED}❌ Test 2 FAILED${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}Test 3: Кастомные громкости${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Command: node src/index.js --output=\"$TEST_DIR\" --merge-video --original-volume=0.1 --translation-volume=1.5 \"$TEST_URL\""
echo ""

# Удаляем предыдущий файл
rm -f "$TEST_DIR/${VIDEO_TITLE}.mp4"

node src/index.js --output="$TEST_DIR" --merge-video --original-volume=0.1 --translation-volume=1.5 "$TEST_URL"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Test 3 PASSED${NC}"
    
    # Проверяем размер файла
    if [ -f "$TEST_DIR/${VIDEO_TITLE}.mp4" ]; then
        FILE_SIZE=$(du -h "$TEST_DIR/${VIDEO_TITLE}.mp4" | cut -f1)
        echo -e "${CYAN}📦 File size: ${FILE_SIZE}${NC}"
    else
        echo -e "${RED}❌ Output file not found!${NC}"
    fi
else
    echo ""
    echo -e "${RED}❌ Test 3 FAILED${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}📊 Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Test directory: $TEST_DIR"
echo ""
echo "Generated files:"
ls -lh "$TEST_DIR"/*.mp4 2>/dev/null || echo "No files found"
echo ""
echo -e "${YELLOW}💡 Tip: Play the videos to compare audio quality!${NC}"
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ Testing Complete!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
