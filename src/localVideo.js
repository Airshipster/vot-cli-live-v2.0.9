import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import parseArgs from 'minimist';
import { runTool, measureVideoBitrate } from './mergeVideo.js';
import { createProgress } from './progress.js';

export async function createSingleFileServer(filePath) {
  const file = fs.realpathSync(filePath);
  const stat = fs.statSync(file);
  if (!stat.isFile() || !stat.size) throw new Error('Выбранный видеофайл пуст или недоступен.');
  const route = '/' + randomBytes(24).toString('hex') + '/video.mp4';
  const server = http.createServer((request, response) => {
    if (String(request.url).split('?')[0] !== route) {
      response.writeHead(404).end(); return;
    }
    if (!['GET', 'HEAD'].includes(request.method)) {
      response.writeHead(405, { Allow: 'GET, HEAD' }).end(); return;
    }
    let start = 0;
    let end = stat.size - 1;
    const range = request.headers.range;
    if (range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (!match || (!match[1] && !match[2])) {
        response.writeHead(416, { 'Content-Range': `bytes */${stat.size}` }).end(); return;
      }
      if (match[1]) {
        start = Number(match[1]);
        if (match[2]) end = Math.min(Number(match[2]), end);
      } else {
        start = Math.max(0, stat.size - Number(match[2]));
      }
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= stat.size) {
        response.writeHead(416, { 'Content-Range': `bytes */${stat.size}` }).end(); return;
      }
    }
    const headers = {
      'Content-Type': 'video/mp4', 'Content-Length': end - start + 1,
      'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    };
    if (range) headers['Content-Range'] = `bytes ${start}-${end}/${stat.size}`;
    response.writeHead(range ? 206 : 200, headers);
    if (request.method === 'HEAD') { response.end(); return; }
    const stream = fs.createReadStream(file, { start, end });
    stream.on('error', () => response.destroy());
    response.on('close', () => stream.destroy());
    stream.pipe(response);
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 15_000;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return {
    url: `http://127.0.0.1:${server.address().port}${route}`,
    origin: `http://127.0.0.1:${server.address().port}`,
    route,
    close: () => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }),
  };
}

export async function prepareLocalVideo(filePath, outputDir, signal) {
  const source = fs.realpathSync(filePath);
  if (!fs.statSync(source).isFile()) throw new Error('Нужен видеофайл, а не папка.');
  const { stdout } = await runTool(process.env.VOT_FFPROBE_EXE || 'ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration:stream=codec_type,codec_name,duration,width,height', '-of', 'json', source,
  ], { timeout: 30_000, signal });
  const metadata = JSON.parse(stdout);
  const video = metadata.streams?.find((stream) => stream.codec_type === 'video');
  const audio = metadata.streams?.find((stream) => stream.codec_type === 'audio');
  const duration = Number(video?.duration) || Number(metadata.format?.duration);
  if (!video || !audio || !(duration > 0)) throw new Error('Файл должен содержать видео и звуковую дорожку с речью.');
  if (duration > 4 * 60 * 60) throw new Error('Яндекс не поддерживает ролики длиннее четырёх часов.');
  const prepared = path.join(outputDir, 'local-source.mp4');
  if (path.resolve(prepared) === source) throw new Error('Исходник совпал с временным файлом задания.');
  const canCopy = ['h264', 'hevc', 'av1', 'vp9', 'mpeg4', 'mpeg2video'].includes(video.codec_name);
  const args = ['-hide_banner', '-nostdin', '-nostats', '-stats_period', '1', '-progress', 'pipe:1',
    '-i', source, '-map', '0:v:0', '-map', '0:a:0', '-sn', '-dn'];
  if (canCopy) args.push('-c:v', 'copy');
  else {
    const bitrate = await measureVideoBitrate(source, duration);
    console.log('Подготовка MP4: исходный кодек требует повторного сжатия в H.264 с исходным средним битрейтом.');
    args.push('-c:v', 'libx264', '-preset', 'fast', '-b:v', String(bitrate), '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough');
  }
  args.push('-c:a', audio.codec_name === 'aac' ? 'copy' : 'aac');
  if (audio.codec_name !== 'aac') args.push('-b:a', '192k');
  args.push('-movflags', '+faststart', '-y', prepared);
  const progress = createProgress('Подготовка локального видео');
  progress.update(0);
  try {
    await runTool(process.env.VOT_FFMPEG_EXE || 'ffmpeg', args, {
      signal,
      timeout: Math.min(2_147_483_647, Math.ceil(Math.max(900_000, duration * 10_000))),
      onLine(line) { if (line.startsWith('out_time_us=')) progress.update(Number(line.slice(12)) / 1e6 / duration * 100); },
    });
    progress.finish();
  } catch (error) { progress.fail(); throw error; }
  return { path: prepared, mergePath: canCopy ? source : prepared, duration };
}

export async function startPublicTunnel(fileServer, signal) {
  const exe = process.env.VOT_CLOUDFLARED_EXE;
  if (!exe || !fs.existsSync(exe)) throw new Error('Не подготовлен Cloudflare Tunnel для локального видео.');
  const child = spawn(exe, ['tunnel', '--no-autoupdate', '--url', fileServer.origin, '--protocol', 'http2', '--edge-ip-version', '4'], {
    windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let details = '';
  let url;
  let ready = false;
  let exited = false;
  let spawnError;
  child.on('error', (error) => { spawnError = error; });
  child.on('exit', () => { exited = true; });
  for (const stream of [child.stdout, child.stderr]) stream.on('data', (chunk) => {
    details = (details + chunk).slice(-12_000);
    url ||= /https:\/\/[a-z0-9-]+\.trycloudflare\.com/.exec(details)?.[0];
    ready ||= details.includes('Registered tunnel connection');
  });
  const close = async () => {
    if (exited) return;
    const ended = new Promise((resolve) => child.once('exit', resolve));
    child.kill();
    await Promise.race([ended, new Promise((resolve) => setTimeout(resolve, 3000))]);
  };
  const deadline = Date.now() + 120_000;
  const progress = createProgress('Временная ссылка для Яндекса');
  progress.update(NaN);
  try {
    while (!(url && ready)) {
      signal?.throwIfAborted();
      if (spawnError || exited) throw new Error(`Не удалось запустить временную ссылку. ${spawnError?.message || details.slice(-1500)}`);
      if (Date.now() >= deadline) throw new Error('Cloudflare не создал временную ссылку за две минуты. Проверьте интернет.');
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    const publicUrl = url + fileServer.route;
    let lastHealth = '';
    const healthDeadline = Date.now() + 90_000;
    while (Date.now() < healthDeadline) {
      signal?.throwIfAborted();
      if (exited) throw new Error('Временная ссылка закрылась до начала перевода.');
      try {
        const response = await fetch(publicUrl, { method: 'HEAD', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(8000)]) : AbortSignal.timeout(8000) });
        if (response.ok) { progress.finish(); return { url: publicUrl, close }; }
        lastHealth = `HTTP ${response.status}`;
        if ([401, 403, 429].includes(response.status)) throw new Error(`TEMP_ACCESS_DENIED: HTTP ${response.status}`);
      } catch (error) {
        if (signal?.aborted || error.message.includes('TEMP_ACCESS_DENIED')) throw error;
        lastHealth = error.cause?.code || error.message;
      }
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
    throw new Error(`Созданная ссылка недоступна из интернета (${lastHealth}). Яндекс не сможет получить видео.`);
  } catch (error) { progress.fail(); await close(); throw error; }
}

async function main() {
  const argv = parseArgs(process.argv.slice(2), { string: ['source', 'output'] });
  if (!argv.source || !argv.output) throw new Error('Укажите выбранный файл и временную папку задания.');
  let fileServer;
  let tunnel;
  let cli;
  let stopped = false;
  const cancellation = new AbortController();
  const stop = () => { stopped = true; cancellation.abort(); cli?.kill(); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  const parentPid = Number(process.env.VOT_PARENT_PID);
  const watchdog = parentPid > 0 ? setInterval(() => {
    try { process.kill(parentPid, 0); }
    catch (error) { if (error.code === 'ESRCH') { stop(); process.kill(process.pid, 'SIGTERM'); } }
  }, 5000) : undefined;
  watchdog?.unref();
  try {
    const video = await prepareLocalVideo(argv.source, argv.output, cancellation.signal);
    if (stopped) return 130;
    fileServer = await createSingleFileServer(video.path);
    console.log('Для облачного перевода временно доступен только выбранный ролик. Доступ закроется после задания.');
    tunnel = await startPublicTunnel(fileServer, cancellation.signal);
    if (stopped) return 130;
    const args = process.argv.slice(2).filter((arg) => !arg.startsWith('--source=') && !arg.startsWith('--output=') && !arg.startsWith('--video-duration='));
    args.push('--output=' + argv.output, '--video-duration=' + video.duration, '--force-live-voices', tunnel.url);
    console.log('Локальный файл подготовлен. Получение перевода Яндекса…');
    const code = await new Promise((resolve, reject) => {
      cli = spawn(process.execPath, [fileURLToPath(new URL('./index.js', import.meta.url)), ...args], {
        windowsHide: true, stdio: 'inherit', env: { ...process.env, VOT_LOCAL_MEDIA_PATH: video.mergePath, VOT_LOCAL_UPLOAD_PATH: video.path },
      });
      cli.once('error', reject);
      cli.once('exit', (code) => resolve(code ?? 1));
    });
    return stopped ? 130 : code;
  } finally {
    clearInterval(watchdog);
    await tunnel?.close();
    await fileServer?.close();
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    console.log('Временный доступ к локальному видео закрыт.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { process.exitCode = await main(); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
