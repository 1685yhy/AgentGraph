/* ═══════ Ad Manager ═══════
 * Usage: AdMgr.showRewarded(type).then(callback)
 * Types: revive, powerup, bonus
 * Auto-detects: WeChat → 微信广告SDK, Douyin → 抖音SDK, Web → confirm */

const AdMgr = {
  _platform: 'web',
  _units: {},

  init(adUnitIds = {}) {
    this._units = adUnitIds;
    // Detect platform
    if (typeof wx !== 'undefined' && wx.createRewardedVideoAd) {
      this._platform = 'wechat';
    } else if (typeof tt !== 'undefined' && tt.createRewardedVideoAd) {
      this._platform = 'douyin';
    }
  },

  showRewarded(type = 'revive') {
    const self = this;
    return new Promise((resolve) => {
      const unitId = self._units[type] || ('adunit-' + type);

      if (self._platform === 'wechat') {
        try {
          const ad = wx.createRewardedVideoAd({ adUnitId: unitId });
          ad.onClose(res => { if (res && res.isEnded) resolve(true); });
          ad.onError(() => { self._webFallback(resolve); });
          ad.show().catch(() => { self._webFallback(resolve); });
        } catch (e) { self._webFallback(resolve); }
      } else if (self._platform === 'douyin') {
        try {
          const ad = tt.createRewardedVideoAd({ adUnitId: unitId });
          ad.onClose(res => { if (res && res.isEnded) resolve(true); });
          ad.onError(() => { self._webFallback(resolve); });
          ad.show().catch(() => { self._webFallback(resolve); });
        } catch (e) { self._webFallback(resolve); }
      } else {
        self._webFallback(resolve);
      }
    });
  },

  _webFallback(resolve) {
    const ok = confirm('📺 观看广告？\n（上线后将展示真实广告）');
    resolve(ok);
  },

  getPlatform() { return this._platform; }
};
