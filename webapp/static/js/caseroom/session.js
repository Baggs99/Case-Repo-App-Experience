/**
 * Purpose: entry module for /session/{id} — wires lobby, consent, knock/admit
 *          (A7 ordering), the call itself, and teardown to debrief.
 * Inputs: window.CASEROOM bootstrap {sessionId, role, state, selfConsent,
 *         peerName, caseTitle}; /api/practice endpoints; signaling WS.
 * Outputs: a working call; state transitions via POST /state.
 * Run: loaded by session.html as <script type="module">.
 */

import { SignalClient } from './signal.js';
import { RtcSession } from './rtc.js';
import * as ui from './ui.js';

const BOOT = window.CASEROOM;
const API = `/api/practice/${BOOT.sessionId}`;
const IS_CANDIDATE = BOOT.role === 'candidate';
const PARAMS = new URLSearchParams(location.search);

let signal = null;
let rtc = null;
let localStream = null;
let joinConfig = null;
let admitted = false;
let inCall = false;

async function api(path, body) {
  const res = await fetch(`${API}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  return { ok: res.ok, status: res.status, data };
}

// ── Lobby: media preview + device pickers ─────────────────────────────────────

async function acquireMedia() {
  const video = {
    width: { ideal: 1280, max: 1280 },
    height: { ideal: 720, max: 720 },
    frameRate: { ideal: 30, max: 30 },
  };
  const audio = { echoCancellation: true, noiseSuppression: true, autoGainControl: true };
  const cam = ui.$('pick-cam').value;
  const mic = ui.$('pick-mic').value;
  if (cam) video.deviceId = { exact: cam };
  if (mic) audio.deviceId = { exact: mic };

  const stream = await navigator.mediaDevices.getUserMedia({ video, audio });
  if (localStream) for (const t of localStream.getTracks()) t.stop();
  localStream = stream;
  ui.$('preview').srcObject = stream;
  ui.$('pip').srcObject = stream;
  await ui.populateDevicePickers();
}

// ── Consent + state helpers ───────────────────────────────────────────────────

async function postConsent(checked) {
  const { ok, data } = await api('/consent', { consent: checked });
  if (!ok) {
    ui.setStatus(data?.detail || 'Consent update failed');
    ui.$('consent').checked = !checked;
    return;
  }
  refreshLobbyStatus(data);
}

function refreshLobbyStatus(session) {
  const mine = IS_CANDIDATE ? session.consent_candidate : session.consent_interviewer;
  const theirs = IS_CANDIDATE ? session.consent_interviewer : session.consent_candidate;
  if (!mine) ui.setStatus('Check the recording-consent box to continue.');
  else if (!theirs) ui.setStatus(`Waiting for ${BOOT.peerName} to consent…`);
  else ui.setStatus(IS_CANDIDATE ? 'Knocking — waiting to be admitted…' : 'Ready — admit your candidate when they knock.');
}

// ── Signaling ────────────────────────────────────────────────────────────────

function onSignalMessage(msg) {
  switch (msg.type) {
    case 'ok':
      admitted = msg.admitted;
      if (IS_CANDIDATE && !admitted) signal.send({ type: 'knock' });
      if (admitted && !inCall) startCall(); // reconnect restore
      break;
    case 'knock':
      if (!IS_CANDIDATE) ui.openAdmitModal(msg.display_name);
      break;
    case 'admit':
      if (IS_CANDIDATE && !inCall) startCall();
      break;
    case 'deny':
      ui.setStatus('The interviewer declined to admit you this time.');
      break;
    case 'peer-joined':
      if (!inCall) refreshFromServer();
      break;
    case 'peer-left':
      if (inCall) ui.banner(`${BOOT.peerName} left — waiting for them to return…`, 'warn');
      break;
    case 'sdp':
    case 'ice':
      rtc?.handleSignal(msg);
      break;
  }
}

async function refreshFromServer() {
  const { ok, data } = await api('');
  if (ok) refreshLobbyStatus(data);
}

// ── Admit flow (A7: server transition FIRST, WS admit only on 200) ──────────

async function admitClicked() {
  const { ok, status, data } = await api('/state', { target: 'live' });
  if (!ok && status !== 409) { ui.setStatus(data?.detail || 'Could not start.'); return; }
  if (status === 409 && !/already|Illegal transition live/.test(data?.detail || '')) {
    // Genuine gate (consent missing); an "already live" 409 falls through.
    ui.setStatus(data?.detail || 'Not ready yet.');
    ui.closeAdmitModal();
    return;
  }
  ui.closeAdmitModal();
  signal.send({ type: 'admit' });
  startCall();
}

function denyClicked() {
  signal.send({ type: 'deny' });
  ui.closeAdmitModal();
}

// ── The call ─────────────────────────────────────────────────────────────────

function startCall() {
  if (inCall) return;
  inCall = true;
  admitted = true;
  ui.showView('call');
  ui.banner(null);

  rtc = new RtcSession({
    polite: IS_CANDIDATE,
    iceServers: joinConfig.ice_servers,
    forceRelay: PARAMS.get('forceRelay') === '1',
    localStream,
    signal,
    onRemoteStream: (stream) => { ui.$('remote').srcObject = stream; },
    onCtrlOpen: () => rtc.sendCtrl({ type: 'echo', t: performance.now() }),
    onCtrlMessage: onCtrl,
    onConnectionState: (s) => {
      if (s === 'connected') ui.banner(null);
      else if (s === 'disconnected' || s === 'failed') ui.banner('Connection lost — reconnecting…', 'warn');
    },
  });

  if (PARAMS.get('debug') === '1') {
    ui.$('debug-overlay').hidden = false;
    setInterval(async () => {
      const s = await rtc?.sampleStats();
      if (s) ui.debugOverlay(`${s.kbps} kbps · ${s.width}×${s.height}@${s.fps ?? '?'} · ctrl RTT ${lastRtt ?? '–'} ms`);
    }, 2000);
  }
}

let lastRtt = null;
function onCtrl(msg) {
  if (msg.type === 'echo') rtc.sendCtrl({ type: 'echo-ack', t: msg.t });
  else if (msg.type === 'echo-ack') {
    lastRtt = Math.round(performance.now() - msg.t);
    console.info(`ctrl DataChannel echo RTT: ${lastRtt} ms`);
  }
}

async function endCall() {
  await api('/state', { target: 'debrief' }).catch(() => {});
  teardown();
  ui.showView('ended');
}

function teardown() {
  signal?.stop();
  rtc?.close();
  if (localStream) for (const t of localStream.getTracks()) t.stop();
  inCall = false;
}

// ── Boot ─────────────────────────────────────────────────────────────────────

async function boot() {
  ui.showView('lobby');
  ui.$('consent').checked = BOOT.selfConsent;

  if (PARAMS.get('nomedia') === '1') {
    // Dev/smoke-test flag: exercise signaling, admit flow, and the ctrl
    // DataChannel on machines with no camera. Real calls never set this.
    localStream = new MediaStream();
  } else {
    try {
      await acquireMedia();
    } catch (err) {
      ui.setStatus(`Camera/microphone unavailable: ${err.name}. Fix permissions and reload.`);
      return;
    }
  }

  if (BOOT.state === 'scheduled') {
    await api('/state', { target: 'lobby' }); // 409 = peer beat us to it; fine
  }

  const jc = await api('/join-config');
  if (!jc.ok) { ui.setStatus(jc.data?.detail || 'Session is not joinable.'); return; }
  joinConfig = jc.data;

  signal = new SignalClient(joinConfig.ws_path, onSignalMessage, (state, code) => {
    if (state === 'reconnecting') ui.banner('Signal connection lost — reconnecting…', 'warn');
    else if (state === 'open') { if (!inCall) ui.banner(null); }
    else if (state === 'closed' && code === 4403) ui.banner('Session is no longer joinable.', 'error');
  });
  signal.connect();
  refreshFromServer();

  ui.$('consent').addEventListener('change', (e) => postConsent(e.target.checked));
  ui.$('pick-cam').addEventListener('change', () => acquireMedia().catch(() => {}));
  ui.$('pick-mic').addEventListener('change', () => acquireMedia().catch(() => {}));
  ui.$('btn-admit').addEventListener('click', admitClicked);
  ui.$('btn-deny').addEventListener('click', denyClicked);
  ui.$('btn-end').addEventListener('click', endCall);
  ui.$('btn-mute').addEventListener('click', () => {
    const t = localStream.getAudioTracks()[0];
    if (!t) return;
    t.enabled = !t.enabled;
    ui.setMuteState('audio', t.enabled);
  });
  ui.$('btn-cam').addEventListener('click', () => {
    const t = localStream.getVideoTracks()[0];
    if (!t) return;
    t.enabled = !t.enabled;
    ui.setMuteState('video', t.enabled);
  });

  // No state transition on pagehide: a mid-call reload must be able to
  // restore (Phase 6 reconciliation). The WS drop tells the peer we left.
  window.addEventListener('pagehide', () => { signal?.stop(); });
}

boot();
