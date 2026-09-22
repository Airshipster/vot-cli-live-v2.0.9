# Публикация vot-cli-live 2.0.0

## 1. Проверка

```bash
npm install
npm run lint
npm pack --dry-run
node src/index.js --version
```

Проверьте TTS и живые голоса на коротком ролике. Для живых голосов задайте
`YANDEX_OAUTH_TOKEN`; не сохраняйте токен в файлах проекта.

## 2. Git

```bash
git add -A
git commit -m "feat: restore Yandex VOT compatibility in v2.0.0"
git tag -a v2.0.0 -m "vot-cli-live 2.0.0"
git push myfork main
git push myfork v2.0.0
```

Force push для релиза не нужен.

## 3. npm

```bash
npm whoami
npm pack --dry-run
npm publish
npm view vot-cli-live@2.0.0 version
```

## 4. GitHub Release

Создайте релиз из тега `v2.0.0` и используйте текст из
`RELEASE-NOTES-v2.0.0.md`.

После публикации проверьте чистую установку:

```bash
npm uninstall -g vot-cli-live
npm install -g vot-cli-live@2.0.0
vot-cli-live --version
```
