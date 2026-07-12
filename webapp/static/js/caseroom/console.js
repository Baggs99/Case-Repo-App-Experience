/**
 * Purpose: interviewer-console clocks (myCase Interviewer Console design) —
 *          the master interview timer with cap progress, and the segment
 *          timer with logged laps. Pure client-side tools, no backend.
 * Inputs: DOM ids #master-time/#master-remain/#master-progress,
 *         #seg-time/#seg-toggle/#seg-stop/#seg-laps.
 * Outputs: DOM updates once per second; laps live only in page memory.
 * Run: import { MasterClock, SegmentTimer } from './console.js'
 */

const $ = (id) => document.getElementById(id);

const fmt = (totalSec) => {
  const s = Math.max(0, Math.round(totalSec));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

export class MasterClock {
  /** @param {number} startedAtMs epoch ms of going live
   *  @param {number} capMinutes visual cap (45 = the .ics default length) */
  constructor(startedAtMs, capMinutes = 45) {
    this.start = startedAtMs;
    this.capSec = capMinutes * 60;
    this.timer = setInterval(() => this._tick(), 1000);
    this._tick();
  }

  _tick() {
    const elapsed = (Date.now() - this.start) / 1000;
    $('master-time').textContent = fmt(elapsed);
    const remain = this.capSec - elapsed;
    const el = $('master-remain');
    if (remain >= 0) {
      el.textContent = `${fmt(remain)} left`;
      el.classList.remove('over');
    } else {
      el.textContent = `${fmt(-remain)} over`;
      el.classList.add('over');
    }
    $('master-progress').style.width =
      `${Math.min(100, (elapsed / this.capSec) * 100)}%`;
  }

  stop() { clearInterval(this.timer); }
}

export class SegmentTimer {
  constructor() {
    this.elapsed = 0;          // seconds, accumulated across pauses
    this.runningSince = null;  // epoch ms while running
    this.laps = [];
    this.timer = setInterval(() => this._render(), 500);
    $('seg-toggle').addEventListener('click', () => this.toggle());
    $('seg-stop').addEventListener('click', () => this.stopLog());
    this._render();
  }

  _now() {
    return this.elapsed
      + (this.runningSince ? (Date.now() - this.runningSince) / 1000 : 0);
  }

  toggle() {
    if (this.runningSince) {
      this.elapsed = this._now();
      this.runningSince = null;
    } else {
      this.runningSince = Date.now();
    }
    this._render();
  }

  /** Stop records the segment below and resets the count to zero. */
  stopLog() {
    const total = this._now();
    this.elapsed = 0;
    this.runningSince = null;
    if (total >= 1) {
      this.laps.push({ label: `Segment ${this.laps.length + 1}`, time: fmt(total) });
      this._renderLaps();
    }
    this._render();
  }

  _render() {
    $('seg-time').textContent = fmt(this._now());
    $('seg-toggle').textContent = this.runningSince ? 'Pause' : 'Start';
  }

  _renderLaps() {
    const wrap = $('seg-laps');
    wrap.innerHTML = '';
    this.laps.forEach((lap, i) => {
      const row = document.createElement('div');
      row.className = 'seg-lap';
      const input = document.createElement('input');
      input.value = lap.label;
      input.setAttribute('aria-label', `Label for segment ${i + 1}`);
      input.addEventListener('change', () => { this.laps[i].label = input.value; });
      const time = document.createElement('span');
      time.textContent = lap.time;
      row.append(input, time);
      wrap.appendChild(row);
    });
  }

  stop() { clearInterval(this.timer); }
}
