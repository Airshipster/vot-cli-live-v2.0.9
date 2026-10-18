import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const startedAt = Date.now();
let sequence = 0;
let warned = false;

export function safeEndpoint(value) {
  try {
    const url = new URL(value);
    const endpoint = /^\/(?:video-translation|translate|vtrans|ping|stream-translation)(?:\/|$)/.test(url.pathname)
      ? '/' + url.pathname.split('/').filter(Boolean).slice(0, 2).map(part => /^[a-z-]{1,50}$/i.test(part) ? part : '[redacted]').join('/')
      : '/[redacted]';
    return `${url.protocol}//${url.hostname}${endpoint}`;
  } catch { return '[redacted-url]'; }
}

export function sanitize(value, key = '', depth = 0) {
  if (depth > 6) return '[truncated]';
  if (/token|authorization|cookie|secret|password|api.?key|credential/i.test(key)) return '[redacted]';
  if (value == null || typeof value === 'boolean' || typeof value === 'number') return value;
  if (Array.isArray(value)) return value.slice(0, 30).map(item => sanitize(item, '', depth + 1));
  if (typeof value === 'object') return Object.fromEntries(Object.entries(value).slice(0, 40).map(([name,item]) => [name,sanitize(item,name,depth + 1)]));
  let text = String(value).replace(/\x1b\[[0-9;]*m/g, '');
  for (const secret of [process.env.YANDEX_OAUTH_TOKEN,process.env.YANDEX_API_TOKEN]) {
    if (secret?.length >= 6) text = text.split(secret).join('[redacted]');
  }
  text = text.replace(/https?:\/\/[^\s<>"']+/gi, match => safeEndpoint(match));
  text = text.replace(/\b(?:Bearer|Basic)\s+[^\s,;"']+/gi, '[redacted-authorization]')
    .replace(/\b(?:access_token|refresh_token|api[_-]?key|cookie|authorization|password)\s*[=:]\s*[^\s,;]+/gi, '[redacted]')
    .replace(/\by[0-9]__[A-Za-z0-9_-]+/g, '[redacted]')
    .replace(/\b[A-Z]:[\\/]Users[\\/][^\\/\s"']+/gi, '%USERPROFILE%')
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, '[redacted-email]');
  return text.slice(0, 1800);
}

export function diagnostic(event, data = {}) {
  const file = process.env.VOT_DIAGNOSTIC_FILE;
  if (!file) return;
  try {
    fs.mkdirSync(path.dirname(file), {recursive:true});
    fs.appendFileSync(file, JSON.stringify({schema:1,ts:new Date().toISOString(),attempt:process.env.VOT_ATTEMPT_ID || null,
      pid:process.pid,seq:++sequence,elapsedMs:Date.now()-startedAt,event,...sanitize(data)}) + '\n', 'utf8');
  } catch {
    if (!warned) { warned = true; console.error('Не удалось записать диагностический журнал.'); }
  }
}

export function errorDetails(error) {
  const message = String(error?.data?.message || error?.message || error || 'Unknown error');
  const httpStatus = Number(error?.response?.status || error?.httpStatus) || Number(/HTTP(?: Error)?\s+(\d{3})/i.exec(message)?.[1]) || undefined;
  return sanitize({name:error?.name,code:error?.code,httpStatus,serviceStatus:error?.data?.status,provider:error?.provider,stage:error?.stage,message,
    cause:error?.cause ? {code:error.cause.code,message:error.cause.message} : undefined});
}

export function tracedFetch(fetchImpl) {
  let request = 0;
  return async (url, options = {}) => {
    const requestId = `http-${++request}`;
    const before = Date.now();
    const endpoint = safeEndpoint(url);
    diagnostic('http.request', {requestId,endpoint,method:options.method || 'GET',bodyBytes:options.body?.byteLength});
    try {
      const response = await fetchImpl(url, options);
      const headers = Object.fromEntries(['content-type','retry-after','x-request-id','x-yandex-request-id']
        .map(name => [name,response.headers?.get?.(name)]).filter(([,value]) => value));
      diagnostic('http.response', {requestId,endpoint,httpStatus:response.status,durationMs:Date.now()-before,headers});
      if (!response.ok) {
        await response.body?.cancel();
        const error = new Error(`HTTP ${response.status} (${endpoint})`);
        error.httpStatus = response.status;
        throw error;
      }
      return response;
    } catch(error) {
      diagnostic('http.error', {requestId,endpoint,durationMs:Date.now()-before,error:errorDetails(error)});
      throw error;
    }
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { diagnostic(process.argv[2], JSON.parse(process.env.VOT_DIAGNOSTIC_DATA || '{}')); }
  catch { console.error('Некорректная запись диагностики.'); process.exitCode=1; }
}
