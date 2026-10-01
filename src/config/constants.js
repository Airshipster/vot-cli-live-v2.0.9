import fs from "node:fs";

const languages = JSON.parse(fs.readFileSync(new URL("./languages.json", import.meta.url), "utf8"));
const availableLangs = languages.source.map((item) => item.code);
const additionalTTS = languages.target.map((item) => item.code);

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
