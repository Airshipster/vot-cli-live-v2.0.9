#!/usr/bin/env node
import fs from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

import chalk from "chalk";
import parseArgs from "minimist";
import { Listr } from "listr2";
import undici from "undici";
import { v4 as uuidv4 } from "uuid";
import VOTClient from "@vot.js/node";
import { getVideoData as getVotVideoData } from "@vot.js/node/utils/videoData";
import { VOTAgent, VOTProxyAgent } from "@vot.js/node/utils/fetchAgent";

import {
  availableLangs,
  additionalTTS,
  liveVoicesSupportedPlatforms,
} from "./config/constants.js";
import validate from "./utils/validator.js";
import getVideoId from "./utils/getVideoId.js";
import downloadFile from "./download.js";
import { clearFileName } from "./utils/utils.js";
import parseProxy from "./proxy.js";
import coursehunterUtils from "./utils/coursehunter.js";
import { createVideoWithTranslation } from "./mergeVideo.js";
import getVideoTitle from "./utils/getVideoTitle.js";
import { formatDuration } from "./progress.js";
import { createEdgeAudio } from "./edgeTts.js";

// Автоматически читаем версию из package.json
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageJson = JSON.parse(
  fs.readFileSync(join(__dirname, "../package.json"), "utf8"),
);
const version = packageJson.version;
const HELP_MESSAGE = `
A small script that allows you to download an audio translation from Yandex via the terminal.

Usage:
  vot-cli [options] [args] <link> [link2] [link3] ...

Args:
  --output — Set the directory to download
  --output-file — Set the file name to download (requires specifying a dir to download in "--output" argument)
  --lang — Set the source video language, or auto to detect it (Default: auto)
  --reslang — Set the audio track language (You can see all supported languages in the documentation. Default: ru)
  --voice-style — Set engine (tts - Yandex standard, live - Yandex live voices, edge - Microsoft Edge. Default: live)
                  Note: Live voices work for English to Russian; authorization is used only if supplied
                  For other platforms (VK, OK.ru), TTS is used automatically
  --api-token — Optional Yandex OAuth token (or YANDEX_OAUTH_TOKEN environment variable)
  --translation-timeout — Maximum translation wait time in seconds (Default: 3600)
  --force-live-voices — Try live voices even for unsupported platforms (may fail. Default: false)
  --merge-video — Merge video with translation audio (requires yt-dlp and ffmpeg)
  --max-height — Maximum video height, e.g. 720 or 1080 (Default: unlimited)
  --video-format — Exact yt-dlp format selector (overrides --max-height)
  --video-title — Original title, as supplied by the video player
  --video-duration — Original duration in seconds, as supplied by the video player
  --video-metadata — yt-dlp metadata JSON file (used for Microsoft subtitles)
  --thumbnail-url — HTTPS image URL to replace the first video frame with the thumbnail (re-encodes video as H.264)
  --tts-voice — Microsoft voice ID, e.g. ru-RU-SvetlanaNeural (with --voice-style=edge)
  --keep-original-audio — Keep original audio when merging (mix with translation. Default: true)
  --normalize-audio — Normalize audio levels for consistent volume (uses dynaudnorm. Default: true)
  --translation-volume — Set translation audio volume (0.0-2.0. Default: 1.0)
  --original-volume — Set original audio volume (0.0-2.0. Default: 1.0)
  --proxy — Set proxy in format ([<PROTOCOL>://]<USERNAME>:<PASSWORD>@<HOST>[:<port>])
  --force-proxy — Don't start the transfer if the proxy could not be identified (true | false. Default: false)
  --quiet — Minimal output mode: only audio URL to stdout, errors to stderr (for scripting)
  --json — JSON output mode: structured data for programmatic processing

Options:
  -h, --help — Show help
  -v, --version — Show version
  --subs, --subtitles — Get video subtitles instead of audio (the subtitle language for saving is taken from --reslang)
`;

// LANG PAIR
let REQUEST_LANG = "auto";
let RESPONSE_LANG = "ru";
let USE_LIVE_VOICES = true; // по умолчанию используем живые голоса
let VOICE_ENGINE = "live";
let proxyData = false;

// ARG PARSER
const argv = parseArgs(process.argv.slice(2), {
  boolean: [
    "merge-video",
    "keep-original-audio",
    "normalize-audio",
    "force-live-voices",
    "subs",
    "subtitles",
    "subs-srt",
    "subtitles-srt",
    "help",
    "h",
    "version",
    "v",
    "force-proxy",
    "quiet",
    "json",
  ],
  string: [
    "output",
    "output-file",
    "lang",
    "reslang",
    "voice-style",
    "proxy",
    "translation-volume",
    "original-volume",
    "api-token",
    "translation-timeout",
    "max-height",
    "video-format",
    "video-title",
    "video-duration",
    "video-metadata",
    "thumbnail-url",
    "tts-voice",
  ],
});

const ARG_LINKS = argv._;
const OUTPUT_DIR = argv.output;
const OUTPUT_FILE = argv["output-file"];
const IS_SUBS_FORMAT_SRT = argv["subs-srt"] || argv["subtitles-srt"];
const RESPONSE_SUBTITLES_FORMAT = IS_SUBS_FORMAT_SRT ? "srt" : "json";
const IS_SUBS_REQ = argv.subs || argv.subtitles || IS_SUBS_FORMAT_SRT;
const ARG_HELP = argv.help || argv.h;
const ARG_VERSION = argv.version || argv.v;
const PROXY_STRING = argv.proxy;
let FORCE_PROXY = argv["force-proxy"] ?? false;
const MERGE_VIDEO = argv["merge-video"] === true || argv["merge-video"] === "";
const MAX_VIDEO_HEIGHT = Number(argv["max-height"] ?? 0);
const VIDEO_FORMAT = argv["video-format"] || undefined;
const VIDEO_TITLE = argv["video-title"] || undefined;
const VIDEO_METADATA = argv["video-metadata"] || undefined;
const THUMBNAIL_URL = argv["thumbnail-url"] || undefined;
const TTS_VOICE = argv["tts-voice"] || undefined;
const VIDEO_DURATION = argv["video-duration"] === undefined ? undefined : Number(argv["video-duration"]);
if (VIDEO_DURATION !== undefined && (!Number.isFinite(VIDEO_DURATION) || VIDEO_DURATION <= 0)) {
  console.error("--video-duration must be a positive number.");
  process.exit(1);
}
if (!Number.isInteger(MAX_VIDEO_HEIGHT) || MAX_VIDEO_HEIGHT < 0 || MAX_VIDEO_HEIGHT > 8640) {
  console.error("--max-height must be an integer between 0 and 8640.");
  process.exit(1);
}
const KEEP_ORIGINAL_AUDIO = argv["keep-original-audio"] ?? true;
const NORMALIZE_AUDIO = argv["normalize-audio"] ?? true;
const FORCE_LIVE_VOICES = argv["force-live-voices"] ?? false;
const TRANSLATION_VOLUME = parseFloat(argv["translation-volume"]) || 1.0;
const ORIGINAL_VOLUME = parseFloat(argv["original-volume"]) || 1.0;
const QUIET_MODE = argv.quiet ?? false;
const JSON_MODE = argv.json ?? false;
const API_TOKEN =
  argv["api-token"] ||
  process.env.YANDEX_OAUTH_TOKEN ||
  process.env.YANDEX_API_TOKEN;
const TRANSLATION_TIMEOUT_SECONDS = Number.parseInt(
  argv["translation-timeout"] ?? "3600",
  10,
);

// Set environment variable for child modules
if (QUIET_MODE || JSON_MODE) {
  process.env.VOT_CLI_QUIET = "1";
}
if (ARG_LINKS.length > 1) process.env.VOT_PROGRESS_MULTIPLE = "1";

// Validate conflicting flags
if (QUIET_MODE && JSON_MODE) {
  console.error(
    chalk.red("❌ Cannot use --quiet and --json together. Choose one."),
  );
  process.exit(1);
}

if (
  !Number.isFinite(TRANSLATION_TIMEOUT_SECONDS) ||
  TRANSLATION_TIMEOUT_SECONDS < 30
) {
  console.error(
    chalk.red("❌ --translation-timeout must be at least 30 seconds."),
  );
  process.exit(1);
}

// Helper functions for output modes
const log = (...args) => {
  if (!QUIET_MODE && !JSON_MODE) {
    console.log(...args);
  }
};

const logError = (...args) => {
  if (JSON_MODE) {
    // В JSON режиме ошибки тоже будут в JSON
    return;
  }
  console.error(...args);
};

// Storage for results (used in quiet/json modes)
const processedResults = [];

if (argv["voice-style"] !== undefined) {
  const voiceStyleValue = argv["voice-style"].toLowerCase();
  if (["tts", "live", "edge"].includes(voiceStyleValue)) {
    VOICE_ENGINE = voiceStyleValue;
    USE_LIVE_VOICES = voiceStyleValue === "live";
    log(
      chalk.cyan(
        `🎤 Voice style is set to ${VOICE_ENGINE === "edge" ? "Microsoft Edge TTS" : USE_LIVE_VOICES ? "live voices (живые голоса) 🔥" : "standard TTS 🤖"}`,
      ),
    );
  } else {
    throw new Error("Invalid voice-style. Choose live, tts or edge.");
  }
}

if (availableLangs.includes(argv.lang)) {
  REQUEST_LANG = argv.lang;
  log(
    chalk.cyan(
      `🌐 Request language is set to ${chalk.bold(REQUEST_LANG.toUpperCase())}`,
    ),
  );
} else if (argv.lang) {
  throw new Error(`Unsupported source language: ${argv.lang}`);
}

if (
  additionalTTS.includes(argv.reslang) ||
  (Boolean(IS_SUBS_REQ) && argv.reslang)
) {
  RESPONSE_LANG = argv.reslang;
  log(
    chalk.cyan(
      `🗣️  Response language is set to ${chalk.bold(RESPONSE_LANG.toUpperCase())}`,
    ),
  );
} else if (argv.reslang) {
  throw new Error(`Unsupported voice language: ${argv.reslang}`);
}

if (PROXY_STRING) {
  log(chalk.cyan(`🌍 Parsing proxy configuration...`));
  proxyData = parseProxy(PROXY_STRING);
  if (proxyData) {
    log(
      chalk.green(
        `✅ Proxy configured: ${proxyData.host}:${proxyData.port || "default"}`,
      ),
    );
  } else {
    logError(chalk.red(`❌ Failed to parse proxy configuration`));
  }
}

if (FORCE_PROXY && !proxyData) {
  throw new Error(
    chalk.red(
      "❌ vot-cli operation was interrupted due to the force-proxy option",
    ),
  );
}

const fetchOpts = {
  dispatcher: proxyData?.proxyUrl
    ? new VOTProxyAgent(proxyData.proxyUrl)
    : new VOTAgent(),
};
const votClient = new VOTClient({
  apiToken: API_TOKEN,
  fetchFn: async (url, options) => {
    const response = await undici.fetch(url, {
      ...options,
      signal: options.signal || AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      await response.body?.cancel();
      const requestUrl = new URL(url);
      throw new Error(`HTTP ${response.status} (${requestUrl.hostname}${requestUrl.pathname})`);
    }
    return response;
  },
  fetchOpts,
});

// TASKS - renderer будет установлен позже в зависимости от режима
let tasks;

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

const getErrorMessage = (error) => {
  const serviceMessage = error?.data?.message;
  if (typeof serviceMessage === "string" && serviceMessage.trim()) {
    return `Яндекс: ${serviceMessage.trim()}`;
  }
  if (typeof error?.data?.data === "string") {
    return `${error.message}: ${error.data.data}`;
  }
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return String(error || "Unknown translation error");
};

const translate = async (videoData, task, useLiveVoices = USE_LIVE_VOICES, videoTitle) => {
  const startedAt = Date.now();
  const deadline = startedAt + TRANSLATION_TIMEOUT_SECONDS * 1000;
  let attempt = 0;
  let transientFailures = 0;
  let firstRequest = true;

  while (Date.now() < deadline) {
    attempt += 1;
    try {
      const result = await votClient.translateVideo({
        videoData,
        requestLang: REQUEST_LANG,
        responseLang: RESPONSE_LANG,
        extraOpts: {
          useLivelyVoice: useLiveVoices,
          videoTitle,
          firstRequest,
        },
      });
      firstRequest = false;

      if (result.translated && result.url && result.status !== 5) {
        task.title = "Video translated successfully.";
        log("   └─ Ссылка на полную дорожку перевода получена.");
        return {
          success: true,
          urlOrError: result.url,
        };
      }

      const elapsedSeconds = Math.floor((Date.now() - startedAt) / 1000);
      const suggestedDelay = Number(result.remainingTime) || 30;
      const retryDelaySeconds = Math.min(30, Math.max(5, suggestedDelay));
      task.title = `⏳ Translation in progress... (${elapsedSeconds}s elapsed, attempt ${attempt})`;
      const remaining = Number(result.remainingTime);
      log(`Ожидание перевода Яндекса: прошло ${formatDuration(elapsedSeconds)}` +
        (remaining > 0 ? `; осталось ≈${formatDuration(remaining)}.` : "; сервис ещё готовит дорожку."));
      await sleep(retryDelaySeconds * 1000);
    } catch (error) {
      const serviceMessage = error?.data?.message || "";
      const isTemporaryFailure =
        error?.data?.status === 0 &&
        /попробуйте позже|try (again )?later|temporar/i.test(serviceMessage);
      const retryDelaySeconds = 30 * (transientFailures + 1);
      if (
        isTemporaryFailure &&
        transientFailures < 2 &&
        Date.now() + retryDelaySeconds * 1000 < deadline
      ) {
        transientFailures += 1;
        firstRequest = true;
        task.title = `⏳ Яндекс временно не смог перевести. Повтор через ${retryDelaySeconds} с (${transientFailures + 1}/3)`;
        log(chalk.yellow(`   └─ ${getErrorMessage(error)}. Повтор через ${retryDelaySeconds} с.`));
        await sleep(retryDelaySeconds * 1000);
        continue;
      }
      return {
        success: false,
        urlOrError: getErrorMessage(error),
      };
    }
  }

  return {
    success: false,
    urlOrError: `Translation timeout: exceeded ${TRANSLATION_TIMEOUT_SECONDS} seconds`,
  };
};

const fetchSubtitles = async (videoData, task) => {
  try {
    const subtitlesResponse = await votClient.getSubtitles({
      videoData,
      requestLang: REQUEST_LANG,
    });
    const subtitles = (subtitlesResponse.subtitles ?? []).reduce(
      (result, item) => {
        if (
          item.language &&
          item.url &&
          !result.some(
            (entry) =>
              entry.language === item.language && !entry.translatedFromLanguage,
          )
        ) {
          result.push({
            source: "yandex",
            language: item.language,
            url: item.url,
          });
        }
        if (item.translatedLanguage && item.translatedUrl) {
          result.push({
            source: "yandex",
            language: item.translatedLanguage,
            translatedFromLanguage: item.language,
            url: item.translatedUrl,
          });
        }
        return result;
      },
      [],
    );

    if (subtitles.length === 0) {
      throw new Error("No subtitles returned by Yandex");
    }

    task.title = "Subtitles for the video have been received.";
    log(
      `Subtitles response (${videoData.url}): "${chalk.gray(
        JSON.stringify(subtitles, null, 2),
      )}"`,
    );
    return {
      success: true,
      subsOrError: subtitles,
    };
  } catch (error) {
    return {
      success: false,
      subsOrError: getErrorMessage(error),
    };
  }
};

async function main() {
  if (ARG_LINKS.length === 0) {
    if (ARG_HELP) {
      return console.log(HELP_MESSAGE);
    } else if (ARG_VERSION) {
      return console.log(`🎬 vot-cli ${version}`);
    } else {
      return console.error(chalk.red("❌ No links provided"));
    }
  }

  // Создаём tasks с правильным renderer
  tasks = new Listr([], {
    concurrent: true,
    exitOnError: false,
    renderer: QUIET_MODE || JSON_MODE ? "silent" : "simple",
  });

  // Красивый баннер при запуске (только в обычном режиме)
  if (!QUIET_MODE && !JSON_MODE) {
    console.log(
      chalk.cyan(
        "\n╔═══════════════════════════════════════════════════════════╗",
      ),
    );
    console.log(
      chalk.cyan("║") +
        chalk.bold.white(
          "        🎬 VOT-CLI with Live Voices 🔥                ",
        ) +
        chalk.cyan("║"),
    );
    console.log(
      chalk.cyan(
        "╚═══════════════════════════════════════════════════════════╝",
      ),
    );
    console.log(
      chalk.gray("  Это форк продукта https://github.com/FOSWLY/vot-cli/"),
    );
    console.log(chalk.gray("  Вся слава Илье @ToilOfficial 🙏\n"));

    console.log(chalk.gray(`📦 Version: ${version}`));
    console.log(chalk.gray(`🎯 Videos to process: ${ARG_LINKS.length}`));
    if (MERGE_VIDEO) {
      console.log(
        chalk.yellow(`🎬 Video merge mode: ${chalk.bold("ENABLED")}`),
      );
      console.log(
        chalk.gray(`   ├─ Original volume: ${ORIGINAL_VOLUME * 100}%`),
      );
      console.log(
        chalk.gray(`   ├─ Translation volume: ${TRANSLATION_VOLUME * 100}%`),
      );
      console.log(
        chalk.gray(
          `   └─ Audio normalization: ${NORMALIZE_AUDIO ? chalk.green("ON") + " 🎚️" : chalk.yellow("OFF")}`,
        ),
      );
    }
    console.log("");
  }

  if (Boolean(OUTPUT_DIR) && !fs.existsSync(OUTPUT_DIR)) {
    try {
      log(chalk.cyan(`📁 Creating output directory: ${OUTPUT_DIR}`));
      fs.mkdirSync(OUTPUT_DIR);
      log(chalk.green(`✅ Directory created successfully\n`));
    } catch {
      throw new Error(chalk.red("❌ Invalid output directory"));
    }
  } else if (OUTPUT_DIR) {
    log(chalk.green(`✅ Output directory exists: ${OUTPUT_DIR}\n`));
  }

  for (const url of ARG_LINKS) {
    const service = validate(url);
    if (!service) {
      logError(chalk.red(`URL: ${url} is unknown service`));
      continue;
    }

    let videoId = getVideoId(service.host, url);
    if (
      typeof videoId === "object" &&
      ["coursehunter"].includes(service.host)
    ) {
      const [statusOrID, lessonId] = videoId;
      if (!statusOrID) {
        logError(chalk.red(`Entered unsupported link: ${url}`));
        continue;
      }

      const coursehunterData = await coursehunterUtils
        .getVideoData(statusOrID, lessonId)
        .then((data) => data);

      videoId = coursehunterData.url;
    }

    if (!videoId) {
      logError(chalk.red(`Entered unsupported link: ${url}`));
      continue;
    }

    tasks.add([
      {
        title: `Performing various tasks (ID: ${videoId}).`,
        task: async (ctx, task) =>
          task.newListr(
            (parent) => [
              {
                title: `🔗 Forming a link to the video`,
                task: async () => {
                  const finalURL =
                    videoId.startsWith("https://") || service.host === "custom"
                      ? videoId
                      : `${service.url}${videoId}`;
                  if (!finalURL) {
                    throw new Error(`Entered unsupported link: ${finalURL}`);
                  }
                  parent.finalURL = finalURL;
                  parent.serviceHost = service.host;
                  parent.videoData = await getVotVideoData(finalURL);
                  if (VIDEO_DURATION !== undefined) parent.videoData.duration = VIDEO_DURATION;
                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(chalk.gray(`   └─ URL: ${finalURL}`));
                    console.log(chalk.gray(`   └─ Platform: ${service.host}`));
                  }

                  // Проверяем поддержку live voices для данной платформы
                  parent.useLiveVoices = USE_LIVE_VOICES;

                  if (
                    parent.useLiveVoices &&
                    (!["en", "auto"].includes(REQUEST_LANG) || RESPONSE_LANG !== "ru")
                  ) {
                    throw new Error("Живые голоса поддерживают английский → русский. Для другой языковой пары выберите стандартную озвучку.");
                  }

                  if (
                    parent.useLiveVoices &&
                    !liveVoicesSupportedPlatforms.includes(service.host)
                  ) {
                    if (!QUIET_MODE && !JSON_MODE) {
                      console.log(
                        chalk.yellow(
                          `   └─ ⚠️  Live voices not officially supported for ${service.host}`,
                        ),
                      );
                    }

                    if (FORCE_LIVE_VOICES) {
                      if (!QUIET_MODE && !JSON_MODE) {
                        console.log(
                          chalk.yellow(
                            `      Trying anyway due to --force-live-voices flag...`,
                          ),
                        );
                      }
                      parent.useLiveVoices = true;
                      parent.shouldFallbackToTTS = true; // Если не сработает, попробуем TTS
                    } else {
                      if (!QUIET_MODE && !JSON_MODE) {
                        console.log(
                          chalk.cyan(
                            `      Using standard TTS instead (better compatibility)`,
                          ),
                        );
                      }
                      parent.useLiveVoices = false;
                    }
                  }

                  // Получаем название видео для имени файла
                  try {
                    if (!QUIET_MODE && !JSON_MODE) {
                      console.log(
                        chalk.cyan(`   └─ 📺 Fetching video title...`),
                      );
                    }
                    parent.videoTitle = VIDEO_TITLE || await getVideoTitle(finalURL);
                    if (parent.videoTitle && !QUIET_MODE && !JSON_MODE) {
                      console.log(
                        chalk.green(`   └─ ✅ Title: "${parent.videoTitle}"`),
                      );
                    }
                  } catch (e) {
                    if (!QUIET_MODE && !JSON_MODE) {
                      console.log(
                        chalk.yellow(
                          `   └─ ⚠️  Could not fetch title, using video ID`,
                        ),
                      );
                    }
                    parent.videoTitle = null;
                  }
                },
              },
              {
                title: `🎤 Translating (ID: ${videoId})`,
                enabled: !IS_SUBS_REQ,
                exitOnError: false,
                task: async (ctxSub, subtask) => {
                  let result;
                  const voiceType = VOICE_ENGINE === "edge" ? "Microsoft Edge TTS" : parent.useLiveVoices
                    ? "live voices 🔥"
                    : "TTS 🤖";
                  subtask.title = `🎤 Translating (ID: ${videoId}) with ${voiceType}`;

                  if (VOICE_ENGINE === "edge") {
                    try {
                      const localAudioPath = await createEdgeAudio({
                        client: votClient, videoData: parent.videoData, videoUrl: parent.finalURL,
                        metadataPath: VIDEO_METADATA, sourceLanguage: REQUEST_LANG, targetLanguage: RESPONSE_LANG,
                        outputDir: OUTPUT_DIR, voice: TTS_VOICE, duration: VIDEO_DURATION || parent.videoData.duration, log,
                      });
                      result = {success: true, urlOrError: localAudioPath, localAudioPath};
                    } catch (error) { result = {success: false, urlOrError: getErrorMessage(error)}; }
                  } else {
                    log(chalk.cyan(`   └─ 📡 Requesting translation from Yandex API...`));
                    result = await translate(parent.videoData, subtask, parent.useLiveVoices, parent.videoTitle);
                  }

                  if (
                    !result.success &&
                    parent.shouldFallbackToTTS &&
                    parent.useLiveVoices &&
                    argv["voice-style"]?.toLowerCase() !== "live"
                  ) {
                    log(
                      chalk.yellow(
                        `   └─ ⚠️  Live voices failed, retrying with TTS...`,
                      ),
                    );
                    parent.useLiveVoices = false;
                    subtask.title = `🎤 Translating (ID: ${videoId}) with TTS 🤖 (fallback)`;
                    result = await translate(parent.videoData, subtask, false, parent.videoTitle);
                  }

                  parent.translateResult = result;
                  if (!result.success) {
                    subtask.title = `❌ ${result.urlOrError}`;
                    throw new Error(result.urlOrError);
                  }

                  const finalVoiceType = VOICE_ENGINE === "edge" ? "Microsoft Edge TTS" : parent.useLiveVoices
                    ? "live voices 🔥"
                    : "TTS 🤖";
                  subtask.title = `✅ Translated successfully with ${finalVoiceType}`;
                },
              },
              {
                title: `Fetching subtitles (ID: ${videoId}).`,
                enabled: Boolean(IS_SUBS_REQ),
                exitOnError: false,
                task: async (ctxSub, subtask) => {
                  const result = await fetchSubtitles(
                    parent.videoData,
                    subtask,
                  );
                  parent.translateResult = result;
                  if (!result.success) {
                    subtask.title = `❌ ${result.subsOrError}`;
                    throw new Error(result.subsOrError);
                  }
                },
              },
              {
                title: `📥 Downloading audio translation (ID: ${videoId})`,
                exitOnError: false,
                enabled: Boolean(OUTPUT_DIR) && !IS_SUBS_REQ,
                task: async (ctxSub, subtask) => {
                  // * Video download

                  if (
                    !(
                      parent.translateResult?.success &&
                      parent.translateResult?.urlOrError
                    )
                  ) {
                    subtask.skip("Скачивание пропущено: перевод не получен");
                    return;
                  }

                  const taskSubTitle = `(ID: ${videoId})`;
                  if (parent.translateResult.localAudioPath) {
                    parent.downloadedPath = parent.translateResult.localAudioPath;
                    subtask.title = "Дорожка Microsoft готова.";
                    return;
                  }
                  const filename = OUTPUT_FILE
                    ? OUTPUT_FILE.endsWith(".mp3")
                      ? OUTPUT_FILE
                      : `${OUTPUT_FILE}.mp3`
                    : parent.videoTitle
                      ? `${parent.videoTitle}.mp3`
                      : `${clearFileName(videoId)}---${uuidv4()}.mp3`;

                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.cyan(`   └─ 💾 Saving as: ${chalk.bold(filename)}`),
                    );
                    console.log(
                      chalk.gray(
                        `   └─ 🔗 Source: ${parent.translateResult.urlOrError.substring(0, 60)}...`,
                      ),
                    );
                  }

                  await downloadFile(
                    parent.translateResult.urlOrError,
                    `${OUTPUT_DIR}/${filename}`,
                    subtask,
                    `(ID: ${videoId} as ${filename})`,
                  )
                    .then(() => {
                      parent.downloadedPath = `${OUTPUT_DIR}/${filename}`;
                      const fileSize = fs.statSync(parent.downloadedPath).size;
                      const fileSizeMB = (fileSize / 1024 / 1024).toFixed(2);
                      subtask.title = `✅ Audio downloaded! (${fileSizeMB} MB)`;
                      if (!QUIET_MODE && !JSON_MODE) {
                        console.log(
                          chalk.green(`   └─ ✅ File size: ${fileSizeMB} MB`),
                        );
                      }
                    })
                    .catch((e) => {
                      parent.outputError = e.message;
                      subtask.title = `❌ Error. Download ${taskSubTitle} failed! Reason: ${e.message}`;
                    });
                },
              },
              {
                title: `Downloading (ID: ${videoId}).`,
                exitOnError: false,
                enabled: Boolean(OUTPUT_DIR) && Boolean(IS_SUBS_REQ),
                task: async (ctxSub, subtask) => {
                  // * Subs download

                  if (
                    !(
                      parent.translateResult?.success &&
                      parent.translateResult?.subsOrError
                    )
                  ) {
                    throw new Error(
                      chalk.red(
                        `Downloading failed! Link "${parent.translateResult?.subsOrError}" not found`,
                      ),
                    );
                  }

                  const subOnReqLang = parent.translateResult.subsOrError.find(
                    (s) => s.language === RESPONSE_LANG,
                  );
                  if (!subOnReqLang) {
                    throw new Error(
                      chalk.red(
                        `Downloading failed! Failed to find ${RESPONSE_LANG} in the resulting list of subtitles`,
                      ),
                    );
                  }

                  const taskSubTitle = `(ID: ${videoId})`;
                  const filename = OUTPUT_FILE
                    ? OUTPUT_FILE.endsWith(`.${RESPONSE_SUBTITLES_FORMAT}`)
                      ? OUTPUT_FILE
                      : `${OUTPUT_FILE}.${RESPONSE_SUBTITLES_FORMAT}`
                    : `${subOnReqLang.language}---${clearFileName(
                        videoId,
                      )}---${uuidv4()}.${RESPONSE_SUBTITLES_FORMAT}`;
                  await downloadFile(
                    subOnReqLang.url,
                    `${OUTPUT_DIR}/${filename}`,
                    subtask,
                    `(ID: ${videoId} as ${filename})`,
                  )
                    .then(() => {
                      parent.downloadedPath = `${OUTPUT_DIR}/${filename}`;
                      subtask.title = `Download ${taskSubTitle} completed!`;
                    })
                    .catch((e) => {
                      parent.outputError = e.message;
                      subtask.title = `Error. Download ${taskSubTitle} failed! Reason: ${e.message}`;
                    });
                },
              },
              {
                title: `🎬 Merging video with translation (ID: ${videoId})`,
                exitOnError: false,
                enabled:
                  Boolean(OUTPUT_DIR) && Boolean(MERGE_VIDEO) && !IS_SUBS_REQ,
                task: async (ctxSub, subtask) => {
                  if (
                    !(
                      parent.translateResult?.success &&
                      parent.translateResult?.urlOrError
                    )
                  ) {
                    subtask.skip("Сборка видео пропущена: перевод не получен");
                    return;
                  }

                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.cyan(`   └─ 🎥 Starting video merge process...`),
                    );
                    console.log(
                      chalk.gray(
                        `      ├─ Original volume: ${ORIGINAL_VOLUME * 100}%`,
                      ),
                    );
                    console.log(
                      chalk.gray(
                        `      └─ Translation volume: ${TRANSLATION_VOLUME * 100}%`,
                      ),
                    );
                  }

                  const audioFilename = OUTPUT_FILE
                    ? OUTPUT_FILE.endsWith(".mp3")
                      ? OUTPUT_FILE
                      : `${OUTPUT_FILE}.mp3`
                    : `${clearFileName(videoId)}---${uuidv4()}.mp3`;
                  const audioPath = parent.downloadedPath || `${OUTPUT_DIR}/${audioFilename}`;

                  const videoFilename = OUTPUT_FILE
                    ? OUTPUT_FILE.endsWith(".mp4")
                      ? OUTPUT_FILE
                      : `${OUTPUT_FILE}.mp4`
                    : parent.videoTitle
                      ? `${parent.videoTitle}.mp4`
                      : `${clearFileName(videoId)}---${uuidv4()}.mp4`;
                  const videoPath = `${OUTPUT_DIR}/${videoFilename}`;

                  subtask.title = `📥 Downloading audio for merge...`;
                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.cyan(
                        `   └─ 📥 Step 1/3: Downloading translation audio...`,
                      ),
                    );
                  }
                  if (!fs.existsSync(audioPath) || fs.statSync(audioPath).size === 0) {
                    await downloadFile(
                      parent.translateResult.urlOrError,
                      audioPath,
                      null,
                      null,
                    );
                  }
                  const audioSize = (
                    fs.statSync(audioPath).size /
                    1024 /
                    1024
                  ).toFixed(2);
                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.green(
                        `      └─ ✅ Audio downloaded (${audioSize} MB)`,
                      ),
                    );
                  }

                  subtask.title = `🎬 Creating video with translation...`;
                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.cyan(
                        `   └─ 🎬 Step 2/3: Merging video with translation...`,
                      ),
                    );
                    console.log(
                      chalk.gray(`      ├─ This may take several minutes...`),
                    );
                    console.log(chalk.gray(`      └─ Video: ${videoFilename}`));
                  }

                  await createVideoWithTranslation(
                    parent.finalURL,
                    audioPath,
                    videoPath,
                    {
                      keepOriginalAudio: KEEP_ORIGINAL_AUDIO,
                      audioVolume: ORIGINAL_VOLUME,
                      translationVolume: TRANSLATION_VOLUME,
                      normalizeAudio: NORMALIZE_AUDIO,
                      maxHeight: MAX_VIDEO_HEIGHT,
                      videoFormat: VIDEO_FORMAT,
                      thumbnailUrl: THUMBNAIL_URL,
                      ...(proxyData?.proxyUrl
                        ? { proxyUrl: proxyData.proxyUrl }
                        : {}),
                    },
                  ).catch((error) => {
                    parent.outputError = getErrorMessage(error);
                    throw error;
                  });

                  // Удаляем временный аудио файл
                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.cyan(
                        `   └─ 🧹 Step 3/3: Cleaning up temporary files...`,
                      ),
                    );
                  }
                  if (fs.existsSync(audioPath)) {
                    fs.unlinkSync(audioPath);
                    if (!QUIET_MODE && !JSON_MODE) {
                      console.log(
                        chalk.gray(`      └─ ✅ Temporary audio file removed`),
                      );
                    }
                  }

                  const videoSize = (
                    fs.statSync(videoPath).size /
                    1024 /
                    1024
                  ).toFixed(2);
                  subtask.title = `✅ Video created! (${videoSize} MB) - ${videoFilename}`;

                  // Сохраняем путь к видео для quiet/json режимов
                  parent.mergedVideoPath = videoPath;
                  parent.mergedVideoSize = videoSize;

                  if (!QUIET_MODE && !JSON_MODE) {
                    console.log(
                      chalk.green(`   └─ ✅ Final video size: ${videoSize} MB`),
                    );
                    console.log(chalk.green(`   └─ 📁 Saved to: ${videoPath}`));
                  }
                },
              },
              {
                title: `Finish (ID: ${videoId}).`,
                task: () => {
                  parent.title = `Translating finished! (ID: ${videoId}).`;

                  // Сохраняем итог каждого задания для вывода и exit code.
                  {
                    const translationSuccess =
                      parent.translateResult?.success || false;
                    const outputSuccess = !OUTPUT_DIR
                      ? true
                      : MERGE_VIDEO && !IS_SUBS_REQ
                        ? Boolean(parent.mergedVideoPath)
                        : Boolean(parent.downloadedPath);
                    const success = translationSuccess && outputSuccess;
                    const subtitles =
                      translationSuccess && IS_SUBS_REQ
                        ? parent.translateResult.subsOrError
                        : null;
                    const subtitleUrl = subtitles?.find(
                      (subtitle) => subtitle.language === RESPONSE_LANG,
                    )?.url;
                    const result = {
                      url: parent.finalURL,
                      platform: parent.serviceHost,
                      videoTitle: parent.videoTitle,
                      success,
                      audioUrl:
                        success && !IS_SUBS_REQ
                          ? parent.translateResult.urlOrError
                          : null,
                      subtitles,
                      subtitleUrl: subtitleUrl || null,
                      error: success
                        ? null
                        : parent.outputError ||
                          parent.translateResult?.urlOrError ||
                          parent.translateResult?.subsOrError ||
                          (translationSuccess
                            ? "Output file was not created"
                            : "Unknown error"),
                      voiceType: VOICE_ENGINE === "edge" ? "edge" : parent.useLiveVoices ? "live" : "tts",
                    };

                    // Если создано видео с переводом, добавляем путь к нему
                    if (parent.mergedVideoPath) {
                      result.mergedVideoPath = parent.mergedVideoPath;
                      result.mergedVideoSize = parent.mergedVideoSize;
                    }

                    processedResults.push(result);
                  }
                },
              },
            ],
            {
              concurrent: false,
              rendererOptions: {
                collapseSubtasks: false,
              },
              exitOnError: false,
            },
          ),
      },
    ]);
  }

  try {
    // В quiet/json режиме отключаем listr UI полностью
    const runOptions = QUIET_MODE || JSON_MODE ? { renderer: "silent" } : {};

    await tasks.run(runOptions);

    const successfulResults = processedResults.filter(
      (result) => result.success,
    );
    const failedResults = processedResults.filter((result) => !result.success);
    const allFailed =
      processedResults.length > 0 && successfulResults.length === 0;

    // Обработка результатов в зависимости от режима
    if (QUIET_MODE) {
      // В quiet режиме выводим путь к видео (если merge) или ссылку на аудио (stdout) и ошибки (stderr)
      for (const result of processedResults) {
        if (result.success) {
          // Если создано видео - выводим путь к видео, иначе ссылку на аудио
          if (result.mergedVideoPath) {
            console.log(result.mergedVideoPath);
          } else if (result.subtitleUrl) {
            console.log(result.subtitleUrl);
          } else if (result.audioUrl) {
            console.log(result.audioUrl);
          }
        } else if (!result.success) {
          console.error(result.error || "Unknown error");
        }
      }

      // Выходим с кодом 1 только если ВСЕ видео failed
      if (allFailed) {
        process.exitCode = 1;
      }
    } else if (JSON_MODE) {
      // В JSON режиме выводим структурированные данные
      console.log(JSON.stringify(processedResults, null, 2));
      if (allFailed) {
        process.exitCode = 1;
      }
    } else {
      if (allFailed) {
        console.error("");
        console.error(chalk.red("❌ No videos were processed successfully."));
        for (const result of failedResults) {
          console.error(chalk.red(`   ${result.url}: ${result.error}`));
        }
        console.error("");
        process.exitCode = 1;
        return;
      }

      // Обычный режим с красивым UI
      console.log("");
      console.log(
        chalk.green(
          "╔═══════════════════════════════════════════════════════════╗",
        ),
      );
      console.log(
        chalk.green("║") +
          chalk.bold.white(
            "            🎉 ALL TASKS COMPLETED! 🎉                 ",
          ) +
          chalk.green("║"),
      );
      console.log(
        chalk.green(
          "╚═══════════════════════════════════════════════════════════╝",
        ),
      );
      console.log("");
      console.log(
        chalk.cyan(
          `✅ Successfully processed ${successfulResults.length}/${processedResults.length} video(s)`,
        ),
      );
      if (OUTPUT_DIR) {
        console.log(chalk.cyan(`📁 Output directory: ${OUTPUT_DIR}`));
      }
      console.log("");
    }
  } catch (e) {
    if (JSON_MODE) {
      console.log(
        JSON.stringify({ success: false, error: e.message }, null, 2),
      );
      process.exit(1);
    } else if (QUIET_MODE) {
      console.error(e.message);
      process.exit(1);
    } else {
      console.error("");
      console.error(
        chalk.red(
          "╔═══════════════════════════════════════════════════════════╗",
        ),
      );
      console.error(
        chalk.red("║") +
          chalk.bold.white(
            "                ❌ ERROR OCCURRED ❌                   ",
          ) +
          chalk.red("║"),
      );
      console.error(
        chalk.red(
          "╚═══════════════════════════════════════════════════════════╝",
        ),
      );
      console.error("");
      console.error(e);
      console.error("");
      process.exitCode = 1;
    }
  }
}

await main().catch((e) => {
  console.error(chalk.red("[VOT]", e));
  process.exitCode = 1;
});
