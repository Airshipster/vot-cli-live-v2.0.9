import fs from "fs";
import { Writable } from "stream";
import axios from "axios";
import { jsonToSrt } from "./utils/utils.js";
import { createProgress } from "./progress.js";

export default async function downloadFile(url, outputPath, subtask, videoId) {
  if (!url) {
    throw new Error("Invalid download link");
  }
  const IS_NEED_CONVERT = outputPath.endsWith(".srt");
  const { data, headers } = await axios({
    method: "get",
    url: url,
    responseType: "stream",
  });

  const writer = fs.createWriteStream(outputPath);
  const progress = createProgress(IS_NEED_CONVERT ? "Скачивание субтитров" : "Скачивание перевода");
  const totalLength = Number(headers["content-length"]);
  let downloadedLength = 0;

  data.on("data", (chunk) => {
    downloadedLength += chunk.length;
    progress.update(totalLength > 0 ? downloadedLength / totalLength * 100 : NaN);
  });

  if (IS_NEED_CONVERT) {
    let dataBuffer = "";
    const writableStream = new Writable({
      write(chunk, encoding, callback) {
        dataBuffer += chunk.toString();
        callback();
      },
    });
    data.pipe(writableStream);
    data.on("end", () => {
      try {
        const jsonData = JSON.parse(dataBuffer);
        writer.end(jsonToSrt(jsonData["subtitles"]));
      } catch (error) { writer.destroy(error); }
    });
  } else {
    data.pipe(writer);
  }

  return new Promise((resolve, reject) => {
    data.on("error", (error) => writer.destroy(error));
    writer.on("finish", () => { progress.finish(); resolve(); });
    writer.on("error", (error) => { data.destroy(); progress.fail(); reject(error); });
  });
}

// await downloadFile(link, "./1244.mp3")
