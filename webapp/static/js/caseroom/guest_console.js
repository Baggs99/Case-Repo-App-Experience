/**
 * Purpose: F10 Task 2 — the guest interviewer's console (canvas 8a `gIsLive`):
 *          drives the interviewer's half of the practice-session lifecycle
 *          and renders the clock / exhibit-release / finalize controls.
 * Inputs: window.GUEST_BOOT {sessionId, caseId, caseTitle, caseType, peerName,
 *         state, consentInterviewer, consentCandidate, startedAt, exhibits}.
 * Outputs: POSTs to /api/practice/{id}/{consent,state,reveals,finalize};
 *          DOM updates to the clock/status/release/end controls.
 * Run: loaded by guest_console.html as <script type="module">.
 */

const BOOT = window.GUEST_BOOT;
const API = `/api/practice/${BOOT.sessionId}`;
const $ = (id) => document.getElementById(id);

let startedAtMs = BOOT.startedAt ? Date.parse(BOOT.startedAt) : null;
let clockTimer = null;
let pollTimer = null;

async function postJSON(path, body) {
  return fetch(path, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
}

function fmt(totalSec) {
  const s = Math.max(0, Math.floor(totalSec));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

function currentClock() {
  if (!startedAtMs) return '00:00';
  return fmt((Date.now() - startedAtMs) / 1000);
}

function toast(msg) {
  const el = $('g-toast');
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 2600);
}

function tick() {
  $('g-clock').textContent = currentClock();
}

function goLive(newStartedAt) {
  if (newStartedAt) startedAtMs = Date.parse(newStartedAt);
  $('g-status').hidden = true;
  const release = $('g-release');
  if (release) release.disabled = false;
  $('g-end').disabled = false;
  if (!clockTimer) {
    clockTimer = setInterval(tick, 1000);
    tick();
  }
}

async function pollForCandidateConsent() {
  try {
    const res = await fetch(API, { credentials: 'same-origin' });
    if (!res.ok) return; // transient — the interval retries, not a crash
    const data = await res.json();
    if (!data.consent_candidate) return;
    clearInterval(pollTimer);
    pollTimer = null;
    const r = await postJSON(`${API}/state`, { target: 'live' });
    if (!r.ok) { toast('Could not start the call — retrying.'); return; }
    const updated = await r.json();
    goLive(updated.started_at);
  } catch (err) {
    // Recoverable — keep polling on the next tick, don't crash the loop.
  }
}

async function run() {
  try {
    let state = BOOT.state;
    let consentCandidate = BOOT.consentCandidate;
    if (state === 'live') { goLive(BOOT.startedAt); return; }
    if (state === 'scheduled') {
      await postJSON(`${API}/consent`, { consent: true });
      await postJSON(`${API}/state`, { target: 'lobby' });
      state = 'lobby';
    }
    if (!consentCandidate) {
      pollTimer = setInterval(pollForCandidateConsent, 3000);
      pollForCandidateConsent();
    } else {
      const r = await postJSON(`${API}/state`, { target: 'live' });
      if (r.ok) {
        const updated = await r.json();
        goLive(updated.started_at);
      } else {
        toast('Could not start the call — reload to retry.');
      }
    }
  } catch (err) {
    toast('Something went wrong starting the session — reload to retry.');
  }
}

function wireRelease() {
  const btn = $('g-release');
  if (!btn || !BOOT.exhibits || !BOOT.exhibits.length) {
    const row = $('g-exhibit-row');
    if (row) row.hidden = true;
    return;
  }
  btn.addEventListener('click', async () => {
    btn.disabled = true;
    try {
      const r = await postJSON(`${API}/reveals`, { exhibit_id: BOOT.exhibits[0].exhibit_id });
      if (!r.ok) { toast('Could not release the exhibit — try again.'); btn.disabled = false; return; }
      btn.hidden = true;
      const sent = $('g-sent');
      sent.textContent = `SENT · ${currentClock()}`; // frozen — tick() never touches g-sent
      sent.hidden = false;
    } catch (err) {
      toast('Could not release the exhibit — try again.');
      btn.disabled = false;
    }
  });
}

function wireEnd() {
  const endBtn = $('g-end');
  const overlay = $('g-score-overlay');
  const confirmBtn = $('g-score-confirm');
  const cancelBtn = $('g-score-cancel');
  let picked = null;

  endBtn.addEventListener('click', () => { overlay.hidden = false; });
  cancelBtn.addEventListener('click', () => { overlay.hidden = true; });
  overlay.querySelectorAll('.g-score-btns button').forEach((b) => {
    b.addEventListener('click', () => {
      picked = Number(b.dataset.score);
      overlay.querySelectorAll('.g-score-btns button').forEach((x) => x.classList.remove('picked'));
      b.classList.add('picked');
      confirmBtn.disabled = false;
    });
  });
  confirmBtn.addEventListener('click', async () => {
    if (picked == null) return;
    confirmBtn.disabled = true;
    try {
      await postJSON(`${API}/state`, { target: 'debrief' });
      const r = await postJSON(`${API}/finalize`, { grade: picked });
      if (!r.ok) {
        toast('Could not finalize — try again.');
        confirmBtn.disabled = false;
        return;
      }
      location.assign(`/g/session/${BOOT.sessionId}/keep`);
    } catch (err) {
      toast('Could not finalize — try again.');
      confirmBtn.disabled = false;
    }
  });
}

wireRelease();
wireEnd();
run();
