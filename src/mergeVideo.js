import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createProgress } from "./progress.js";

const executable = (variable, name) =>
  process.env[variable] || (process.platform === "win32" ? `${name}.exe` : name);

export async function runTool(file, args, options = {}) {
  const { onLine, ...execOptions } = options;
  return new Promise((resolve, reject) => {
    const child = execFile(file, args, {
      windowsHide: true, timeout: 600_000, maxBuffer: 16 * 1024 * 1024, encoding: "utf8",
      ...execOptions,
    }, (error, stdout, stderr) => {
      if (!error) { resolve({ stdout, stderr }); return; }
      const details = error.killed
        ? "Превышено время ожидания."
        : String(stderr || error.message).trim().slice(-1800);
      reject(new Error(`${path.basename(file)}: ${details}`));
    });
    if (!onLine) return;
    for (const stream of [child.stdout, child.stderr]) {
      let pending = "";
      stream.on("data", (chunk) => {
        pending += chunk;
        const lines = pending.split(/\r?\n|\r/);
        pending = lines.pop();
        for (const line of lines) onLine(line);
      });
      stream.on("end", () => { if (pending) onLine(pending); });
    }
  });
}

export async function downloadYouTubeVideo(videoUrl, outputDir, proxyUrl, maxHeight = 0, selectedFormat) {
  const heightFilter = maxHeight ? `[height<=${maxHeight}]` : "";
  const format = selectedFormat ||
    `bv${heightFilter}[ext=mp4]+ba[ext=m4a]/bv${heightFilter}+ba/b${heightFilter}`;
  const videoPath = path.join(outputDir, `temp_video_${Date.now()}.mp4`);
  const args = [
    "--ignore-config", "--no-playlist", "--progress", "--newline", "--progress-delta", "1", "--no-simulate",
    "--progress-template", "download:VOT_PROGRESS:%(info.format_id)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.eta)s|%(progress.fragment_index)s|%(progress.fragment_count)s|%(progress.status)s|%(info.vcodec)s",
    "--js-runtimes", `node:${process.env.VOT_NODE_EXE || process.execPath}`,
    "-f", format, "--merge-output-format", "mp4", "--remux-video", "mp4",
    "--print", "after_move:filepath", "-o", videoPath,
  ];
  if (process.env.VOT_FFMPEG_EXE) {
    args.push("--ffmpeg-location", path.dirname(process.env.VOT_FFMPEG_EXE));
  }
  if (proxyUrl) args.push("--proxy", proxyUrl);
  args.push(videoUrl);
  let progress;
  let currentFormat;
  let stdout;
  try {
    ({ stdout } = await runTool(executable("VOT_YTDLP_EXE", "yt-dlp"), args, {
      onLine(line) {
        if (!line.startsWith("VOT_PROGRESS:")) return;
        const [formatId, downloaded, total, estimate, eta, fragment, fragmentCount, status, vcodec] =
          line.slice("VOT_PROGRESS:".length).split("|");
        if (formatId !== currentFormat) {
          progress?.fail();
          currentFormat = formatId;
          progress = createProgress(vcodec === "none" ? "Скачивание оригинального звука" : "Скачивание видео");
        }
        const totalBytes = Number(total) || Number(estimate);
        const percent = totalBytes > 0 ? Number(downloaded) / totalBytes * 100
          : Number(fragmentCount) > 0 ? Number(fragment) / Number(fragmentCount) * 100 : NaN;
        if (status === "finished") progress.finish();
        else progress.update(percent, Number(eta));
      },
    }));
  } catch (error) { progress?.fail(); throw error; }
  const downloadedPath = stdout.trim().split(/\r?\n/).filter((line) => !line.startsWith("VOT_PROGRESS:")).at(-1);
  const expectedRoot = path.resolve(outputDir) + path.sep;
  if (!downloadedPath || !path.resolve(downloadedPath).startsWith(expectedRoot) ||
      !fs.existsSync(downloadedPath) || fs.statSync(downloadedPath).size === 0 ||
      !downloadedPath.toLowerCase().endsWith(".mp4")) {
    throw new Error("yt-dlp не создал законченный MP4-файл.");
  }
  return downloadedPath;
}

export async function mergeVideoWithAudio(videoPath, audioPath, outputPath, options = {}) {
  const { keepOriginalAudio = true, audioVolume = 1, translationVolume = 1, normalizeAudio = true } = options;
  const { stdout } = await runTool(executable("VOT_FFPROBE_EXE", "ffprobe"), [
    "-v", "error", "-show_entries", "format=duration:stream=codec_type,duration", "-of", "json", videoPath,
  ], { timeout: 30_000 });
  const metadata = JSON.parse(stdout);
  const duration = Number(metadata.format?.duration);
  const args = ["-hide_banner", "-nostdin", "-nostats", "-stats_period", "1", "-progress", "pipe:1", "-i", videoPath, "-i", audioPath];
  if (keepOriginalAudio) {
    if (!metadata.streams?.some((stream) => stream.codec_type === "audio")) {
      throw new Error("Не скачана оригинальная аудиодорожка.");
    }
    let filter = `[0:a:0]volume=${audioVolume}[original];` +
      `[1:a:0]volume=${translationVolume}[translation];` +
      "[original][translation]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[mixed]";
    filter += normalizeAudio
      ? ";[mixed]dynaudnorm=framelen=30:gausssize=31:maxgain=12[aout]"
      : ";[mixed]anull[aout]";
    args.push("-filter_complex", filter, "-map", "0:v:0", "-map", "[aout]");
  } else {
    args.push("-map", "0:v:0", "-map", "1:a:0", "-af", `volume=${translationVolume}`, "-shortest");
  }
  args.push("-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-y", outputPath);
  const progress = createProgress("Сведение озвучки");
  progress.update(0);
  try {
    await runTool(executable("VOT_FFMPEG_EXE", "ffmpeg"), args, {
      timeout: 900_000,
      onLine(line) {
        if (line.startsWith("out_time_us=") && duration > 0) {
          progress.update(Number(line.slice("out_time_us=".length)) / 1_000_000 / duration * 100);
        }
      },
    });
    progress.finish();
  } catch (error) { progress.fail(); throw error; }
}

export async function createVideoWithTranslation(videoUrl, audioPath, outputPath, options = {}) {
  const { proxyUrl, maxHeight = 0, videoFormat, ...mergeOptions } = options;
  let videoPath;
  try {
    if (!process.env.VOT_CLI_QUIET) console.log("Скачивание видео и оригинального звука...");
    videoPath = await downloadYouTubeVideo(videoUrl, path.dirname(outputPath), proxyUrl, maxHeight, videoFormat);
    if (!process.env.VOT_CLI_QUIET) console.log("Объединение видео с переводом...");
    await mergeVideoWithAudio(videoPath, audioPath, outputPath, mergeOptions);
    if (!process.env.VOT_CLI_QUIET) console.log(`✅ Видео с переводом сохранено: ${outputPath}`);
  } finally {
    if (videoPath && fs.existsSync(videoPath)) fs.unlinkSync(videoPath);
  }
}

export default { downloadYouTubeVideo, mergeVideoWithAudio, createVideoWithTranslation };
