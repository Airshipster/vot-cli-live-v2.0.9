## 🎤 VOT-CLI with Live Voices | VOT-CLI с живыми голосами

[![npm version](https://img.shields.io/npm/v/vot-cli-live)](https://www.npmjs.com/package/vot-cli-live)
[![npm downloads](https://img.shields.io/npm/dm/vot-cli-live)](https://www.npmjs.com/package/vot-cli-live)
[![GitHub stars](https://img.shields.io/github/stars/fantomcheg/vot-cli-live)](https://github.com/fantomcheg/vot-cli-live/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> ### 🔥 Форк с поддержкой живых голосов Яндекса!
> 
> Оригинальный [FOSWLY/vot-cli](https://github.com/FOSWLY/vot-cli) качал только стандартный TTS. 
> **Эта версия использует живые голоса Яндекса по умолчанию** - озвучка звучит намного естественнее и качественнее!

---

## ✨ Что нового в этом форке:

| Фича | Описание | Статус |
|------|----------|--------|
| 🎤 **Живые голоса** | Поддержка `useLivelyVoice` - более естественная озвучка от Яндекса | ✅ Работает |
| 🎚️ **Выбор типа озвучки** | Параметр `--voice-style` (live/tts) для переключения между живыми голосами и TTS | ✅ Работает |
| 📝 **Умные названия файлов** | Автоматическое именование по названию видео (например: `Rick_Astley_-_Never_Gonna_Give_You_Up.mp3`) | ✅ Работает |
| 🎬 **Объединение видео** | Параметр `--merge-video` для создания видео с встроенным переводом | ⚠️ Экспериментально |
| 🔊 **Настройка громкости** | Параметры `--translation-volume` и `--original-volume` | ✅ Работает |
| 📚 **Полная документация** | Wiki на 1200+ строк с примерами и FAQ | ✅ Готово |

---

## 🚀 Быстрый старт

### Установка:
```bash
npm install -g vot-cli-live
```

### Использование:
```bash
# Скачать только аудио перевод с живыми голосами (файл назовётся по названию видео)
vot-cli-live --output="." "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
# Результат: Rick_Astley_-_Never_Gonna_Give_You_Up.mp3

# Скачать со стандартным TTS
vot-cli-live --output="." --voice-style=tts "https://www.youtube.com/watch?v=VIDEO_ID"

# Скачать ВИДЕО с встроенным переводом (требует yt-dlp и ffmpeg)
vot-cli-live --output="." --merge-video "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
# Результат: Rick_Astley_-_Never_Gonna_Give_You_Up.mp4 (видео с переводом)

# Видео с переводом БЕЗ оригинального аудио
vot-cli-live --output="." --merge-video --keep-original-audio=false "https://www.youtube.com/watch?v=VIDEO_ID"

# Настройка громкости: тихий оригинал (30%), громкий перевод (150%)
vot-cli-live --output="." --merge-video --original-volume=0.3 --translation-volume=1.5 "https://www.youtube.com/watch?v=VIDEO_ID"
# Идеально для изучения языка: слышишь оригинал на фоне + чёткий перевод
```

---

English version: [Link](https://github.com/fantomcheg/vot-cli-live/blob/main/README-EN.md)

Небольшой скрипт, позволяющий скачать аудио перевод от Яндекса через терминал.

## 📖 Использование

> 💡 **Полная документация:** [Wiki](https://github.com/fantomcheg/vot-cli-live/wiki)  
> 💡 **Больше примеров:** [EXAMPLES.md](./EXAMPLES.md)  
> 🔧 **Устранение проблем:** [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### Примеры использования:

- `vot-cli [options] [args] <link> [link2] [link3] ...` — общий пример
- `vot-cli <link>` — получить перевод аудио по ссылке
- `vot-cli --help` — показать помощь по командам
- `vot-cli --version` — показать версию скрипта
- `vot-cli --output=<path> <link>` — получить перевод аудио по ссылке и сохранить его по указаному пути
- `vot-cli --output=<path> --reslang=en <link>` — получить перевод аудио на английский и сохранить его по указаному пути
- `vot-cli --output=<path> --voice-style=live <link>` — получить перевод с живыми голосами (по умолчанию)
- `vot-cli --output=<path> --voice-style=tts <link>` — получить перевод со стандартной озвучкой TTS
- `vot-cli --output=<path> --merge-video <link>` — скачать видео с встроенным переводом (требует yt-dlp и ffmpeg)
- `vot-cli --output=<path> --merge-video --keep-original-audio=false <link>` — видео только с переводом (без оригинального аудио)
- `vot-cli --subs --output=<path> --lang=en <link>` — получить английские субтитры к видео и сохранить их по указанному пути
- `vot-cli --output="." "https://www.youtube.com/watch?v=X98VPQCE_WI" "https://www.youtube.com/watch?v=djr8j-4fS3A&t=900s"` - пример с реальными данными

### Аргументы:

- `--output` — установить путь сохранения аудио файла перевода
- `--output-file` — установить имя файла для сохранения (требует указания пути в "--output"). Если не указано, используется название видео с YouTube
- `--lang` — установить язык исходного видео (см. [Wiki - Работа с языками](https://github.com/fantomcheg/vot-cli-live/wiki/Home#-работа-с-языками), чтобы узнать какие языки поддерживаются)
- `--reslang` — установить язык полученного аудио файла (см. [Wiki - Работа с языками](https://github.com/fantomcheg/vot-cli-live/wiki/Home#-работа-с-языками), чтобы узнать какие языки поддерживаются)
- `--voice-style` — установить тип озвучки (tts - стандартный TTS, live - живые голоса. По умолчанию: live)
  - **Примечание:** Живые голоса лучше всего работают с YouTube, Twitch, Vimeo
  - Для других платформ (VK, OK.ru) автоматически используется TTS для лучшей совместимости
- `--force-live-voices` — принудительно использовать живые голоса даже для неподдерживаемых платформ (может не работать. По умолчанию: false)
- `--merge-video` — объединить видео с аудио переводом (⚠️ экспериментально, требует yt-dlp и ffmpeg, может занять много времени)
- `--keep-original-audio` — сохранить оригинальное аудио при объединении (микшировать с переводом. По умолчанию: true)
- `--normalize-audio` — нормализовать уровни громкости для равномерного звучания (использует dynaudnorm. По умолчанию: true)
- `--translation-volume` — установить громкость перевода (0.0-2.0. По умолчанию: 1.0)
- `--original-volume` — установить громкость оригинала (0.0-2.0. По умолчанию: 1.0)
- `--proxy` — установить HTTP или HTTPS прокси в формате `[<PROTOCOL>://]<USERNAME>:<PASSWORD>@<HOST>[:<port>]`

### Опции:

- `-h`, `--help` — показать помощь по использованию
- `-v`, `--version` — показать версию скрипта
- `--subs`, `--subtitles` — получить субтитры к видео вместо аудио (язык субтитров для сохранения берется из `--reslang`)
- `--subs-srt`, `--subtitles-srt` — получить субтитры в формате `.srt` к видео вместо аудио

## 💻 Установка

### Из npm (рекомендуется):

**Версия с живыми голосами:**
```bash
npm install -g vot-cli-live
```

**Оригинальная версия (без живых голосов):**
```bash
npm install -g vot-cli
```

### Требования:
- NodeJS 18+
- yt-dlp (рекомендуется для автоматических названий файлов): `pip install yt-dlp` или `sudo apt install yt-dlp`
- ffmpeg (для `--merge-video`): `sudo apt install ffmpeg`

> 💡 **Примечание:** Без yt-dlp файлы будут называться по videoId (например: `dQw4w9WgXcQ.mp3`)

## ⚙️ Установка из исходников

1. Установите NodeJS 18+
2. Клонируйте репозиторий:

```bash
git clone https://github.com/fantomcheg/vot-cli-live.git
cd vot-cli-live
```

3. Установите зависимости:

```bash
npm install --ignore-scripts
```

4. Установите глобально:

```bash
sudo npm link
```

5. Готово! Теперь команда `vot-cli` доступна в терминале

## 📁 Полезные ссылки

1. Версия для браузера: [Ссылка](https://github.com/ilyhalight/voice-over-translation)
2. Скрипт для скачивания видео с встроенным переводом (надстройка над vot-cli):
   | OS | Оболочка | Автор | Ссылка |
   | --- | --- | --- | --- |
   | Windows | PowerShell | Dragoy | [Ссылка](https://github.com/FOSWLY/vot-cli/tree/main/scripts)
   | Unix | Fish | Musickiller | [Ссылка](https://gitlab.com/musickiller/fishy-voice-over/)
   | Linux | Bash | s-n-alexeyev | [Ссылка](https://github.com/s-n-alexeyev/yvt)
   | Cloud | Google Colab | alex2844 | [Ссылка](https://github.com/alex2844/youtube-translate)

## 🔧 Устранение проблем

Если после обновления `--version` показывает старую версию, или у вас другие проблемы - смотрите:
📖 **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - подробный гайд по решению всех известных проблем

### Основные проблемы:
- ❌ **Старая версия после обновления** → [решение](./TROUBLESHOOTING.md#проблема---version-показывает-старую-версию-после-обновления)
- ❌ **ECONNRESET ошибки** → [решение](./TROUBLESHOOTING.md#проблема-ошибка-econnreset-при-переводе-видео)
- ⏰ **Timeout при скачивании** → [решение](./TROUBLESHOOTING.md#проблема-timeout-при-скачиваниеобработке-видео)
- 🔒 **3 уязвимости при установке** → [решение](./TROUBLESHOOTING.md#проблема-3-уязвимости-после-установки)

### 📊 Что нового в последних версиях:

#### v1.7.2 (latest) - Documentation
- ✅ Добавлен **TROUBLESHOOTING.md** (500+ строк)
- ✅ Решения всех известных проблем
- ✅ Обновлён README.md

#### v1.7.0 - Major Update
- 🐛 Исправлены критические баги (timeout, ECONNRESET)
- 🎨 Красивый UI с эмоджи и прогресс-барами
- ⏰ Таймауты для всех операций (60s API, 10m yt-dlp, 15m ffmpeg)
- 📏 Автоопределение длительности видео

**Полный changelog:** [changelog.md](./changelog.md) | **Releases:** [GitHub Releases](https://github.com/fantomcheg/vot-cli-live/releases)

## ❗ Примечание

1. Оборачивайте ссылки в кавычки, дабы избежать ошибок
2. Для записи в системный раздел (например на "Диск C" в Windows) необходимы права администратора

![example btn](https://github.com/FOSWLY/vot-cli/blob/main/img/example.png "example")
