export function formatDuration(seconds) {
  const value = Math.max(0, Math.ceil(seconds));
  const minutes = Math.floor(value / 60);
  return `${String(minutes).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`;
}

function createProgressLine() {
  const enabled = !process.env.VOT_CLI_QUIET;
  const framed = process.env.VOT_PROGRESS_TRANSPORT === 'json';
  const inline = process.stdout.isTTY && !process.env.VOT_PROGRESS_MULTIPLE;
  let lastUpdate = 0;
  let lastText = "";
  let closed = false;

  function write(line, event = 'update', force = false) {
    if (!enabled || closed) return;
    const now = Date.now();
    if (!force && now - lastUpdate < 1000) return;
    if (line === lastText && !force) return;
    if (framed) {
      process.stdout.write('VOT_PROGRESS_JSON:' + JSON.stringify({event, text:line}) + '\n');
    } else { process.stdout.write(inline ? `\r\x1b[2K${line}` : `${line}\n`); }
    lastUpdate = now;
    lastText = line;
  }

  return {
    write,
    close(event = 'finish', emit = true) {
      if (closed) return;
      if (enabled && framed && lastText && emit) process.stdout.write('VOT_PROGRESS_JSON:' + JSON.stringify({event,text:lastText}) + '\n');
      else if (enabled && inline && !framed && lastText) process.stdout.write("\n");
      closed = true;
    },
  };
}

export function createStatusLine() {
  const line = createProgressLine();
  return {
    update(text) { line.write(text); },
    finish() { line.close(); },
    fail() { line.close('fail'); },
  };
}

// Percentages describe the current stage, using bytes or processed media time.
export function createProgress(label) {
  const line = createProgressLine();
  const startedAt = Date.now();
  function write(percent, etaSeconds, finish = false) {
    const fraction = percent / 100;
    const elapsed = (Date.now() - startedAt) / 1000;
    const eta = Number.isFinite(etaSeconds) && etaSeconds >= 0
      ? etaSeconds
      : elapsed >= 1 && fraction > 0 && fraction < 1 ? elapsed * (1 - fraction) / fraction : NaN;
    const remaining = Number.isFinite(eta) ? ` (осталось ≈${formatDuration(eta)})` : "";
    const suffix = Number.isFinite(percent) ? ` — ${percent.toFixed(1)}%` : " — ожидание данных";
    line.write(`${label}${remaining}${suffix}`, finish ? 'finish' : 'update', finish);
  }
  return {
    update(percent, etaSeconds) {
      write(Number.isFinite(percent) ? Math.min(99.9, Math.max(0, percent)) : NaN, etaSeconds);
    },
    finish() { write(100, 0, true); line.close('finish', false); },
    fail() { line.close('fail'); },
  };
}
