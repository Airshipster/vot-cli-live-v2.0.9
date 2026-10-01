import argparse
import asyncio
import json
import math
import os
from pathlib import Path
import sys
import wave

sys.path.insert(0, os.environ.get("VOT_EDGE_PACKAGES", ""))
import edge_tts


async def tool(executable, *args):
    options = {"creationflags": 0x08000000} if os.name == "nt" else {}
    process = await asyncio.create_subprocess_exec(
        executable, *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, **options
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), 60)
    except BaseException:
        if process.returncode is None:
            process.kill()
            await process.wait()
        raise
    if process.returncode:
        raise RuntimeError(stderr.decode("utf-8", errors="replace")[-1200:])
    return stdout


def tempo_filter(factor):
    factors = []
    while factor > 2:
        factors.append("atempo=2")
        factor /= 2
    factors.append(f"atempo={max(1, factor):.6f}")
    return ",".join(factors)


async def synthesize(args):
    entries = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
    entries = [e for e in entries if str(e.get("text", "")).strip() and e.get("durationMs", 0) > 0]
    entries.sort(key=lambda e: e["startMs"])
    if not entries:
        raise RuntimeError("Нет текста субтитров для озвучки Microsoft.")
    duration = float(args.duration)
    if not math.isfinite(duration) or duration <= 0:
        raise RuntimeError("Не определена длительность видео.")
    blocks = []
    for entry in entries:
        start = max(0, entry["startMs"] / 1000)
        end = min(duration, (entry["startMs"] + entry["durationMs"]) / 1000)
        if start >= end:
            continue
        text = str(entry["text"]).strip()
        if blocks and start - blocks[-1]["end"] <= 0.3 and end - blocks[-1]["start"] <= 12 and len(blocks[-1]["text"]) + len(text) <= 300:
            blocks[-1]["text"] += " " + text
            blocks[-1]["end"] = max(end, blocks[-1]["end"])
        else:
            blocks.append({"start": start, "end": end, "text": text})
    if not blocks:
        raise RuntimeError("Временные метки субтитров находятся за пределами видео.")
    sample_rate = 24000
    work_dir = Path(args.input).parent / "edge-segments"
    work_dir.mkdir(exist_ok=True)
    semaphore = asyncio.Semaphore(3)
    completed = 0
    print("VOT_EDGE_PROGRESS:0", flush=True)

    async def one(index, block):
        nonlocal completed
        async with semaphore:
            audio_path = work_dir / f"segment-{index:05d}.mp3"
            await asyncio.wait_for(edge_tts.Communicate(
                block["text"], args.voice, connect_timeout=15, receive_timeout=30
            ).save(str(audio_path)), 60)
            info = json.loads(await tool(args.ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "json", str(audio_path)))
            audio_duration = float(info["format"]["duration"])
            stop = min(duration, blocks[index + 1]["start"]) if index + 1 < len(blocks) else duration
            window = min(max(block["end"] - block["start"], 0.1), max(stop - block["start"], 0.1))
            filter_value = tempo_filter(audio_duration / window) + f",apad,atrim=duration={window:.6f}"
            pcm = await tool(args.ffmpeg, "-hide_banner", "-nostdin", "-loglevel", "error", "-i", str(audio_path), "-af", filter_value,
                             "-ac", "1", "-ar", str(sample_rate), "-f", "s16le", "pipe:1")
            audio_path.unlink()
            completed += 1
            print(f"VOT_EDGE_PROGRESS:{completed / len(blocks) * 98:.1f}", flush=True)
            return pcm

    tasks = []
    try:
        async with asyncio.TaskGroup() as group:
            tasks = [group.create_task(one(index, block)) for index, block in enumerate(blocks)]
    except ExceptionGroup as error:
        reason = error.exceptions[0]
        raise RuntimeError(f"Microsoft не завершил синтез дорожки: {type(reason).__name__}: {reason}") from reason
    with wave.open(args.output, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        cursor = 0
        final_frame = round(duration * sample_rate)
        silence = b"\0" * (sample_rate * 2)

        def pad(frames):
            while frames > 0:
                count = min(frames, sample_rate)
                output.writeframesraw(silence[:count * 2])
                frames -= count

        for block, task in zip(blocks, tasks):
            start_frame = round(block["start"] * sample_rate)
            if start_frame > cursor:
                pad(start_frame - cursor)
                cursor = start_frame
            pcm = task.result()
            skip = max(0, cursor - start_frame) * 2
            pcm = pcm[skip:max(skip, skip + (final_frame - cursor) * 2)]
            output.writeframesraw(pcm)
            cursor += len(pcm) // 2
        pad(max(0, final_frame - cursor))
    work_dir.rmdir()


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list-voices", action="store_true")
    parser.add_argument("--lang", default="ru")
    parser.add_argument("--input")
    parser.add_argument("--output")
    parser.add_argument("--voice")
    parser.add_argument("--duration", type=float)
    parser.add_argument("--ffmpeg")
    parser.add_argument("--ffprobe")
    args = parser.parse_args()
    if args.list_voices:
        voices = await asyncio.wait_for(edge_tts.list_voices(), 30)
        selected = [{"id": v["ShortName"], "locale": v["Locale"], "gender": v["Gender"]}
                    for v in voices if v["Locale"].split("-")[0] == args.lang]
        print(json.dumps(sorted(selected, key=lambda v: v["id"]), ensure_ascii=False))
    else:
        await synthesize(args)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as error:
        print(f"Microsoft TTS: {error}", file=sys.stderr)
        sys.exit(1)
