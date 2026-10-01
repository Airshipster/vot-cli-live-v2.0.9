# VOT-CLI Live 2.0

[![npm version](https://img.shields.io/npm/v/vot-cli-live)](https://www.npmjs.com/package/vot-cli-live)
[![GitHub](https://img.shields.io/github/stars/fantomcheg/vot-cli-live)](https://github.com/fantomcheg/vot-cli-live)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

CLI для получения перевода видео и субтитров через Yandex VOT. Форк сохраняет
поддержку живых голосов, JSON/quiet-режимов и сборки готового видео через
`yt-dlp` + `ffmpeg`.

Версия 2.0 переведена со старых ручных protobuf-запросов на актуальную
библиотеку [`vot.js`](https://github.com/FOSWLY/vot.js). Это исправляет ошибки
`Translation not available`, HTTP 400 и проблемы запуска новых переводов,
которые появились после изменений API Яндекса.

> Проект предназначен только для исследовательских и личных целей. Он не
> связан с Яндексом. Все права на исходные сервисы принадлежат их владельцам.

## Что важно в 2.0

- Обычный TTS работает без авторизации.
- Живые голоса требуют Yandex OAuth-токен и поддерживаются только для `en → ru`.
- Без токена CLI автоматически использует обычный TTS и показывает предупреждение.
- Старые аргументы `--output`, `--output-file` и `--voice-style` сохранены.
- Ожидание долгих переводов увеличено до 60 минут и настраивается.

## Установка

```bash
npm install -g vot-cli-live
```

Требования:

- Node.js 22.19+;
- `yt-dlp` — для определения видео и `--merge-video`;
- `ffmpeg` — только для `--merge-video`.

Установка из исходников:

```bash
git clone https://github.com/fantomcheg/vot-cli-live.git
cd vot-cli-live
npm install
npm link
```

## Быстрый старт

Обычный перевод TTS:

```bash
vot-cli-live --voice-style=tts --output=. "https://www.youtube.com/watch?v=VIDEO_ID"
```

Перевод живыми голосами:

```bash
export YANDEX_OAUTH_TOKEN="ваш-токен"
vot-cli-live --voice-style=live --output=. "https://www.youtube.com/watch?v=VIDEO_ID"
```

Токен также можно передать через `--api-token`, но переменная окружения
безопаснее: токен не попадёт в историю команд и список процессов.

Получение OAuth-токена описано в
[официальной документации Яндекс ID](https://yandex.ru/dev/id/doc/ru/tokens/debug-token).
Не публикуйте токен и не добавляйте его в Git.

## Видео с переводом

```bash
vot-cli-live \
  --output=. \
  --merge-video \
  --original-volume=0.3 \
  --translation-volume=1.5 \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

Без оригинальной дорожки:

```bash
vot-cli-live --output=. --merge-video --keep-original-audio=false "URL"
```

## Автоматизация

Только ссылка на аудио или путь к собранному видео:

```bash
vot-cli-live --quiet "URL"
```

JSON:

```bash
vot-cli-live --json "URL"
```

Несколько ссылок можно передать одной команде:

```bash
vot-cli-live --json "URL_1" "URL_2" "URL_3"
```

## Субтитры

```bash
vot-cli-live --subs --output=. --reslang=ru "URL"
vot-cli-live --subs-srt --output=. --reslang=ru "URL"
```

## Основные параметры

| Параметр | Назначение |
| --- | --- |
| `--output=<путь>` | Каталог сохранения |
| `--output-file=<имя>` | Имя выходного файла |
| `--lang=<код>` | Язык исходного видео, по умолчанию `en` |
| `--reslang=<код>` | Язык перевода, по умолчанию `ru` |
| `--voice-style=live\|tts` | Тип голоса |
| `--api-token=<токен>` | OAuth-токен для живых голосов |
| `--translation-timeout=<сек>` | Максимальное ожидание, по умолчанию `3600` |
| `--proxy=<URL>` | HTTP/HTTPS-прокси |
| `--merge-video` | Скачать видео и встроить перевод |
| `--keep-original-audio` | Смешать оригинал с переводом |
| `--normalize-audio` | Нормализовать итоговую дорожку |
| `--original-volume=0..2` | Громкость оригинала |
| `--translation-volume=0..2` | Громкость перевода |
| `--quiet` | Вывести только результат |
| `--json` | Структурированный JSON |
| `--subs`, `--subs-srt` | Скачать субтитры |

## Ограничения

- API Яндекса не переводит видео длиннее 4 часов. Такие видео нужно заранее
  разделить на части.
- Живые голоса доступны только для пары `en → ru` и требуют действующий OAuth.
- Доступность перевода конкретного видео определяет Яндекс.
- `--merge-video` зависит от поддержки URL установленной версией `yt-dlp`.

## Диагностика

```bash
vot-cli-live --version
node --version
yt-dlp --version
ffmpeg -version
```

Если команда показывает старую версию:

```bash
npm uninstall -g vot-cli-live
npm cache clean --force
npm install -g vot-cli-live@latest
hash -r
```

Подробности: [TROUBLESHOOTING.md](./TROUBLESHOOTING.md), история изменений:
[changelog.md](./changelog.md).

English documentation: [README-EN.md](./README-EN.md).
