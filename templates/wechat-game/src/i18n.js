/* ═══════ i18n ═══════
 * Multi-language support with fallback and pluralization.
 * Usage:
 *   i18n.init({ zh: { score: '分数' }, en: { score: 'Score' } }, 'zh');
 *   i18n.t('score'); // '分数' */

const i18n = {
  _lang: 'zh',
  _strings: {},
  _fallback: 'zh',

  // Initialize with translations
  init(strings, defaultLang = 'zh') {
    this._strings = strings;
    this._lang = this._detectLang(defaultLang);
    this._fallback = defaultLang;
  },

  // Translate a key
  t(key, replacements = {}) {
    const langStrings = this._strings[this._lang] || this._strings[this._fallback] || {};
    let text = langStrings[key] || this._strings[this._fallback]?.[key] || key;

    // Pluralization: {{count}} → choose form
    if (replacements.count !== undefined) {
      const pluralKey = key + this._pluralForm(replacements.count);
      const pluralText = langStrings[pluralKey] || this._strings[this._fallback]?.[pluralKey];
      if (pluralText) text = pluralText;
    }

    // Replace {{var}} placeholders
    for (const [k, v] of Object.entries(replacements)) {
      text = text.replace(new RegExp('{{' + k + '}}', 'g'), v);
    }
    return text;
  },

  // Change language
  setLang(lang) {
    if (this._strings[lang]) { this._lang = lang; localStorage.setItem('i18n_lang', lang); }
  },

  getLang() { return this._lang; },

  // Common game strings template
  static GAME_STRINGS = {
    zh: {
      start: '开始游戏', retry: '再来一次', score: '得分',
      game_over: '游戏结束', you_win: '恭喜通关！',
      watch_ad: '📺 看广告', share: '📤 分享',
      rank: '排名', best_score: '最高分', combo: '连击',
      province: '选择省份', settings: '设置',
      sound_on: '音效:开', sound_off: '音效:关',
      music_on: '音乐:开', music_off: '音乐:关',
      privacy: '隐私政策', terms: '用户协议',
      new_record: '新纪录！', beat_percent: '击败了 {{pct}}% 的人',
    },
    en: {
      start: 'Start', retry: 'Retry', score: 'Score',
      game_over: 'Game Over', you_win: 'You Win!',
      watch_ad: '📺 Watch Ad', share: '📤 Share',
      rank: 'Rank', best_score: 'Best Score', combo: 'Combo',
      province: 'Select Region', settings: 'Settings',
      sound_on: 'SFX:ON', sound_off: 'SFX:OFF',
      music_on: 'BGM:ON', music_off: 'BGM:OFF',
      privacy: 'Privacy Policy', terms: 'Terms of Service',
      new_record: 'New Record!', beat_percent: 'Better than {{pct}}%!',
    }
  },

  _detectLang(defaultLang) {
    const stored = localStorage.getItem('i18n_lang');
    if (stored) return stored;
    const nav = navigator.language || navigator.userLanguage || '';
    return nav.startsWith('zh') ? 'zh' : defaultLang;
  },

  _pluralForm(count) {
    if (this._lang === 'zh') return ''; // Chinese has no plural
    return count === 1 ? '_one' : '_other';
  }
};
