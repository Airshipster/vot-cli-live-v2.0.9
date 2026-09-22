// available languages for translation
const availableLangs = [
  "ru",
  "en",
  "zh",
  "ko",
  "ar",
  "fr",
  "it",
  "es",
  "de",
  "ja",
];

// Additional languages working with TTS
const additionalTTS = [
  "ru",
  "kk",
  "en",
  // "bn",
  // "pt",
  // "cs",
  // "hi",
  // "mr",
  // "te",
  // "tr",
  // "ms",
  // "vi",
  // "ta",
  // "jv",
  // "ur",
  // "fa",
  // "gu",
  // "id",
  // "uk",
  // "kk",
];

// Platforms where live voices are officially supported and tested
const liveVoicesSupportedPlatforms = ["youtube", "twitch", "vimeo"];

// Platforms where live voices are NOT supported (will use TTS instead)
const liveVoicesUnsupportedPlatforms = ["vk", "ok.ru", "rutube", "mail.ru"];

export {
  availableLangs,
  additionalTTS,
  liveVoicesSupportedPlatforms,
  liveVoicesUnsupportedPlatforms,
};
