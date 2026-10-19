import fs from 'node:fs';
import path from 'node:path';
import { createProgress } from './progress.js';
import { diagnostic } from './diagnostics.js';

function containsIdr(bytes) {
  for (let i = 0; i < bytes.length - 4; i++) {
    if (bytes[i] === 0 && bytes[i + 1] === 0 &&
        (bytes[i + 2] === 1 || (bytes[i + 2] === 0 && bytes[i + 3] === 1))) {
      const offset = bytes[i + 2] === 1 ? 3 : 4;
      if ((bytes[i + offset] & 31) === 5) return true;
    }
  }
  return false;
}

export async function prepareThumbnailVideo(videoPath, thumbnailPath, metadata, tools) {
  const {run, ffmpeg, ffprobe, directory = path.dirname(videoPath)} = tools;
  const video = metadata.streams.find(stream => stream.codec_type === 'video');
  if (video.codec_name !== 'h264') return null;
  if (Math.abs(Number(video.start_time) || 0) > 0.0001) return null;
  const duration = Number(video.duration) || Number(metadata.format.duration);
  const timeBase = /^1\/(\d+)$/.exec(video.time_base || '');
  if (!timeBase || !(duration > 0)) return null;
  const folder = fs.mkdtempSync(path.join(directory, 'cover-'));
  const names = ['boundary.h264','head.mp4','tail.mp4','join.ffconcat'];
  const file = name => path.join(folder, name);
  const cleanup = () => {
    for (const name of names) if (fs.existsSync(file(name))) fs.unlinkSync(file(name));
    fs.rmdirSync(folder);
  };
  const progress = createProgress('Обложка: обработка начального фрагмента');
  progress.update(NaN);
  try {
    const {stdout} = await run(ffprobe, ['-v','error','-select_streams','v:0','-read_intervals','%+31',
      '-show_packets','-show_entries','packet=pts_time,flags','-of','json',videoPath],
    {diagnosticStage:'media.thumbnail.inspect',timeout:60_000});
    const keys = JSON.parse(stdout).packets.filter(packet => packet.flags?.includes('K'))
      .map(packet => Number(packet.pts_time)).filter(value => value > 0 && value <= 30).sort((a,b) => a-b);
    let cut;
    for (const candidate of keys) {
      await run(ffmpeg, ['-hide_banner','-v','error','-nostdin','-ss',String(candidate),'-i',videoPath,
        '-map','0:v:0','-an','-c:v','copy','-frames:v','1','-bsf:v','h264_mp4toannexb','-f','h264','-y',file('boundary.h264')],
      {diagnosticStage:'media.thumbnail.boundary',timeout:60_000});
      if (containsIdr(fs.readFileSync(file('boundary.h264')))) { cut = candidate; break; }
    }
    if (cut === undefined && duration > 30) throw new Error('Не найден безопасный ключевой кадр в начале. Обложка не вставлена: полное пережатие видео автоматически не выполняется.');
    const openingDuration = cut ?? duration;
    const sar = /^\d+:\d+$/.test(video.sample_aspect_ratio || '') ? video.sample_aspect_ratio.replace(':','/') : '1';
    const filter = `[1:v]scale=${video.width}:${video.height}:force_original_aspect_ratio=decrease:force_divisible_by=2,` +
      `pad=${video.width}:${video.height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=${sar}[cover];` +
      "[0:v][cover]overlay=0:0:enable='eq(n,0)':eof_action=repeat:format=auto[v]";
    const args = ['-hide_banner','-v','warning','-nostdin','-i',videoPath,'-i',thumbnailPath,
      '-filter_complex',filter,'-map','[v]','-an','-t',String(openingDuration),'-c:v','libx264',
      '-preset','slow','-crf','14','-bf',String(Math.min(2,Number(video.has_b_frames) || 0)),
      '-pix_fmt',video.pix_fmt || 'yuv420p','-fps_mode','passthrough',
      '-enc_time_base',video.time_base,'-video_track_timescale',timeBase[1]];
    for (const [option,value] of [['-color_primaries',video.color_primaries],['-color_trc',video.color_transfer],
      ['-colorspace',video.color_space],['-color_range',video.color_range]]) {
      if (value && value !== 'unknown' && value !== 'reserved') args.push(option,value);
    }
    args.push('-y',file('head.mp4'));
    await run(ffmpeg,args,{diagnosticStage:'media.thumbnail.encode-opening',timeout:600_000});
    let inputArgs = ['-i',file('head.mp4')];
    if (cut !== undefined) {
      await run(ffmpeg, ['-hide_banner','-v','warning','-nostdin','-ss',String(cut),'-i',videoPath,
        '-map','0:v:0','-an','-c:v','copy','-video_track_timescale',timeBase[1],'-avoid_negative_ts','disabled','-y',file('tail.mp4')],
      {diagnosticStage:'media.thumbnail.copy-remainder',timeout:0});
      const {stdout:tailJson} = await run(ffprobe, ['-v','error','-select_streams','v:0','-read_intervals','%+#1',
        '-show_packets','-show_entries','packet=pts_time,flags','-of','json',file('tail.mp4')],{timeout:60_000});
      const first = JSON.parse(tailJson).packets?.[0];
      if (!first?.flags?.includes('K') || Math.abs(Number(first.pts_time)) > 2 / Number(timeBase[1])) {
        throw new Error('Не удалось точно отделить исходный ключевой кадр. Склейка отменена без изменения исходника.');
      }
      fs.writeFileSync(file('join.ffconcat'),`ffconcat version 1.0\nfile head.mp4\nduration ${cut}\nfile tail.mp4\n`);
      inputArgs = ['-f','concat','-safe','1','-auto_convert','1','-i',file('join.ffconcat')];
    }
    diagnostic('media.thumbnail.prepared',{codec:'h264',openingSeconds:openingDuration,qualityCrf:14,remainderCopied:cut !== undefined});
    progress.finish();
    if (!process.env.VOT_CLI_QUIET) console.log(`Обложка: обработано начало ${openingDuration.toFixed(3)} с; ${cut === undefined ? 'ролик помещается в один начальный фрагмент' : 'остальная видеодорожка копируется без пережатия'}.`);
    return {inputArgs,cut:openingDuration,cleanup};
  } catch (error) {
    progress.fail();
    cleanup();
    throw error;
  }
}
