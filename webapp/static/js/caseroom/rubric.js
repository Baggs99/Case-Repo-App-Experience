/**
 * Purpose: interviewer rubric UI (spec T7.1/T7.2) — in-call drawer and
 *          debrief editor with debounced autosave, grade preview, finalize.
 * Inputs: {api} fetch helper from session.js; GET/PUT /rubric,
 *         POST /finalize; DOM containers #rubric-body / a debrief zone.
 * Outputs: draft autosaves (800 ms debounce); finalize POST; calls
 *          opts.onFinalized(feedbackViewData) so session.js can swap views.
 * Run: import { RubricPanel } from '/static/js/caseroom/rubric.js'
 */

const SAVE_DEBOUNCE_MS = 800;

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export class RubricPanel {
  /** @param {{api: Function, onFinalized?: Function}} opts */
  constructor(opts) {
    this.opts = opts;
    this.template = [];
    this.draft = { items: {}, notes_md: '' };
    this.gradePreview = 0;
    this.saveTimer = null;
    this.loaded = false;
    this.gradeTouched = false; // user edited the finalize grade box by hand
  }

  async load() {
    if (this.loaded) return true;
    const r = await this.opts.api('/rubric');
    if (!r.ok) return false;
    this.template = r.data.template_items;
    this.draft = { items: r.data.items || {}, notes_md: r.data.notes_md || '' };
    this.gradePreview = r.data.grade_preview;
    this.loaded = true;
    return true;
  }

  // ── In-call drawer ──────────────────────────────────────────────────────

  async toggleDrawer(force) {
    const drawer = $('rubric-drawer');
    const show = force !== undefined ? force : drawer.hidden;
    if (show) {
      $('pdf-drawer').hidden = true; // one left-side drawer at a time
      if (await this.load()) this._renderForm($('rubric-body'));
    }
    drawer.hidden = !show;
  }

  // ── Debrief editor (ended view) ─────────────────────────────────────────

  async renderDebrief(container) {
    if (!(await this.load())) return;
    container.innerHTML = `
      <div id="ru-debrief-form"></div>
      <div class="ru-finalize">
        <label class="label" for="ru-grade">Final grade (0–5)</label>
        <div class="ru-finalize-row">
          <input id="ru-grade" type="number" min="0" max="5" step="0.1">
          <button id="ru-finalize-btn" class="primary">Finalize</button>
        </div>
        <p id="ru-finalize-note" class="ru-hint">Finalizing releases the grade
          and notes to your candidate and burns this case for them. It cannot
          be undone.</p>
      </div>`;
    this._renderForm($('ru-debrief-form'));

    const gradeInput = $('ru-grade');
    gradeInput.value = this.gradePreview.toFixed(1);
    gradeInput.addEventListener('input', () => { this.gradeTouched = true; });

    $('ru-finalize-btn').addEventListener('click', () => this._finalizeClicked());
  }

  async _finalizeClicked() {
    const btn = $('ru-finalize-btn');
    const grade = parseFloat($('ru-grade').value);
    if (Number.isNaN(grade) || grade < 0 || grade > 5) {
      $('ru-finalize-note').textContent = 'Grade must be between 0 and 5.';
      return;
    }
    if (btn.dataset.armed !== '1') {
      btn.dataset.armed = '1';
      btn.textContent = `Confirm ${grade.toFixed(1)} / 5`;
      $('ru-finalize-note').textContent =
        'Click again to confirm — this releases feedback and cannot be undone.';
      return;
    }
    btn.disabled = true;
    await this._flushSave(); // don't finalize a stale draft
    const r = await this.opts.api('/finalize', { grade });
    if (!r.ok) {
      btn.disabled = false;
      btn.dataset.armed = '0';
      btn.textContent = 'Finalize';
      $('ru-finalize-note').textContent = r.data?.detail || 'Finalize failed.';
      return;
    }
    this.opts.onFinalized?.();
  }

  // ── Shared form ─────────────────────────────────────────────────────────

  _renderForm(container) {
    container.innerHTML = this.template.map((item) => {
      const entry = this.draft.items[item.id] || {};
      return `
        <div class="ru-item">
          <div class="ru-head">
            <span>${esc(item.label)}</span>
            <span class="ru-pts">
              <input type="number" inputmode="numeric" min="0"
                     max="${item.max_points}" step="1"
                     value="${entry.points ?? ''}" data-ru-points="${esc(item.id)}"
                     aria-label="Points for ${esc(item.label)}">
              / ${item.max_points}
            </span>
          </div>
          <input type="text" class="ru-note" maxlength="2000"
                 placeholder="Note (optional)" value="${esc(entry.note ?? '')}"
                 data-ru-note="${esc(item.id)}"
                 aria-label="Note for ${esc(item.label)}">
        </div>`;
    }).join('') + `
      <label class="label" for="ru-notes-${container.id}">Overall notes</label>
      <textarea id="ru-notes-${container.id}" class="ru-notes" rows="4"
        maxlength="20000"
        placeholder="What went well, what to practice next…">${esc(this.draft.notes_md)}</textarea>
      <p class="ru-status"><span data-ru-grade>Draft grade: ${this.gradePreview.toFixed(1)} / 5</span>
        <span data-ru-saved></span></p>`;

    // Property assignment, not addEventListener: re-rendering the same
    // container (drawer reopened) must not stack duplicate handlers.
    container.oninput = (ev) => this._onInput(ev);
  }

  _onInput(ev) {
    const t = ev.target;
    if (t.dataset.ruPoints !== undefined) {
      const item = this.template.find((i) => i.id === t.dataset.ruPoints);
      let points = parseInt(t.value, 10);
      if (Number.isNaN(points)) points = 0;
      points = Math.max(0, Math.min(item.max_points, points));
      this._entry(t.dataset.ruPoints).points = points;
    } else if (t.dataset.ruNote !== undefined) {
      this._entry(t.dataset.ruNote).note = t.value;
    } else if (t.classList.contains('ru-notes')) {
      this.draft.notes_md = t.value;
    } else {
      return;
    }
    this._scheduleSave();
  }

  _entry(id) {
    return (this.draft.items[id] ??= { points: 0, note: '' });
  }

  _scheduleSave() {
    this._setSaved('Saving…');
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this._flushSave(), SAVE_DEBOUNCE_MS);
  }

  async _flushSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = null;
    const r = await this.opts.api('/rubric', this.draft, 'PUT');
    if (!r.ok) { this._setSaved('Save failed — will retry'); this._scheduleSave(); return; }
    this.gradePreview = r.data.grade_preview;
    this._setSaved('Saved ✓');
    for (const el of document.querySelectorAll('[data-ru-grade]')) {
      el.textContent = `Draft grade: ${this.gradePreview.toFixed(1)} / 5`;
    }
    const gradeInput = $('ru-grade');
    if (gradeInput && !this.gradeTouched) gradeInput.value = this.gradePreview.toFixed(1);
  }

  _setSaved(text) {
    for (const el of document.querySelectorAll('[data-ru-saved]')) el.textContent = text;
  }
}

/** T7.3: the released-feedback view (candidate and interviewer). */
export async function renderFeedbackView(api, boot) {
  const r = await api('/feedback');
  if (!r.ok) return false;
  const fb = r.data;
  const rows = fb.items.map((i) => {
    const pct = i.max_points ? Math.round(100 * i.points / i.max_points) : 0;
    return `
      <div class="fb-item">
        <div class="fb-item-head"><span>${esc(i.label)}</span>
          <span class="fb-pts">${i.points} / ${i.max_points}</span></div>
        <div class="fb-bar"><div class="fb-fill" style="width:${pct}%"></div></div>
        ${i.note ? `<p class="fb-note">${esc(i.note)}</p>` : ''}
      </div>`;
  }).join('');
  const fmt = (ms) => `${Math.floor(ms / 60000)}:${String(Math.round(ms / 1000) % 60).padStart(2, '0')}`;
  const timeline = fb.reveals.length
    ? `<p class="label" style="margin-top:18px">Exhibits revealed</p>`
      + fb.reveals.map((rev) =>
          `<p class="tl-row"><span class="tl-t">${fmt(rev.t_offset_ms)}</span> Exhibit ${rev.idx}</p>`).join('')
    : '';

  document.getElementById('fb-body').innerHTML = `
    <p class="label">${boot.role === 'candidate' ? 'Your feedback' : 'Feedback you gave'} · ${esc(fb.case_title)}</p>
    <div class="fb-grade"><span class="fb-grade-n">${fb.grade.toFixed(1)}</span>
      <span class="fb-grade-of">/ 5</span></div>
    ${rows}
    ${fb.notes_md ? `<p class="label" style="margin-top:18px">Notes</p>
      <p class="fb-notes">${esc(fb.notes_md)}</p>` : ''}
    ${timeline}
    <div id="recording-links-fb" hidden style="margin-top:18px"></div>
    <p style="margin-top:22px">
      <a class="fb-link" href="/api/cases/${fb.case_id}/open-pdf" target="_blank" rel="noopener">Open the full case PDF ↗</a>
      · <a class="fb-link" href="/room">Back to your room</a></p>`;
  return true;
}
