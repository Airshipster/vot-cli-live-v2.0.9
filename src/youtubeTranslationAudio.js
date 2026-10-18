import fs from 'node:fs';
import path from 'node:path';
import { runYouTubeTool, getYouTubeFragmentConcurrency } from './mergeVideo.js';
import { createProgress } from './progress.js';

export async function downloadTranslationAudio(url, directory, proxy, signal) {
  let progress = createProgress('Скачивание дорожки для перевода');
  const args = [
    '--ignore-config', '--no-playlist', '--progress', '--newline', '--progress-delta', '1',
    '--socket-timeout','30','--retries','3','--fragment-retries','3','--abort-on-unavailable-fragments','--concurrent-fragments',String(getYouTubeFragmentConcurrency()),
    '--progress-template', 'download:VOT_AUDIO:%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.eta)s|%(progress.status)s',
    '--js-runtimes', `node:${process.env.VOT_NODE_EXE || process.execPath}`,
    '-f', 'ba[ext=m4a]/ba', '--print', 'after_move:filepath',
    '-o', path.join(directory, 'translation-source.%(ext)s'),
  ];
  if (proxy) args.push('--proxy', proxy);
  args.push(url);
  try {
    const {stdout} = await runYouTubeTool(process.env.VOT_YTDLP_EXE || (process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp'), args, {
      diagnosticStage:'youtube.source-audio.download',
      signal,
      onRetry() { progress.fail(); progress=createProgress('Скачивание дорожки для перевода'); },
      onLine(line) {
        if (!line.startsWith('VOT_AUDIO:')) return;
        const [downloaded,total,estimate,eta,status] = line.slice('VOT_AUDIO:'.length).split('|');
        if (status === 'finished') progress.finish();
        else {
          const percent = Number(downloaded) / (Number(total) || Number(estimate)) * 100;
          progress.update(percent >= 1 ? percent : NaN, percent >= 1 ? Number(eta) : NaN);
        }
      },
    });
    const file = stdout.trim().split(/\r?\n/).filter(line => !line.startsWith('VOT_AUDIO:')).at(-1);
    if (!file || !path.resolve(file).startsWith(path.resolve(directory) + path.sep) || !fs.existsSync(file) || !fs.statSync(file).size) {
      throw new Error('Не получен файл исходной аудиодорожки YouTube.');
    }
    return file;
  } catch(error) { progress.fail(); throw error; }
}
