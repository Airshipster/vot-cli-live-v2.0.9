# 🚀 Быстрый старт v1.7.3

## ✅ Что нового?

**Профессиональное аудио-микширование!** 🎚️

Теперь vot-cli-live использует улучшенный профиль ffmpeg с:
- ✅ `weights` вместо `volume` (меньше искажений)
- ✅ `dynaudnorm` (автоматическое выравнивание громкости)
- ✅ Новый параметр `--normalize-audio`

---

## 🎯 Примеры использования

### 1. Базовое использование (с нормализацией)
```bash
node src/index.js --output="." --merge-video \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

**Результат:**
- Видео с переводом
- Ровная громкость на протяжении всего видео
- Профессиональное качество звука

---

### 2. Без нормализации (быстрее)
```bash
node src/index.js --output="." --merge-video \
  --normalize-audio=false \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

**Результат:**
- Обработка на ~10% быстрее
- Громкость может скакать

---

### 3. Изучение языка (оригинал на фоне)
```bash
node src/index.js --output="." --merge-video \
  --original-volume=0.1 \
  --translation-volume=1.5 \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

**Результат:**
- Оригинал тихий (10%)
- Перевод громкий (150%)
- Громкость выровнена автоматически

---

## 🧪 Тестирование

### Автоматические тесты:
```bash
./test-audio-improvements.sh
```

### Проверка версии:
```bash
node src/index.js --version
# 🎬 vot-cli 1.7.3
```

### Проверка параметра:
```bash
node src/index.js --help | grep normalize
# --normalize-audio — Normalize audio levels...
```

---

## 📚 Документация

| Файл | Описание |
|------|----------|
| `AUDIO-IMPROVEMENTS.md` | Полная техническая документация (2000+ строк) |
| `RELEASE-v1.7.3.md` | Release notes для GitHub |
| `DEPLOYMENT-v1.7.3.md` | Инструкция по деплою |
| `IMPLEMENTATION-COMPLETE.md` | Финальный summary |

---

## 🎊 Что дальше?

1. **Протестируйте:** `./test-audio-improvements.sh`
2. **Деплой:** Следуйте `DEPLOYMENT-v1.7.3.md`
3. **Наслаждайтесь:** Профессиональным качеством звука! 🎧✨

---

**Дата:** 2024-12-17  
**Версия:** 1.7.3  
**Статус:** ✅ Готово к использованию
