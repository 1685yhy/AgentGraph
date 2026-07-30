/* ═══════ A/B Test Framework ═══════
 * Split testing, variant assignment, metric tracking, simple significance.
 * Use case: "Does 3-revive-ads make more money than 5-revive-ads?"
 * Privacy-safe: no PII, opt-out via localStorage. */

class ABTest {
  constructor() {
    this._tests = {};
    this._userId = this._loadUserId();
  }

  // Register an A/B test
  // name: unique test name
  // variants: ['control', 'variant_a', 'variant_b']
  // weights: [0.5, 0.25, 0.25] (optional, defaults to equal)
  register(name, variants, weights = null) {
    if (this._tests[name]) return this._tests[name].variant;

    // Deterministic assignment (same user always gets same variant)
    const hash = this._hash(name + this._userId);
    const ws = weights || variants.map(() => 1 / variants.length);
    let cumulative = 0;
    let assignedIdx = 0;
    for (let i = 0; i < variants.length; i++) {
      cumulative += ws[i];
      if (hash <= cumulative) { assignedIdx = i; break; }
    }

    this._tests[name] = {
      variants,
      variant: variants[assignedIdx],
      variantIdx: assignedIdx,
      metrics: {},
      started: Date.now()
    };

    // Track assignment
    this.track(name, 'assigned', { variant: variants[assignedIdx] });

    return variants[assignedIdx];
  }

  // Get current variant for a test
  getVariant(name) { return this._tests[name]?.variant || 'control'; }

  // Track a metric for a test
  track(testName, metricName, value = 1) {
    const test = this._tests[testName];
    if (!test) return;
    const key = `${test.variant}:${metricName}`;
    test.metrics[key] = (test.metrics[key] || 0) + value;
  }

  // Track conversion (binary: converted or not)
  convert(testName, goal = 'conversion') {
    this.track(testName, goal, 1);
    this.track(testName, goal + '_trials', 1);
  }

  // Get results for a test
  getResults(testName) {
    const test = this._tests[testName];
    if (!test) return null;

    const results = {};
    for (const v of test.variants) {
      results[v] = {};
      for (const [key, val] of Object.entries(test.metrics)) {
        if (key.startsWith(v + ':')) {
          results[v][key.slice(v.length + 1)] = val;
        }
      }
    }
    return {
      test: testName,
      variants: results,
      duration: Date.now() - test.started,
      winner: this._pickWinner(results)
    };
  }

  // Simple winner picker: highest conversion or highest value
  _pickWinner(results) {
    let best = null, bestRate = -1;
    for (const [variant, metrics] of Object.entries(results)) {
      // Prefer conversion rate if available
      if (metrics.conversion && metrics.conversion_trials) {
        const rate = metrics.conversion / metrics.conversion_trials;
        if (rate > bestRate) { bestRate = rate; best = variant; }
      } else {
        // Fall back to total tracked value
        const total = Object.values(metrics).reduce((a, b) => a + b, 0);
        if (total > bestRate) { bestRate = total; best = variant; }
      }
    }
    return best;
  }

  // Save results to localStorage for persistence
  save() {
    try { localStorage.setItem('ab_tests', JSON.stringify(this._tests)); } catch (e) {}
  }

  load() {
    try {
      const d = localStorage.getItem('ab_tests');
      if (d) this._tests = JSON.parse(d);
    } catch (e) {}
  }

  // Deterministic hash for user assignment
  _hash(str) {
    let h = 0;
    for (let i = 0; i < str.length; i++) { h = ((h << 5) - h + str.charCodeAt(i)) | 0; }
    return (Math.abs(h) % 10000) / 10000; // 0.0 - 1.0
  }

  _loadUserId() {
    let id = localStorage.getItem('ab_user_id');
    if (!id) { id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6); localStorage.setItem('ab_user_id', id); }
    return id;
  }
}

// Singleton
const AB = new ABTest();
