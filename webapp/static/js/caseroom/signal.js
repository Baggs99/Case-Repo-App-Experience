/**
 * Purpose: WebSocket signaling client for practice calls (spec §4.2 protocol).
 * Inputs: session id (ws path from /join-config), browser session cookie.
 * Outputs: dispatched message events; auto-reconnect with backoff; 30 s pings.
 * Run: import { SignalClient } from '/static/js/caseroom/signal.js'
 */

const PING_INTERVAL_MS = 30_000;
const BACKOFF_MS = [1000, 2000, 4000, 8000, 10_000];

// Server close codes that mean "stop trying" (webapp/signaling.py).
const FATAL_CLOSES = new Set([4000, 4401, 4403]);

export class SignalClient {
  /**
   * @param {string} wsPath e.g. "/ws/practice/7"
   * @param {(msg: object) => void} onMessage every parsed server message
   * @param {(state: 'open'|'reconnecting'|'closed', detail?: number) => void} onState
   */
  constructor(wsPath, onMessage, onState) {
    this.url = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}${wsPath}`;
    this.onMessage = onMessage;
    this.onState = onState;
    this.ws = null;
    this.attempts = 0;
    this.pingTimer = null;
    this.stopped = false;
  }

  connect() {
    if (this.stopped) return;
    const ws = new WebSocket(this.url);
    this.ws = ws;

    ws.onopen = () => {
      this.attempts = 0;
      this.pingTimer = setInterval(() => this.send({ type: 'ping' }), PING_INTERVAL_MS);
      this.onState('open');
    };

    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === 'pong') return;
      this.onMessage(msg);
    };

    ws.onclose = (ev) => {
      clearInterval(this.pingTimer);
      if (this.stopped || FATAL_CLOSES.has(ev.code)) {
        this.onState('closed', ev.code);
        return;
      }
      // Transient drop (network blip, server restart): retry with backoff.
      const delay = BACKOFF_MS[Math.min(this.attempts, BACKOFF_MS.length - 1)];
      this.attempts += 1;
      this.onState('reconnecting');
      setTimeout(() => this.connect(), delay);
    };

    ws.onerror = () => { /* onclose always follows; handled there */ };
  }

  send(msg) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  /** Best-effort bye + permanent close (end call / page teardown). */
  stop() {
    this.stopped = true;
    clearInterval(this.pingTimer);
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: 'bye' }));
    }
    this.ws?.close();
  }
}
