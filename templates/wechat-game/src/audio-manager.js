/* ═══════ Audio Manager ═══════
 * Sound pool, background music, spatial audio.
 * Prevents audio crackling from rapid playback (羊了个羊 tile-click problem).
 * Web Audio API, zero dependencies. */

class AudioManager {
  constructor() {
    this._ctx = null;
    this._pools = {};    // { name: [buffer, buffer, ...] }
    this._bgm = null;    // current BGM source node
    this._bgmGain = null;
    this._masterGain = null;
    this._sfxGain = null;
    this._muted = false;
    this._sfxMuted = false;
    this._bgmMuted = false;
  }

  init() {
    try {
      this._ctx = new (window.AudioContext || window.webkitAudioContext)();
      this._masterGain = this._ctx.createGain();
      this._masterGain.connect(this._ctx.destination);
      this._sfxGain = this._ctx.createGain();
      this._sfxGain.connect(this._masterGain);
      this._bgmGain = this._ctx.createGain();
      this._bgmGain.gain.value = 0.3;
      this._bgmGain.connect(this._masterGain);
    } catch (e) { console.warn('Audio not available'); }
  }

  // Ensure context is running (must be called from user gesture)
  resume() {
    if (this._ctx && this._ctx.state === 'suspended') this._ctx.resume();
  }

  // Preload a sound for pooling
  preload(name, frequency, duration, type = 'sine', poolSize = 3) {
    if (!this._ctx) return;
    this._pools[name] = [];
    for (let i = 0; i < poolSize; i++) {
      this._pools[name].push({ frequency, duration, type, ready: true });
    }
  }

  // Play a sound through the pool
  play(name, volume = 0.08) {
    if (!this._ctx || this._sfxMuted || this._muted) return;
    const pool = this._pools[name];
    if (!pool) return;

    // Find available buffer
    const entry = pool.find(e => e.ready);
    if (!entry) return; // pool exhausted, skip (no audio crackle!)

    entry.ready = false;
    const { frequency, duration, type } = entry;

    try {
      const osc = this._ctx.createOscillator();
      const gain = this._ctx.createGain();
      osc.type = type;
      osc.frequency.value = frequency;
      gain.gain.setValueAtTime(volume, this._ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, this._ctx.currentTime + duration);
      osc.connect(gain);
      gain.connect(this._sfxGain);
      osc.start();
      osc.stop(this._ctx.currentTime + duration);
      osc.onended = () => { entry.ready = true; };
    } catch (e) { entry.ready = true; }
  }

  // Play a chord (multiple frequencies)
  playChord(name, frequencies, duration = 0.15, volume = 0.06) {
    frequencies.forEach((f, i) => {
      setTimeout(() => {
        if (!this._ctx || this._sfxMuted) return;
        try {
          const osc = this._ctx.createOscillator(), g = this._ctx.createGain();
          osc.type = 'sine'; osc.frequency.value = f;
          g.gain.setValueAtTime(volume, this._ctx.currentTime);
          g.gain.exponentialRampToValueAtTime(0.001, this._ctx.currentTime + duration);
          osc.connect(g); g.connect(this._sfxGain);
          osc.start(); osc.stop(this._ctx.currentTime + duration);
        } catch (e) {}
      }, i * 60);
    });
  }

  // Background music (looping oscillator)
  playBGM(frequencies, noteDuration = 0.3) {
    this.stopBGM();
    if (!this._ctx || this._bgmMuted) return;
    // Simple melody sequencer
    let i = 0;
    const playNext = () => {
      if (!this._bgm || this._bgmMuted) return;
      try {
        const osc = this._ctx.createOscillator(), g = this._ctx.createGain();
        osc.type = 'triangle'; osc.frequency.value = frequencies[i % frequencies.length];
        g.gain.setValueAtTime(0.04, this._ctx.currentTime);
        g.gain.exponentialRampToValueAtTime(0.001, this._ctx.currentTime + noteDuration);
        osc.connect(g); g.connect(this._bgmGain);
        osc.start(); osc.stop(this._ctx.currentTime + noteDuration);
      } catch (e) {}
      i++;
      this._bgmTimer = setTimeout(playNext, noteDuration * 1000);
    };
    playNext();
  }

  stopBGM() {
    if (this._bgmTimer) { clearTimeout(this._bgmTimer); this._bgmTimer = null; }
  }

  // Mute controls
  toggleMute() { this._muted = !this._muted; return this._muted; }
  toggleSFX() { this._sfxMuted = !this._sfxMuted; return this._sfxMuted; }
  toggleBGM() { this._bgmMuted = !this._bgmMuted; if (this._bgmMuted) this.stopBGM(); return this._bgmMuted; }
}
