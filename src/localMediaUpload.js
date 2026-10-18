import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { createProgress } from './progress.js';
import { config } from '@vot.js/shared';
import {diagnostic,errorDetails} from './diagnostics.js';

// Same chunk framing as the extension's local-file downloader. Only send media
// after Yandex explicitly requests it; a waiting response is not an upload request.
export async function uploadLocalMedia(provider, url, translationId, filePath, signal) {
  if (!translationId) throw new Error('Яндекс запросил файл без идентификатора перевода.');
  const size = fs.statSync(filePath).size;
  if (!size) throw new Error('Подготовленный локальный файл пуст.');
  const sourceHost = new URL(url).hostname;
  const isYouTube = sourceHost === 'youtu.be' || sourceHost === 'www.youtube.com' || sourceHost === 'youtube.com';
  const chunkSize = isYouTube ? config.minChunkSize : 256 * 1024;
  const amount = Math.ceil(size / chunkSize);
  diagnostic('upload.start', {provider:'yandex',source:isYouTube?'youtube':'local',bytes:size,chunkBytes:chunkSize,chunks:amount});
  const fileId = 'local_' + randomUUID();
  const file = await fs.promises.open(filePath, 'r');
  const progress = createProgress('Передача файла Яндексу');
  progress.update(0);
  try {
    let response;
    for (let index = 0; index < amount; index++) {
      signal?.throwIfAborted();
      const length = Math.min(chunkSize, size - index * chunkSize);
      const data = Buffer.allocUnsafe(length);
      let read = 0;
      while (read < length) {
        const result = await file.read(data, read, length - read, index * chunkSize + read);
        if (!result.bytesRead) throw new Error('Выбранный файл изменился во время передачи.');
        read += result.bytesRead;
      }
      response = amount === 1
        ? await provider.requestVtransAudio(url, translationId, { audioFile: data, fileId }, undefined, {}, { signal })
        : await provider.requestVtransAudio(url, translationId, { audioFile: data, chunkId: index },
          { audioPartsLength: amount, fileId, version: 1 }, {}, { signal });
      diagnostic('upload.chunk', {chunk:index+1,chunks:amount,bytes:length,status:response?.status,remainingChunks:response?.remainingChunks?.length});
      if (![1, 2].includes(response?.status)) throw new Error('Яндекс не принял содержимое локального файла.');
      progress.update((index + 1) / amount * 100);
      if (response.status === 2 && Array.isArray(response.remainingChunks) && !response.remainingChunks.length) {
        diagnostic('upload.finish', {bytes:size,chunks:index+1});
        progress.finish(); return;
      }
    }
    throw new Error('Яндекс не подтвердил получение всех частей локального файла.');
  } catch (error) { diagnostic('upload.error', {error:errorDetails(error)}); progress.fail(); throw error; }
  finally { await file.close(); }
}
