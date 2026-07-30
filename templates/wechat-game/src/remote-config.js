/* ═══════ Remote Config ═══════
 * Toggle features and adjust parameters without redeploying.
 * Production: fetch from server. Development: localStorage override.
 * Use case: "Level 2 too hard? Lower difficulty remotely. No re-publish." */

class RemoteConfig {
  constructor(defaults = {}) {
    this._defaults = defaults;
    this._config = { ...defaults };
    this._fetched = false;
    this._url = null;
  }

  // Set remote config URL (JSON endpoint)
  setEndpoint(url) { this._url = url; }

  // Fetch remote config
  async fetch() {
    // First, check localStorage override (dev mode)
    const local = this._loadLocal();
    if (local) { this._config = { ...this._defaults, ...local }; this._fetched = true; return this._config; }

    // Fetch from server
    if (this._url) {
      try {
        const res = await fetch(this._url + '?t=' + Date.now());
        const remote = await res.json();
        this._config = { ...this._defaults, ...remote };
        this._fetched = true;
      } catch (e) {}
    }
    return this._config;
  }

  // Get a config value
  get(key, fallback) {
    return key in this._config ? this._config[key] : fallback;
  }

  // Check if a feature flag is enabled
  enabled(feature) { return !!this.get(feature, false); }

  // Override locally (dev only)
  setLocal(key, value) {
    this._config[key] = value;
    const local = this._loadLocal() || {};
    local[key] = value;
    try { localStorage.setItem('rc_override', JSON.stringify(local)); } catch (e) {}
  }

  // Typical game config
  static GAME_DEFAULTS = {
    // Difficulty
    level1_tiles: 30, level2_tiles: 96, level2_layers: 4,
    max_slots: 7, match_count: 3,
    // Monetization
    ads_enabled: true, revive_cost: 1, powerup_shuffle: true,
    powerup_undo: true, powerup_remove: true,
    // Social
    province_ranking: true, daily_challenge: true,
    // Debug
    debug_mode: false, show_fps: false, skip_tutorial: false
  };

  _loadLocal() {
    try { const d = localStorage.getItem('rc_override'); return d ? JSON.parse(d) : null; } catch (e) { return null; }
  }
}
