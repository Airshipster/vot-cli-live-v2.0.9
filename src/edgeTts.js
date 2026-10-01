import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import YandexBrowserTranslateProvider from "@toil/translate/providers/yandexbrowser";
import { runTool } from "./mergeVideo.js";
import { createProgress } from "./progress.js";

const worker = fileURLToPath(new URL("./edge_worker.py", import.meta.url));
const executable = (variable, name) => process.env[variable] || (process.platform === "win32" ? `${name}.exe` : name);
const baseLanguage = (language) => String(language || "").split("-")[0].toLowerCase();

async function getJson(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(30_000) });
  if (!response.ok) throw new Error(`HTTP ${response.status} (${new URL(url).hostname})`);
  return response.json();
}

function timedEntries(data) {
  const subtitles = Array.isArray(data) ? data : data.subtitles;
  if (Array.isArray(subtitles)) {
    return subtitles.map((entry) => ({text: String(entry.text || "").trim(), startMs: Number(entry.startMs), durationMs: Number(entry.durationMs)}))
      .filter((entry) => entry.text && Number.isFinite(entry.startMs) && entry.startMs >= 0 && Number.isFinite(entry.durationMs) && entry.durationMs > 0);
  }
  if (Array.isArray(data.events)) {
    return data.events.filter((event) => event.segs && event.dDurationMs > 0).map((event) => ({
      text: event.segs.map((segment) => segment.utf8 || "").join("").replace(/\s+/g, " ").trim(),
      startMs: Number(event.tStartMs), durationMs: Number(event.dDurationMs),
    })).filter((entry) => entry.text && Number.isFinite(entry.startMs) && entry.startMs >= 0);
  }
  return [];
}

async function translateText(entries, sourceLanguage, targetLanguage, fetchOpts) {
  const translator = new YandexBrowserTranslateProvider({fetchOpts,
    fetchFn: (url, options) => fetch(url, {...options, signal: AbortSignal.timeout(30_000)}),
  });
  if (!sourceLanguage || sourceLanguage === "auto") {
    const detected = await translator.detect(entries.slice(0, 5).map((entry) => entry.text).join(" "));
    sourceLanguage = detected.lang;
    if (!sourceLanguage) throw new Error("Не удалось определить язык субтитров.");
  }
  const translated = [];
  let cursor = 0;
  const progress = createProgress("Перевод субтитров Яндекс");
  progress.update(0);
  try {
    while (cursor < entries.length) {
      const batch = [];
      let chars = 0;
      while (cursor + batch.length < entries.length && batch.length < 40) {
        const entry = entries[cursor + batch.length];
        if (batch.length && chars + entry.text.length > 8000) break;
        batch.push(entry);
        chars += entry.text.length;
      }
      const result = await translator.translate(batch.map((entry) => entry.text), `${sourceLanguage}-${targetLanguage}`);
      if (result.error || !Array.isArray(result.translations) || result.translations.length !== batch.length ||
          result.translations.some((text) => typeof text !== "string" || !text.trim())) {
        throw new Error("Яндекс не вернул перевод субтитров для выбранной озвучки.");
      }
      translated.push(...batch.map((entry, index) => ({...entry, text: result.translations[index]})));
      cursor += batch.length;
      progress.update(cursor / entries.length * 100);
    }
    progress.finish();
    return translated;
  } catch (error) { progress.fail(); throw error; }
}

async function videoMetadata(videoUrl, metadataPath) {
  if (metadataPath) return JSON.parse(fs.readFileSync(metadataPath, "utf8").replace(/^\uFEFF/, ""));
  const {stdout} = await runTool(executable("VOT_YTDLP_EXE", "yt-dlp"), [
    "--ignore-config", "--no-playlist", "--no-progress", "--skip-download", "--dump-single-json",
    "--socket-timeout", "30", "--retries", "1", "--js-runtimes", `node:${process.env.VOT_NODE_EXE || process.execPath}`, videoUrl,
  ], {timeout: 120_000});
  return JSON.parse(stdout);
}

async function translatedSubtitles({client, videoData, videoUrl, metadataPath, metadata, sourceLanguage, targetLanguage, log}) {
  let original;
  let subtitlesError;
  try {
    const result = await client.getSubtitles({videoData, requestLang: sourceLanguage});
    const tracks = result.subtitles || [];
    for (const track of tracks) {
      const url = baseLanguage(track.translatedLanguage) === targetLanguage ? track.translatedUrl
        : baseLanguage(track.language) === targetLanguage ? track.url : null;
      if (!url) continue;
      const entries = timedEntries(await getJson(url));
      if (entries.length) { log("Субтитры на языке результата получены из VOT."); return entries; }
    }
    const source = tracks.find((track) => baseLanguage(track.language) === sourceLanguage && track.url) || tracks.find((track) => track.url);
    if (source) original = {url: source.url, language: baseLanguage(source.language)};
  } catch (error) { subtitlesError = error.message; }

  try {
    metadata ||= await videoMetadata(videoUrl, metadataPath);
    const selected = metadata.subtitles?.[targetLanguage] || metadata.automatic_captions?.[targetLanguage];
    const track = selected?.find((item) => item.ext === "json3");
    if (track?.url) {
      const entries = timedEntries(await getJson(track.url));
      if (entries.length) { log("Субтитры на языке результата получены из YouTube."); return entries; }
    }
    if (!original) {
      const detected = sourceLanguage === "auto" ? baseLanguage(metadata.language) : sourceLanguage;
      const tracks = metadata.subtitles?.[detected] || metadata.automatic_captions?.[`${detected}-orig`] || metadata.automatic_captions?.[detected];
      const source = tracks?.find((item) => item.ext === "json3");
      if (source?.url) original = {url: source.url, language: detected};
    }
  } catch (error) { subtitlesError = error.message; }
  if (original) {
    const entries = timedEntries(await getJson(original.url));
    if (entries.length) return translateText(entries, original.language || sourceLanguage, targetLanguage, client.fetchOpts);
  }
  throw new Error("Microsoft TTS нужны субтитры с временными метками. Для этого ролика получить их не удалось." + (subtitlesError ? ` ${subtitlesError}` : ""));
}

export async function createEdgeAudio(options) {
  const {outputDir, voice, targetLanguage, log} = options;
  if (!outputDir) throw new Error("Для Microsoft TTS укажите --output.");
  if (!voice || baseLanguage(voice) !== targetLanguage) throw new Error("Выберите диктора Microsoft на языке результата (--tts-voice).");
  const python = process.env.VOT_PYTHON_EXE;
  if (!python || !process.env.VOT_EDGE_PACKAGES) throw new Error("Microsoft TTS не подготовлен. Запустите Run-VOT.ps1 и выберите Microsoft.");
  if (!Number.isFinite(options.duration) || options.duration <= 0) {
    const metadata = await videoMetadata(options.videoUrl, options.metadataPath);
    options = {...options, metadata, duration: Number(metadata.duration)};
  }
  const {duration} = options;
  if (!Number.isFinite(duration) || duration <= 0) throw new Error("Не определена длительность видео для Microsoft.");
  log("Получение переведённых субтитров для Microsoft TTS…");
  const entries = await translatedSubtitles(options);
  const jobDir = fs.mkdtempSync(path.join(outputDir, "edge-job-"));
  const input = path.join(jobDir, "edge-subtitles.json");
  const output = path.join(outputDir, `translation-edge-${randomUUID()}.wav`);
  fs.writeFileSync(input, JSON.stringify(entries), "utf8");
  const progress = createProgress("Синтез Microsoft");
  progress.update(0);
  try {
    await runTool(python, ["-X", "utf8", worker, "--input", input, "--output", output, "--duration", String(duration), "--voice", voice,
      "--ffmpeg", executable("VOT_FFMPEG_EXE", "ffmpeg"), "--ffprobe", executable("VOT_FFPROBE_EXE", "ffprobe")], {
      timeout: 900_000,
      onLine(line) { if (line.startsWith("VOT_EDGE_PROGRESS:")) progress.update(Number(line.slice("VOT_EDGE_PROGRESS:".length))); },
    });
    if (!fs.existsSync(output) || fs.statSync(output).size < 44) throw new Error("Microsoft не создал аудиодорожку.");
    progress.finish();
    return output;
  } catch (error) { progress.fail(); fs.rmSync(output, {force: true}); throw error; }
  finally { fs.rmSync(jobDir, {force: true, recursive: true}); }
}
