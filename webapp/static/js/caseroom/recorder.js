/**
 * Purpose: local mic recording per spec §4.6 — own audio track only, 60 s
 *          chunks uploaded immediately in seq order, complete at debrief.
 * Inputs: {apiBase, stream, onState} — apiBase like /api/practice/42;
 *         POST …/recordings/chunk|complete endpoints.
 * Outputs: chunk uploads; onState('recording'|'failed'|'done'|'off');
 *          A9: any upload failure downgrades state, never the call.
 * Run: import { Recorder, renderRecordingLinks } from './recorder.js'
 */

const TIMESLICE_MS = 60_000;              // §4.6: crash loses ≤ 60 s
const BITS_PER_SECOND = 32_000;
const RETRY_DELAYS_MS = [1000, 2000, 4000, 8000, 15000];

function pickMime() {
  if (window.MediaRecorder?.isTypeSupported?.('audio/webm;codecs=opus')) {
    return { record: 'audio/webm;codecs=opus', upload: 'audio/webm' };
  }
  return { record: 'audio/mp4', upload: 'audio/mp4' };   // Safari
}

export class Recorder {
  /** @param {{apiBase: string, stream: MediaStream, onState?: Function}} opts */
  constructor(opts) {
    this.opts = opts;
    this.seq = 0;
    this.queue = [];
    this.pumping = false;
    this.failed = false;
    this.recorder = null;
    this.mime = pickMime();
    this.drained = null;   // resolver: queue fully flushed after stop
  }

  start() {
    const track = this.opts.stream.getAudioTracks()[0];
    if (!track || !window.MediaRecorder) {
      this.opts.onState?.('off');
      return false;
    }
    this.recorder = new MediaRecorder(new MediaStream([track]), {
      mimeType: this.mime.record,
      audioBitsPerSecond: BITS_PER_SECOND,
    });
    this.recorder.ondataavailable = (ev) => {
      if (ev.data && ev.data.size > 0 && !this.failed) {
        this.queue.push({ seq: this.seq++, blob: ev.data });
        this._pump();
      }
      if (this.recorder.state === 'inactive') this._maybeDrained();
    };
    this.recorder.start(TIMESLICE_MS);
    this.opts.onState?.('recording');
    return true;
  }

  /** Stop, flush the final chunk, then mark the recording complete. */
  async stopAndComplete() {
    if (!this.recorder || this.recorder.state === 'inactive') return;
    const stopped = new Promise((resolve) => { this.drained = resolve; });
    this.recorder.stop();          // fires a final ondataavailable
    await stopped;                 // queue empty (or failed)
    if (this.failed) return;
    const res = await fetch(`${this.opts.apiBase}/recordings/complete`,
                            { method: 'POST' }).catch(() => null);
    this.opts.onState?.(res?.ok ? 'done' : 'failed');
  }

  async _pump() {
    if (this.pumping) return;
    this.pumping = true;
    while (this.queue.length && !this.failed) {
      const item = this.queue[0];
      const ok = await this._uploadWithRetry(item);
      if (!ok) {
        // A9: recording is best-effort; the call must not care. Stop
        // capturing too — buffering forever would only grow memory.
        this.failed = true;
        try { this.recorder.stop(); } catch { /* already stopped */ }
        this.opts.onState?.('failed');
        break;
      }
      this.queue.shift();
    }
    this.pumping = false;
    this._maybeDrained();
  }

  _maybeDrained() {
    if (this.drained && (this.queue.length === 0 || this.failed)
        && this.recorder.state === 'inactive' && !this.pumping) {
      this.drained();
      this.drained = null;
    }
  }

  async _uploadWithRetry(item) {
    for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
      const form = new FormData();
      form.append('seq', String(item.seq));
      form.append('mime', this.mime.upload);
      form.append('blob', item.blob, `chunk-${item.seq}`);
      let res = null;
      try {
        res = await fetch(`${this.opts.apiBase}/recordings/chunk`,
                          { method: 'POST', body: form });
      } catch { /* network — retry */ }
      if (res?.ok) return true;
      if (res?.status === 409) {
        // "expected seq N": N > item.seq means the server already has this
        // chunk (a retry after a lost response) — treat as applied.
        const detail = (await res.json().catch(() => null))?.detail || '';
        const m = detail.match(/expected seq (\d+)/);
        if (m && Number(m[1]) > item.seq) return true;
      }
      if (attempt < RETRY_DELAYS_MS.length) {
        await new Promise((r) => setTimeout(r, RETRY_DELAYS_MS[attempt]));
      }
    }
    return false;
  }
}

/** Debrief/feedback helper: list both sides' recordings with download
 * links (T10.3). Renders nothing if the container or data is absent. */
export async function renderRecordingLinks(api, apiBase, containerId) {
  const wrap = document.getElementById(containerId);
  if (!wrap) return;
  const r = await api('/recordings');
  if (!r.ok || !r.data.recordings.length) { wrap.hidden = true; return; }
  wrap.hidden = false;
  wrap.innerHTML = '<p class="label">Recordings</p>'
    + r.data.recordings.map((rec) => {
        const size = rec.bytes > 0 ? `${(rec.bytes / 1048576).toFixed(1)} MB` : '';
        const status = rec.completed ? size : 'incomplete';
        return `<p class="tl-row"><a class="rec-link" `
          + `href="${apiBase}/recordings/${rec.user_id}">${rec.name} `
          + `(${rec.role})</a> <span class="tl-t">${status}</span></p>`;
      }).join('');
}
