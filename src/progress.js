export function formatDuration(seconds) {
  const value = Math.max(0, Math.ceil(seconds));
  const minutes = Math.floor(value / 60);
  return `${String(minutes).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`;
}

// Percentages describe the current stage, using bytes or processed media time.
export function createProgress(label) {
  const enabled = !process.env.VOT_CLI_QUIET;
  const inline = process.stdout.isTTY && !process.env.VOT_PROGRESS_MULTIPLE;
  const startedAt = Date.now();
  let lastUpdate = 0;
  let lastText = "";
  let closed = false;

  function write(percent, etaSeconds, force = false) {
    if (!enabled || closed) return;
    const now = Date.now();
    if (!force && now - lastUpdate < 1000) return;
    const fraction = percent / 100;
    const elapsed = (now - startedAt) / 1000;
    const eta = Number.isFinite(etaSeconds) && etaSeconds >= 0
      ? etaSeconds
      : elapsed >= 1 && fraction > 0 && fraction < 1 ? elapsed * (1 - fraction) / fraction : NaN;
    const remaining = Number.isFinite(eta) ? ` (осталось ≈${formatDuration(eta)})` : "";
    const suffix = Number.isFinite(percent) ? ` — ${percent.toFixed(1)}%` : " — ожидание данных";
    const line = `${label}${remaining}${suffix}`;
    if (line === lastText && !force) return;
    process.stdout.write(inline ? `\r\x1b[2K${line}` : `${line}\n`);
    lastUpdate = now;
    lastText = line;
  }

  return {
    update(percent, etaSeconds) {
      write(Number.isFinite(percent) ? Math.min(99.9, Math.max(0, percent)) : NaN, etaSeconds);
    },
    finish() {
      write(100, 0, true);
      if (enabled && inline) process.stdout.write("\n");
      closed = true;
    },
    fail() {
      if (enabled && inline && lastText) process.stdout.write("\n");
      closed = true;
    },
  };
}
