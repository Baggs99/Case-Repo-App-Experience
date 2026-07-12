/**
 * Purpose: in-call exhibit machinery (spec §4.4) — candidate encrypted
 *          preload + WebCrypto decrypt-on-reveal, interviewer strip with
 *          Send buttons + PDF drawer, DV-4 polling fallback, reveal timeline.
 * Inputs: {api, apiBase, role, caseId, sendCtrl, isCtrlOpen} from session.js;
 *         /api/practice/{id}/exhibit* + /reveals endpoints; ctrl DataChannel
 *         messages {type:'reveal', exhibit_id, key_b64} via handleCtrl().
 * Outputs: DOM in #exhibit-tray / #exhibit-panel / #lightbox /
 *          #reveal-timeline; POST /reveals as system of record.
 * Run: import { ExhibitManager } from '/static/js/caseroom/exhibits.js'
 */

const POLL_MS = 5000; // DV-4: poll reveals every 5 s while ctrl DC is down

const $ = (id) => document.getElementById(id);

function b64buf(b64) {
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}

function fmtOffset(ms) {
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export class ExhibitManager {
  /**
   * @param {object} opts
   * @param {(path: string, body?: object) => Promise<{ok, status, data}>} opts.api
   * @param {string} opts.apiBase e.g. `/api/practice/42` — for raw blob fetches
   * @param {'interviewer'|'candidate'} opts.role
   * @param {number} opts.caseId for the interviewer's PDF drawer
   * @param {(msg: object) => boolean} opts.sendCtrl
   * @param {() => boolean} opts.isCtrlOpen
   */
  constructor(opts) {
    this.opts = opts;
    this.manifest = [];            // [{exhibit_id, idx, iv_b64, …}]
    this.blobs = new Map();        // exhibit_id -> Promise<ArrayBuffer>
    this.urls = new Map();         // exhibit_id -> decrypted object URL
    this.keys = new Map();         // exhibit_id -> key_b64 (interviewer)
    this.sent = new Set();         // exhibit_id (interviewer)
    this.pollTimer = null;
    this.started = false;
  }

  async start() {
    if (this.started) return;
    this.started = true;

    const m = await this.opts.api('/exhibits');
    if (!m.ok) return;
    this.manifest = m.data.exhibits;
    // No exhibits: candidate gets no tray (DV-12b — sessions never block on
    // exhibits), but the interviewer panel still hosts PDF/Rubric buttons.
    if (!this.manifest.length && this.opts.role === 'candidate') return;

    for (const e of this.manifest) {
      this.blobs.set(e.exhibit_id, fetch(`${this.opts.apiBase}/exhibit-blob/${e.exhibit_id}`)
        .then((r) => { if (!r.ok) throw new Error(`blob ${r.status}`); return r.arrayBuffer(); }));
    }

    if (this.opts.role === 'candidate') await this._startCandidate();
    else await this._startInterviewer();
  }

  // ── Candidate: locked tray, preload, decrypt on key ───────────────────────

  async _startCandidate() {
    $('exhibit-tray').hidden = false;
    const slots = $('tray-slots');
    slots.innerHTML = '';
    for (const e of this.manifest) {
      const slot = document.createElement('button');
      slot.className = 'ex-slot locked';
      slot.id = `ex-slot-${e.exhibit_id}`;
      slot.disabled = true;
      slot.innerHTML = `<span class="ex-num">${e.idx}</span><span class="ex-lock">LOCKED</span>`;
      slot.addEventListener('click', () => this._enlarge(e.exhibit_id));
      slots.appendChild(slot);
    }

    let done = 0;
    const status = $('tray-status');
    status.textContent = `Preloading exhibits… 0/${this.manifest.length}`;
    await Promise.allSettled([...this.blobs.values()].map((p) => p.then(() => {
      status.textContent = `Preloading exhibits… ${++done}/${this.manifest.length}`;
    })));
    status.textContent = `${this.manifest.length} exhibit${this.manifest.length > 1 ? 's' : ''} — locked until revealed`;

    await this.reconcile();          // mid-call reload: restore revealed state
    this._setPolling(!this.opts.isCtrlOpen());
  }

  /** ctrl DataChannel fast path (spec §4.4 step 4). */
  handleCtrl(msg) {
    if (msg.type === 'reveal' && this.opts.role === 'candidate') {
      this._unlock(msg.exhibit_id, msg.key_b64, true).catch(() => this.reconcile(true));
    }
  }

  onCtrlOpen() {
    this._setPolling(false);
    if (this.opts.role === 'candidate') this.reconcile(true); // catch missed keys
  }

  onCtrlClosed() {
    if (this.started && this.opts.role === 'candidate') this._setPolling(true);
  }

  _setPolling(on) {
    if (on && !this.pollTimer) {
      this.pollTimer = setInterval(() => {
        if (this.opts.isCtrlOpen()) this._setPolling(false);
        else this.reconcile(true);
      }, POLL_MS);
    } else if (!on && this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  /** Fetch the reveal list and pull any missing keys via the fallback
   * endpoint (spec §4.4 step 5, DV-4). Safe to call repeatedly.
   * spotlight=true auto-enlarges newly unlocked exhibits (live reveal);
   * false restores quietly (mid-call reload). */
  async reconcile(spotlight = false) {
    const r = await this.opts.api('/reveals');
    if (!r.ok) return;
    for (const rev of r.data.reveals) {
      if (this.urls.has(rev.exhibit_id)) continue;
      const k = await this.opts.api(`/exhibit-key/${rev.exhibit_id}`);
      if (k.ok) await this._unlock(rev.exhibit_id, k.data.key_b64, spotlight).catch(() => {});
    }
  }

  async _unlock(exhibitId, keyB64, spotlight = false) {
    if (this.urls.has(exhibitId)) return;
    const url = await this._decrypt(exhibitId, keyB64);
    const slot = $(`ex-slot-${exhibitId}`);
    if (slot) {
      slot.classList.remove('locked');
      slot.disabled = false;
      const e = this.manifest.find((x) => x.exhibit_id === exhibitId);
      slot.innerHTML = `<img src="${url}" alt="Exhibit ${e?.idx ?? ''}">`
        + `<span class="ex-num">${e?.idx ?? ''}</span>`;
      $('tray-status').textContent =
        `${this.urls.size} of ${this.manifest.length} exhibits revealed`;
    }
    if (spotlight) this._enlarge(exhibitId); // a fresh reveal takes the spotlight
  }

  // ── Interviewer: thumbnails + Send, PDF drawer ────────────────────────────

  async _startInterviewer() {
    const k = await this.opts.api('/exhibit-keys');
    if (!k.ok) return;
    for (const item of k.data.keys) this.keys.set(item.exhibit_id, item.key_b64);

    const already = await this.opts.api('/reveals'); // reload: restore sent state
    if (already.ok) for (const rev of already.data.reveals) this.sent.add(rev.exhibit_id);

    $('exhibit-panel').hidden = false;
    $('btn-pdf').addEventListener('click', () => this._togglePdf());
    $('btn-pdf-close').addEventListener('click', () => this._togglePdf(false));

    const strip = $('exhibit-strip');
    strip.innerHTML = '';
    for (const e of this.manifest) {
      const card = document.createElement('div');
      card.className = 'ex-card';
      card.innerHTML = `
        <button class="ex-thumb" aria-label="Enlarge exhibit ${e.idx}"></button>
        <button class="ex-send" id="ex-send-${e.exhibit_id}">Send ${e.idx}</button>`;
      strip.appendChild(card);
      card.querySelector('.ex-thumb').addEventListener('click', () => this._enlarge(e.exhibit_id));
      const btn = card.querySelector('.ex-send');
      btn.addEventListener('click', () => this.sendExhibit(e.exhibit_id));
      if (this.sent.has(e.exhibit_id)) this._markSent(e.exhibit_id);

      this._decrypt(e.exhibit_id, this.keys.get(e.exhibit_id)).then((url) => {
        card.querySelector('.ex-thumb').innerHTML = `<img src="${url}" alt="Exhibit ${e.idx}">`;
      }).catch(() => {
        card.querySelector('.ex-thumb').textContent = '⚠︎';
      });
    }
  }

  /** Spec §4.4 step 3: DataChannel fast path + POST system of record. */
  async sendExhibit(exhibitId) {
    const keyB64 = this.keys.get(exhibitId);
    if (!keyB64) return;
    this.opts.sendCtrl({ type: 'reveal', exhibit_id: exhibitId, key_b64: keyB64 });
    const r = await this.opts.api('/reveals', { exhibit_id: exhibitId });
    if (!r.ok) {
      const btn = $(`ex-send-${exhibitId}`);
      if (btn) { btn.textContent = 'Retry'; btn.classList.add('err'); }
      return;
    }
    this.sent.add(exhibitId);
    this._markSent(exhibitId);
  }

  _markSent(exhibitId) {
    const btn = $(`ex-send-${exhibitId}`);
    if (btn) { btn.textContent = 'Sent ✓'; btn.disabled = true; btn.classList.remove('err'); }
  }

  _togglePdf(force) {
    const drawer = $('pdf-drawer');
    const show = force !== undefined ? force : drawer.hidden;
    if (show) {
      $('rubric-drawer').hidden = true; // one left-side drawer at a time
      if (!$('pdf-frame').src) {
        $('pdf-frame').src = `/api/cases/${this.opts.caseId}/open-pdf`; // lazy-load
      }
    }
    drawer.hidden = !show;
  }

  // ── Shared: decrypt, lightbox, timeline ───────────────────────────────────

  async _decrypt(exhibitId, keyB64) {
    if (this.urls.has(exhibitId)) return this.urls.get(exhibitId);
    const e = this.manifest.find((x) => x.exhibit_id === exhibitId);
    if (!e || !keyB64) throw new Error('unknown exhibit or missing key');
    const cipher = await this.blobs.get(exhibitId);
    const key = await crypto.subtle.importKey('raw', b64buf(keyB64), 'AES-GCM', false, ['decrypt']);
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: b64buf(e.iv_b64) }, key, cipher);
    const url = URL.createObjectURL(new Blob([plain], { type: 'image/webp' }));
    this.urls.set(exhibitId, url);
    return url;
  }

  _enlarge(exhibitId) {
    const url = this.urls.get(exhibitId);
    if (!url) return;
    const e = this.manifest.find((x) => x.exhibit_id === exhibitId);
    $('lightbox-img').src = url;
    $('lightbox-cap').textContent = `Exhibit ${e?.idx ?? ''}`;
    $('lightbox').hidden = false;
  }

  stop() {
    this._setPolling(false);
  }
}

/** T6.4: reveal timeline for the ended/debrief view (both parties).
 * Standalone: also used when the page loads straight into debrief and no
 * ExhibitManager ever starts. */
export async function renderRevealTimeline(api) {
  const r = await api('/reveals');
  const wrap = $('reveal-timeline');
  if (!r.ok || !r.data.reveals.length) { wrap.hidden = true; return; }
  wrap.hidden = false;
  wrap.innerHTML = '<p class="label">Exhibits revealed</p>'
    + r.data.reveals.map((rev) =>
        `<p class="tl-row"><span class="tl-t">${fmtOffset(rev.t_offset_ms)}</span>`
        + ` Exhibit ${rev.idx}</p>`).join('');
}

export function wireLightbox() {
  const box = $('lightbox');
  box.addEventListener('click', () => { box.hidden = true; });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') box.hidden = true;
  });
}
