/* ═══════ Dashboard Data Hook ═══════
 * Auto-fetch + cache + polling + error handling + loading state
 * Usage: const { data, loading, error, refetch } = useData('/api/analytics/sales'); */

import { useState, useEffect, useCallback, useRef } from 'react';

export function useData(url, options = {}) {
  const { pollMs = 0, cacheMs = 30000, enabled = true } = options;
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const cache = useRef({});

  const fetchData = useCallback(async () => {
    // Check cache
    const cached = cache.current[url];
    if (cached && Date.now() - cached.time < cacheMs) {
      setData(cached.data);
      setLoading(false);
      return;
    }
    try {
      setLoading(true);
      const res = await fetch(url);
      if (!res.ok) throw new Error(`${res.status}`);
      const json = await res.json();
      cache.current[url] = { data: json, time: Date.now() };
      setData(json);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [url, cacheMs]);

  useEffect(() => {
    if (!enabled) return;
    fetchData();
    if (pollMs > 0) {
      const timer = setInterval(fetchData, pollMs);
      return () => clearInterval(timer);
    }
  }, [fetchData, pollMs, enabled]);

  return { data, loading, error, refetch: fetchData };
}
