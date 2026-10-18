import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Public OAuth application used by upstream VOT. This is an application ID,
// not a user's token; account consent is still required on Yandex's page.
export const YANDEX_CLIENT_ID = '331eef9fe3fd4382a051897d5275170e';
export const CALLBACK = 'https://rust-server-531j.onrender.com/auth/callback';

export function parseAuthCallback(rawUrl, expectedState) {
  let url;
  try { url = new URL(rawUrl); } catch { return null; }
  if (url.origin + url.pathname !== CALLBACK) return null;
  const data = new URLSearchParams(url.hash.slice(1));
  const state = data.get('state') || url.searchParams.get('state');
  if (state !== expectedState) return null;
  if (data.has('error')) throw new Error('Вход в Яндекс отменён или доступ не разрешён.');
  const token = data.get('access_token');
  const expiresIn = Number(data.get('expires_in'));
  if (!token || token.length < 20 || token.length > 8192 || /\s/.test(token) || !(expiresIn > 0) || expiresIn > 10 * 366 * 86400 || !Number.isFinite(expiresIn)) return null;
  return { token, expiresAt: Date.now() + expiresIn * 1000 };
}

export function findLoginBrowser() {
  const locations = [
    [process.env.PROGRAMFILES, 'Google/Chrome/Application/chrome.exe'],
    [process.env['PROGRAMFILES(X86)'], 'Google/Chrome/Application/chrome.exe'],
    [process.env.LOCALAPPDATA, 'Google/Chrome/Application/chrome.exe'],
  ];
  return locations.filter(([root]) => root).map(([root, file]) => path.join(root, file)).find(file => fs.existsSync(file));
}

const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

export async function createLoginBridge() {
  const nonce = randomBytes(32).toString('hex');
  let credentials, expectedHost, state, authUrl, finish, fail;
  const result = new Promise((resolve, reject) => { finish = resolve; fail = reject; });
  result.catch(() => {});
  const basePath = '/vot-auth/' + nonce;
  const server = http.createServer(async (request, response) => {
    const origin = request.headers.origin;
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
    const reject = code => { response.writeHead(code); response.end('Request rejected'); };
    if (request.headers.host !== expectedHost) return reject(403);
    if (request.url === basePath + '/token' || request.url === basePath + '/import') {
      const manual = request.url.endsWith('/import');
      if (origin && origin !== 'http://' + expectedHost) return reject(403);
      if (request.method === 'OPTIONS') {
        response.setHeader('Access-Control-Allow-Methods', 'POST');
        response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        response.writeHead(204); response.end(); return;
      }
      const contentType = request.headers['content-type'] || '';
      if (request.method !== 'POST' || !(manual ? /^application\/x-www-form-urlencoded(?:;|$)/i.test(contentType) : /^application\/json(?:;|$)/i.test(contentType))) return reject(405);
      if (credentials) return reject(409);
      try {
        const chunks = []; let size = 0;
        for await (const chunk of request) {
          size += chunk.length;
          if (size > 16384) { response.writeHead(413); response.end(); return; }
          chunks.push(chunk);
        }
        const body = Buffer.concat(chunks).toString('utf8');
        const payload = manual ? null : JSON.parse(body);
        if (!manual && payload.state !== state) return reject(403);
        const callback = manual ? new URLSearchParams(body).get('callbackUrl') : CALLBACK + '#' + new URLSearchParams({state:payload.state, access_token:payload.token || '', expires_in:String(payload.expiresIn)});
        const parsed = parseAuthCallback(callback, state);
        if (!parsed) return reject(400);
        credentials = parsed;
        if (manual) { response.writeHead(303, {Location:basePath + '/complete'}); response.end(); }
        else { response.writeHead(200, {'Content-Type':'application/json'}); response.end('{"ok":true}'); }
        finish(credentials);
      } catch { if (!response.headersSent) reject(400); }
      return;
    }
    if (request.method !== 'GET' || (request.url !== basePath && request.url !== basePath + '/complete')) return reject(404);
    if (request.url.endsWith('/complete') && !credentials) return reject(404);
    const complete = request.url.endsWith('/complete');
    response.writeHead(200, {'Content-Type':'text/html; charset=utf-8'});
    response.end(`<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>VOT — вход в основном Chrome</title><style>body{font:18px/1.5 system-ui;max-width:760px;margin:60px auto;padding:0 24px;color:#20252b}a,button,input{font:inherit}a,button{display:inline-block;padding:12px 18px;background:#2464b7;color:white;border:0;border-radius:8px;text-decoration:none}input{display:block;box-sizing:border-box;width:100%;padding:12px;margin:12px 0}</style></head><body><h1>VOT — вход в основном Chrome</h1>${complete ? '<p>Доступ передан программе VOT. Проверьте сообщение «Вход в Яндекс сохранён» в PowerShell. Эту вкладку можно закрыть.</p>' : `<p>Используется текущая сессия Chrome. Дополнительные расширения не нужны.</p><p><a id="auth-link" target="_blank" rel="noopener noreferrer" href="${escapeHtml(authUrl)}">Продолжить вход Яндекса</a></p><p>После подтверждения Яндекс вернёт результат на сайт Text To Morse. Для передачи результата программе используется эта локальная страница.</p><form method="post" action="${basePath}/import" autocomplete="off"><label for="callbackUrl">Ссылка с результатом входа</label><input id="callbackUrl" name="callbackUrl" type="password" autocomplete="off" required><button type="submit">Сохранить вход в VOT</button></form><p>Ссылка должна относиться к текущему запросу входа. Не отправляйте её в чат. При управлении Chrome через Codex результат передаётся сюда локально.</p>`}</body></html>`);
  });
  server.requestTimeout = 15000;
  server.setTimeout(5000, socket => socket.destroy());
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  expectedHost = '127.0.0.1:' + port;
  state = `vot-cli.${port}.${nonce}`;
  authUrl = 'https://oauth.yandex.ru/authorize?' + new URLSearchParams({response_type:'token', client_id:YANDEX_CLIENT_ID, state});
  return {
    url:'http://' + expectedHost + basePath, state, authUrl, result,
    cancel: () => fail(new Error('Вход отменён.')),
    close: () => new Promise(resolve => server.close(resolve)),
  };
}

export async function loginYandex({ timeoutMs = 10 * 60 * 1000, checkOnly = false } = {}) {
  const browser = findLoginBrowser();
  if (!browser) throw new Error('Для входа нужен установленный Google Chrome.');
  if (checkOnly) return {browserAvailable:true, browser:path.basename(browser), requiresAddon:false, separateProfile:false};
  const bridge = await createLoginBridge();
  let timedOut = false;
  const timeout = setTimeout(() => { timedOut = true; bridge.cancel(); }, timeoutMs);
  const stop = () => bridge.cancel();
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  const parentPid = Number(process.env.VOT_AUTH_PARENT_PID);
  const watchdog = parentPid > 0 ? setInterval(() => {
    try { process.kill(parentPid, 0); } catch (error) { if (error.code === 'ESRCH') bridge.cancel(); }
  }, 1000) : undefined;
  watchdog?.unref();
  const child = spawn(browser, [bridge.url], {windowsHide:true, stdio:'ignore'});
  child.on('error', stop);
  console.error('Открыта обычная вкладка Chrome. Дополнительные расширения не нужны.');
  console.error('VOT_LOGIN_URL=' + bridge.url);
  try {
    const account = await bridge.result;
    await new Promise(resolve => setTimeout(resolve, 2000));
    return account;
  } catch { throw new Error(timedOut ? 'Время входа истекло. Повторите пункт 3 → 1.' : 'Вход отменён.'); }
  finally {
    clearTimeout(timeout); clearInterval(watchdog);
    process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop);
    await bridge.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { console.log(JSON.stringify(await loginYandex({ checkOnly: process.argv.includes('--check-only') }))); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
