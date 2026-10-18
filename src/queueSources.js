import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const HOSTS = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be', 'www.youtu.be', 'youtube-nocookie.com', 'www.youtube-nocookie.com']);

export function normalizeSource(value, depth = 0) {
  if (depth > 3) throw new Error('Слишком много вложенных ссылок.');
  let text = String(value).trim().replace(/&amp;/gi, '&').replace(/[).,;!\]}>'"»]+$/, '');
  if (VIDEO_ID.test(text)) return { kind: 'video', id: text, url: `https://www.youtube.com/watch?v=${text}` };
  if (!/^https?:\/\//i.test(text)) text = 'https://' + text;
  let url;
  try { url = new URL(text); } catch { throw new Error('Не удалось разобрать ссылку.'); }
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.port || !HOSTS.has(url.hostname)) throw new Error('Нужна ссылка YouTube.');
  if (url.pathname === '/attribution_link' || url.pathname === '/redirect') {
    const nested = url.searchParams.get('u') || url.searchParams.get('q') || url.searchParams.get('url');
    if (nested) return normalizeSource(nested.startsWith('/') ? 'https://www.youtube.com' + nested : nested, depth + 1);
  }
  let id;
  if (url.hostname.endsWith('youtu.be')) id = url.pathname.slice(1).split('/')[0];
  else if (url.pathname === '/watch') id = url.searchParams.get('v');
  else id = url.pathname.match(/^\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{11})(?:\/|$)/)?.[1];
  if (id !== undefined && id !== null) {
    if (!VIDEO_ID.test(id)) throw new Error('Некорректный идентификатор видео.');
    return { kind: 'video', id, url: `https://www.youtube.com/watch?v=${id}` };
  }
  const channel = url.pathname.match(/^\/(?:@[^/]+|channel\/UC[A-Za-z0-9_-]+|c\/[^/]+|user\/[^/]+)(?:\/(?:videos|shorts|streams|featured))?\/?$/);
  if (channel) {
    const base = url.pathname.replace(/\/(?:videos|shorts|streams|featured)\/?$/, '').replace(/\/$/, '');
    return { kind: 'channel', url: 'https://www.youtube.com' + base };
  }
  if (url.pathname === '/playlist' && /^[A-Za-z0-9_-]{10,150}$/.test(url.searchParams.get('list') || '')) return { kind: 'playlist', url: 'https://www.youtube.com/playlist?list=' + url.searchParams.get('list') };
  throw new Error('Не найдены видео, канал или плейлист в ссылке.');
}

export function parseSources(input) {
  const text = String(input).replace(/\\\//g, '/').replace(/\\u0026/gi, '&');
  const sources = [], issues = [], seen = new Set();
  for (const line of text.split(/\r?\n/)) {
    const matches = [...line.matchAll(/(?:https?:\/\/[^\s<>"'\[\](),;]+|(?:www\.|m\.|music\.)?youtube\.com\/[^\s<>"'\[\](),;]+|(?:www\.)?youtu\.be\/[^\s<>"'\[\](),;]+)/gi)].map(match => match[0]);
    if (!matches.length && VIDEO_ID.test(line.trim())) matches.push(line.trim());
    if (!matches.length) {
      if (line.trim()) issues.push({ input: line.trim().slice(0, 500), reason: 'В строке не найдена ссылка YouTube.' });
      continue;
    }
    for (const candidate of matches) {
      try {
        const source = normalizeSource(candidate);
        if (!seen.has(source.url)) { seen.add(source.url); sources.push(source); }
      } catch (error) { issues.push({ input: candidate.slice(0, 500), reason: error.message }); }
    }
  }
  return { sources, issues };
}

export function readChannel(source, { executable, node = process.execPath, testLimit = 0, timeoutMs = 10 * 60 * 1000, onProgress = () => {} } = {}) {
  return new Promise((resolve, reject) => {
    const args = ['--ignore-config', '--flat-playlist', '--dump-json', '--skip-download', '--ignore-errors', '--no-progress', '--js-runtimes', 'node:' + node, '--socket-timeout', '30', '--retries', '2', '--extractor-retries', '2'];
    if (testLimit > 0) args.push('--playlist-end', String(testLimit));
    args.push('--', source.url);
    const child = spawn(executable, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const entries = [], issues = [];
    let buffer = '', errors = '', timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
    const consume = line => {
      if (!line.trim()) return;
      try {
        const entry = JSON.parse(line);
        if (!VIDEO_ID.test(entry.id || '')) return;
        const url = `https://www.youtube.com/watch?v=${entry.id}`;
        if (entry.live_status === 'is_live' || entry.live_status === 'is_upcoming') issues.push({ input: url, reason: 'Текущий или предстоящий эфир пропущен.' });
        else if (entry.availability && !['public', 'unlisted'].includes(entry.availability)) issues.push({ input: url, reason: 'Видео недоступно: ' + entry.availability });
        else entries.push({ url, id: entry.id, title: entry.title || entry.id, duration: entry.duration || 0 });
        if (entries.length % 25 === 0) onProgress(entries.length);
      } catch { issues.push({ input: source.url, reason: 'Не удалось прочитать элемент списка канала.' }); }
    };
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      buffer += chunk;
      const lines = buffer.split(/\r?\n/); buffer = lines.pop();
      for (const line of lines) consume(line);
    });
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', chunk => { errors = (errors + chunk).slice(-6000); });
    child.once('error', () => { clearTimeout(timer); reject(new Error('Не удалось запустить yt-dlp для списка канала.')); });
    child.once('close', code => {
      clearTimeout(timer); consume(buffer);
      if (timedOut) issues.push({ input: source.url, reason: 'Время получения списка истекло; список может быть неполным.' });
      else if (code !== 0 || /ERROR:/i.test(errors)) issues.push({ input: source.url, reason: (errors.trim() || 'Не удалось получить доступ к каналу.').slice(-1500) });
      if (!entries.length && !issues.length) issues.push({ input: source.url, reason: 'На канале не найдены доступные видео.' });
      resolve({ entries, issues });
    });
  });
}

export async function collectSources(input, options) {
  const parsed = parseSources(input), items = [], issues = [...parsed.issues], seen = new Set();
  for (const source of parsed.sources) {
    let entries;
    if (source.kind === 'video') entries = [{ ...source, title: source.id }];
    else {
      options.onSource?.(source);
      try { const result = await readChannel(source, options); entries = result.entries; issues.push(...result.issues); }
      catch (error) { issues.push({ input: source.url, reason: error.message }); continue; }
    }
    for (const entry of entries) if (!seen.has(entry.id)) { seen.add(entry.id); items.push({ ...entry, status: 'pending', output: '', error: '' }); }
  }
  return { items, issues };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const inputFile = process.argv[2];
    const input = fs.readFileSync(inputFile, 'utf8').replace(/^\uFEFF/, '');
    const result = process.argv.includes('--parse-only') ? parseSources(input) : await collectSources(input, {
      executable: process.env.VOT_YTDLP_EXE,
      onSource: source => console.error('Получение полного списка: ' + source.url),
      onProgress: count => console.error('Найдено роликов: ' + count),
    });
    process.stdout.write(JSON.stringify(result));
  } catch { console.error('Не удалось получить список ссылок.'); process.exitCode = 1; }
}
