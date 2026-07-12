/**
 * Purpose: DOM helpers for the practice-session page — view switching,
 *          device pickers, banner, admit modal.
 * Inputs: element ids from templates/session.html.
 * Outputs: DOM mutations only; no network, no WebRTC.
 * Run: import * as ui from '/static/js/caseroom/ui.js'
 */

export const $ = (id) => document.getElementById(id);

export function showView(name) {
  for (const v of document.querySelectorAll('[data-view]')) {
    v.hidden = v.dataset.view !== name;
  }
}

/** Top-of-page status banner; pass null to hide. */
export function banner(text, tone = 'info') {
  const el = $('banner');
  if (!text) { el.hidden = true; return; }
  el.textContent = text;
  el.dataset.tone = tone;
  el.hidden = false;
}

export function setStatus(text) {
  $('lobby-status').textContent = text;
}

export async function populateDevicePickers() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  for (const [kind, sel] of [['videoinput', $('pick-cam')], ['audioinput', $('pick-mic')]]) {
    const current = sel.value;
    sel.innerHTML = '';
    devices.filter((d) => d.kind === kind).forEach((d, i) => {
      const opt = document.createElement('option');
      opt.value = d.deviceId;
      opt.textContent = d.label || `${kind === 'videoinput' ? 'Camera' : 'Microphone'} ${i + 1}`;
      sel.appendChild(opt);
    });
    if (current) sel.value = current;
  }
}

export function openAdmitModal(displayName) {
  $('admit-name').textContent = displayName;
  const modal = $('admit-modal');
  modal.hidden = false;
  $('btn-admit').focus();
}

export function closeAdmitModal() {
  $('admit-modal').hidden = true;
}

export function setMuteState(kind, enabled) {
  const btn = kind === 'audio' ? $('btn-mute') : $('btn-cam');
  btn.setAttribute('aria-pressed', String(!enabled));
  btn.classList.toggle('off', !enabled);
  if (kind === 'audio') {
    btn.textContent = enabled ? 'Mute' : 'Unmute';
  } else {
    btn.textContent = enabled ? 'Camera off' : 'Camera on';
  }
}

export function debugOverlay(text) {
  const el = $('debug-overlay');
  if (!el.hidden) el.textContent = text;
}
