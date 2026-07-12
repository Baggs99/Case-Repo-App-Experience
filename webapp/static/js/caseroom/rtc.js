/**
 * Purpose: WebRTC peer session for practice calls (spec §4.3) — perfect
 *          negotiation, 1.2 Mbps cap, negotiated `ctrl` DataChannel, ICE restart.
 * Inputs: polite flag (candidate=true), ice servers, local MediaStream,
 *         a SignalClient for sdp/ice transport, UI callbacks.
 * Outputs: remote MediaStream via callback; ctrl channel messages; state events.
 * Run: import { RtcSession } from '/static/js/caseroom/rtc.js'
 */

const MAX_VIDEO_BITRATE = 1_200_000; // spec §1: ~1.2 Mbps cap
const DISCONNECT_RESTART_DELAY_MS = 3000;

export class RtcSession {
  /**
   * @param {object} opts
   * @param {boolean} opts.polite candidate = polite, interviewer = impolite (§4.3)
   * @param {Array} opts.iceServers from /join-config
   * @param {boolean} opts.forceRelay ?forceRelay=1 debug flag
   * @param {MediaStream} opts.localStream
   * @param {SignalClient} opts.signal used to send {type:'sdp'|'ice'} messages
   * @param {(stream: MediaStream) => void} opts.onRemoteStream
   * @param {(msg: object) => void} opts.onCtrlMessage parsed ctrl-channel JSON
   * @param {() => void} opts.onCtrlOpen
   * @param {() => void} opts.onCtrlClose
   * @param {(state: string) => void} opts.onConnectionState pc.connectionState changes
   */
  constructor(opts) {
    this.opts = opts;
    this.makingOffer = false;
    this.ignoreOffer = false;
    this.disconnectTimer = null;
    this.lastStats = { bytesSent: 0, at: 0 };

    const pc = new RTCPeerConnection({
      iceServers: opts.iceServers,
      iceTransportPolicy: opts.forceRelay ? 'relay' : 'all',
    });
    this.pc = pc;

    // Negotiated on both sides with a fixed id — never rides the SDP race (§4.3).
    this.ctrl = pc.createDataChannel('ctrl', { id: 0, negotiated: true, ordered: true });
    this.ctrl.onopen = () => opts.onCtrlOpen?.();
    this.ctrl.onclose = () => opts.onCtrlClose?.();
    this.ctrl.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      opts.onCtrlMessage?.(msg);
    };

    for (const track of opts.localStream.getTracks()) {
      pc.addTrack(track, opts.localStream);
    }
    this._capVideoBitrate();

    pc.ontrack = ({ streams }) => {
      if (streams[0]) opts.onRemoteStream(streams[0]);
    };

    pc.onnegotiationneeded = async () => {
      try {
        this.makingOffer = true;
        await pc.setLocalDescription();
        opts.signal.send({ type: 'sdp', description: pc.localDescription });
      } catch (err) {
        console.error('negotiation failed', err);
      } finally {
        this.makingOffer = false;
      }
    };

    pc.onicecandidate = ({ candidate }) => {
      opts.signal.send({ type: 'ice', candidate });
    };

    pc.oniceconnectionstatechange = () => {
      const s = pc.iceConnectionState;
      if (s === 'disconnected') {
        // Give it a moment to self-heal before forcing a restart (§4.3).
        this.disconnectTimer = setTimeout(() => pc.restartIce(), DISCONNECT_RESTART_DELAY_MS);
      } else if (s === 'failed') {
        pc.restartIce();
      } else if (s === 'connected' || s === 'completed') {
        clearTimeout(this.disconnectTimer);
      }
    };

    pc.onconnectionstatechange = () => opts.onConnectionState?.(pc.connectionState);
  }

  async _capVideoBitrate() {
    const sender = this.pc.getSenders().find((s) => s.track?.kind === 'video');
    if (!sender) return;
    const p = sender.getParameters();
    p.encodings = p.encodings?.length ? p.encodings : [{}];
    p.encodings[0].maxBitrate = MAX_VIDEO_BITRATE;
    try { await sender.setParameters(p); } catch (err) {
      console.warn('bitrate cap failed', err);
    }
  }

  /** Perfect negotiation (§4.3): feed every sdp/ice signaling message here. */
  async handleSignal(msg) {
    const pc = this.pc;
    if (msg.type === 'sdp') {
      const description = msg.description;
      const offerCollision = description.type === 'offer'
        && (this.makingOffer || pc.signalingState !== 'stable');
      this.ignoreOffer = !this.opts.polite && offerCollision;
      if (this.ignoreOffer) return;

      await pc.setRemoteDescription(description); // implicit rollback when polite
      if (description.type === 'offer') {
        await pc.setLocalDescription();
        this.opts.signal.send({ type: 'sdp', description: pc.localDescription });
      }
    } else if (msg.type === 'ice') {
      try {
        await pc.addIceCandidate(msg.candidate ?? undefined);
      } catch (err) {
        if (!this.ignoreOffer) throw err;
      }
    }
  }

  sendCtrl(msg) {
    if (this.ctrl.readyState === 'open') {
      this.ctrl.send(JSON.stringify(msg));
      return true;
    }
    return false;
  }

  /** One outbound-video stats sample: kbps since last call + frame size. */
  async sampleStats() {
    const report = await this.pc.getStats();
    let out = null;
    for (const stat of report.values()) {
      if (stat.type === 'outbound-rtp' && stat.kind === 'video') out = stat;
    }
    if (!out) return null;
    const now = out.timestamp;
    const kbps = this.lastStats.at
      ? Math.round((8 * (out.bytesSent - this.lastStats.bytesSent)) / (now - this.lastStats.at))
      : 0;
    this.lastStats = { bytesSent: out.bytesSent, at: now };
    return {
      kbps,
      width: out.frameWidth,
      height: out.frameHeight,
      fps: out.framesPerSecond,
    };
  }

  close() {
    clearTimeout(this.disconnectTimer);
    this.ctrl.close();
    this.pc.close();
  }
}
