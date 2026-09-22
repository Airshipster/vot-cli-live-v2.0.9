# 🔧 Устранение проблем / Troubleshooting

## Проблема: живые голоса не запускаются или возвращают HTTP 400/status 7

Начиная с версии 2.0 живые голоса используют актуальный клиент `vot.js` и
требуют Yandex OAuth-токен. Они доступны только для перевода `en → ru`.

Рекомендуемый запуск:

```bash
export YANDEX_OAUTH_TOKEN="ваш-токен"
vot-cli-live --voice-style=live --lang=en --reslang=ru "URL"
```

Токен можно получить по
[официальной инструкции Яндекс ID](https://yandex.ru/dev/id/doc/ru/tokens/debug-token).
Не помещайте токен в репозиторий, логи или скриншоты. Если токена нет, выберите
обычный голос явно:

```bash
vot-cli-live --voice-style=tts "URL"
```

Если новый перевод готовится дольше стандартного часа:

```bash
vot-cli-live --translation-timeout=7200 "URL"
```

---

## Проблема: `--version` показывает старую версию после обновления

### Симптомы
```bash
npm install -g vot-cli-live
# added 108 packages

vot-cli-live --version
# vot-cli 1.6.2  ← старая версия!

npm list -g vot-cli-live
# vot-cli-live@1.7.1  ← но npm показывает новую!
```

### Причина
В системе могут остаться старые установки пакета в нескольких местах:
- `/usr/bin/vot-cli-live` (системная установка)
- `/bin/vot-cli-live` (системная установка)
- `~/.nvm/versions/node/vX.X.X/bin/vot-cli-live` (nvm установка)

Shell использует первую найденную команду по `$PATH`, и старая системная установка имеет приоритет!

### Решение

#### 1. Проверьте все установки
```bash
which -a vot-cli-live
```

Если вы видите несколько путей, например:
```
/home/user/.nvm/versions/node/v20.18.2/bin/vot-cli-live  ← новая (1.7.1)
/usr/bin/vot-cli-live                                     ← старая (1.6.2)
/bin/vot-cli-live                                         ← старая (1.6.2)
```

#### 2. Удалите старые системные установки
```bash
# Проверьте что это старые версии
/usr/bin/vot-cli-live --version
/bin/vot-cli-live --version

# Удалите их (требуется sudo)
sudo rm -f /usr/bin/vot-cli-live /bin/vot-cli-live
```

#### 3. Очистите кеш shell и npm
```bash
# Очистите кеш команд shell
hash -r

# Очистите кеш npm (опционально)
npm cache clean --force

# Переустановите пакет
npm uninstall -g vot-cli-live
npm install -g vot-cli-live
```

#### 4. Проверьте версию
```bash
vot-cli-live --version
# 🎬 vot-cli 1.7.1 ✓
```

---

## Проблема: npm показывает warnings при публикации

### Симптомы
```bash
npm publish
# npm warn publish npm auto-corrected some errors in your package.json
# npm warn publish "bin" was converted to an object
```

### Причина
В `package.json` поле `"bin"` было строкой вместо объекта:
```json
"bin": "./src/index.js"  ← неправильно
```

### Решение
Используйте объект:
```json
"bin": {
  "vot-cli-live": "src/index.js"
}
```

Или используйте автоисправление npm:
```bash
npm pkg fix
```

---

## Проблема: Ошибка "ECONNRESET" при переводе видео

### Симптомы
```
AxiosError: Client network socket disconnected before secure TLS connection
code: 'ECONNRESET'
host: 'api.browser.yandex.ru'
```

### Причина
- Нестабильное интернет-соединение
- Блокировка Yandex API вашим провайдером/firewall
- Проблемы с DNS

### Решение

#### 1. Используйте прокси
```bash
vot-cli-live --proxy="http://proxy.example.com:8080" \
  --output="." \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

#### 2. Используйте прокси с авторизацией
```bash
vot-cli-live --proxy="http://user:password@proxy.example.com:8080" \
  --output="." \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

#### 3. Принудительный прокси (не запускать без прокси)
```bash
vot-cli-live --proxy="http://proxy.example.com:8080" \
  --force-proxy \
  --output="." \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

---

## Проблема: Timeout при скачивании/обработке видео

### Симптомы
```
Error: yt-dlp download timeout (600000ms exceeded)
Error: ffmpeg processing timeout (900000ms exceeded)
```

### Причина
Видео слишком длинное или медленное соединение

### Решение
Текущие таймауты:
- **yt-dlp download**: 10 минут
- **ffmpeg processing**: 15 минут
- **Yandex API**: 60 секунд
- **Translation retry**: 5 минут (10 попыток × 30 секунд)

Для длинных видео (>30 минут) эти таймауты могут быть недостаточны. Используйте:

```bash
# Сначала скачайте только аудио перевод
vot-cli-live --output="." "URL"

# Потом вручную объедините через ffmpeg с большими таймаутами
ffmpeg -i original.mp4 -i translation.mp3 \
  -filter_complex "[0:a]volume=0.3[a1];[1:a]volume=1.5[a2];[a1][a2]amix=inputs=2:duration=first[aout]" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k output.mp4
```

---

## Проблема: "The translation will take a few minutes"

### Симптомы
Перевод долго готовится (более 1 минуты)

### Причина
Yandex API готовит перевод. Это нормально для:
- Длинных видео (>10 минут)
- Первого запроса для конкретного видео
- Использования live voices (живых голосов)

### Решение
Просто подождите! У нас есть автоматический retry механизм:
- **Максимум попыток**: 10
- **Интервал между попытками**: 30 секунд
- **Максимальное время ожидания**: 5 минут

Вы увидите прогресс:
```
🎤 Translating (ID: xxx) - attempt 3/10 ⏰
   └─ ⏳ Retry 3/10 (waiting 30s)...
```

Если через 5 минут перевод не готов, попробуйте:
1. Подождать 10-15 минут и повторить команду
2. Использовать TTS вместо live voices: `--voice-style=tts`
3. Проверить доступность Yandex API через прокси

---

## Проблема: 3 уязвимости после установки

### Симптомы
```bash
npm install -g vot-cli-live
# 3 vulnerabilities (1 low, 1 moderate, 1 high)
```

### Причина
Зависимости пакета могут содержать уязвимости. Это зависит от:
- `axios`, `chalk`, `listr2`, `minimist` и других пакетов
- Транзитивных зависимостей (зависимости зависимостей)

### Решение

#### 1. Проверьте детали уязвимостей
```bash
npm audit
```

#### 2. Попробуйте исправить автоматически
```bash
npm audit fix
```

#### 3. Для критических уязвимостей
```bash
npm audit fix --force
```

**⚠️ Важно**: Большинство уязвимостей в CLI-инструментах не критичны, так как:
- Пакет не запускается как сервер
- Нет обработки пользовательского ввода из сети
- Используется локально в терминале

Если уязвимость не критична для CLI-инструмента (например, XSS или RCE через HTTP), можно игнорировать.

---

## Проблема: Не удаётся создать GitHub Release

### Симптомы
```bash
gh release create v1.7.1
# Exit code: 1
# message: "Bad credentials"
```

### Причина
`gh` CLI требует аутентификации для создания релизов

### Решение

#### 1. Аутентифицируйтесь в GitHub CLI
```bash
gh auth login
```

Выберите:
- **Where do you use GitHub?** → GitHub.com
- **Protocol?** → HTTPS
- **Authenticate?** → Login with a web browser

#### 2. Проверьте авторизацию
```bash
gh auth status
```

#### 3. Создайте релиз
```bash
gh release create v1.7.1 \
  --title "v1.7.1 - Major Update: Bug Fixes & Beautiful UI" \
  --notes-file RELEASE-v1.7.1.md
```

#### Альтернатива: Создайте через веб-интерфейс
1. Откройте https://github.com/YOUR_USERNAME/vot-cli-live/releases/new
2. Выберите тег `v1.7.1`
3. Заполните Title и Description из `RELEASE-v1.7.1.md`
4. Нажмите "Publish release"

---

## Проблема: Большой размер git репозитория (>200MB)

### Симптомы
```bash
du -sh .git
# 290M .git
```

### Причина
Тестовые видео/аудио файлы (`.mp4`, `.mp3`) были случайно закоммичены

### Решение

#### 1. Добавьте в .gitignore
```bash
echo "test/*.mp3" >> .gitignore
echo "test/*.mp4" >> .gitignore
echo "logERROR.txt" >> .gitignore
```

#### 2. Удалите из истории
```bash
git filter-branch --index-filter \
  'git rm --cached --ignore-unmatch test/*.mp3 test/*.mp4 logERROR.txt' \
  --prune-empty --tag-name-filter cat -- --all
```

#### 3. Очистите репозиторий
```bash
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

#### 4. Принудительно запушьте
```bash
git push origin --force --all
git push origin --force --tags
```

**⚠️ Внимание**: `git filter-branch` перезаписывает историю! Используйте только если уверены.

---

## Полезные команды для диагностики

```bash
# Проверка установки
which vot-cli-live
npm list -g vot-cli-live
vot-cli-live --version

# Проверка всех установок
which -a vot-cli-live

# Проверка PATH
echo $PATH

# Проверка зависимостей
npm list -g --depth=0

# Проверка кеша npm
npm cache verify

# Тест прокси
curl -x http://proxy:8080 https://api.browser.yandex.ru

# Проверка yt-dlp
yt-dlp --version

# Проверка ffmpeg
ffmpeg -version

# Тест загрузки
vot-cli-live --output="/tmp" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

---

## Нужна помощь?

1. **GitHub Issues**: https://github.com/fantomcheg/vot-cli-live/issues
2. **Original vot-cli**: https://github.com/FOSWLY/vot-cli/issues
3. **Wiki**: https://github.com/fantomcheg/vot-cli-live/wiki

При создании issue укажите:
- Версию пакета (`vot-cli-live --version`)
- Версию Node.js (`node --version`)
- ОС и версию
- Полный вывод ошибки
- Команду которую вы запускали
