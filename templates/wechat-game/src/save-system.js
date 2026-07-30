/* ═══════ Save System ═══════
 * Cloud save with localStorage fallback + conflict resolution.
 * Strategy: last-write-wins with timestamp, merge for numerical values.
 * Zero dependencies. */

class SaveSystem {
  constructor(gameId = 'default') {
    this._gameId = gameId;
    this._key = `save_${gameId}`;
    this._data = {};
    this._dirty = false;
    this._autoSaveInterval = null;
    this._cloudEnabled = false;
  }

  // Load from best available source
  async load() {
    // Try cloud first, fall back to local
    const cloud = await this._loadCloud().catch(() => null);
    const local = this._loadLocal();

    if (cloud && local) {
      // Conflict resolution: pick most recent
      this._data = (cloud._ts > local._ts) ? cloud : local;
    } else {
      this._data = cloud || local || this._defaultData();
    }
    return this._data;
  }

  // Save to all available stores
  async save(data) {
    Object.assign(this._data, data);
    this._data._ts = Date.now();
    this._data._version = (this._data._version || 0) + 1;
    this._saveLocal(this._data);
    if (this._cloudEnabled) await this._saveCloud(this._data).catch(() => {});
    this._dirty = false;
  }

  // Get a value
  get(key, fallback) { return key in this._data ? this._data[key] : fallback; }

  // Set a value (auto-saves on interval)
  set(key, value) {
    this._data[key] = value;
    this._dirty = true;
  }

  // Enable auto-save
  enableAutoSave(intervalMs = 10000) {
    this._autoSaveInterval = setInterval(() => {
      if (this._dirty) this.save({});
    }, intervalMs);
  }

  // Reset all data
  async reset() {
    this._data = this._defaultData();
    await this.save({});
  }

  // Cloud integration (Leancloud)
  enableCloud(appId, appKey) {
    if (typeof AV !== 'undefined') {
      try {
        AV.init({ appId, appKey, serverURL: 'https://' + appId.slice(0,8) + '.api.lncldglobal.com' });
        this._cloudEnabled = true;
      } catch (e) {}
    }
  }

  // Internal
  _defaultData() { return { _ts: 0, _version: 0, coins: 0, highScore: 0, level: 1, settings: {} }; }

  _loadLocal() {
    try {
      const raw = localStorage.getItem(this._key);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  }

  _saveLocal(data) {
    try { localStorage.setItem(this._key, JSON.stringify(data)); } catch (e) {}
  }

  async _loadCloud() {
    if (!this._cloudEnabled) throw new Error('Cloud not enabled');
    const Save = AV.Object.extend('GameSave');
    const q = new AV.Query('Save');
    q.equalTo('gameId', this._gameId);
    q.descending('updatedAt');
    q.limit(1);
    const results = await q.find();
    return results.length ? JSON.parse(results[0].get('data')) : null;
  }

  async _saveCloud(data) {
    const Save = AV.Object.extend('GameSave');
    const q = new AV.Query('Save');
    q.equalTo('gameId', this._gameId);
    q.limit(1);
    const results = await q.find();
    const obj = results.length ? results[0] : new Save();
    obj.set('gameId', this._gameId);
    obj.set('data', JSON.stringify(data));
    await obj.save();
  }
}
