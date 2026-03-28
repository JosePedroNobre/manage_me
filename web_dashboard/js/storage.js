// ── Local Storage + Offline Cache ──────────────────────────────

const DB_NAME = 'manageme';
const DB_VERSION = 1;

let _db = null;

function openDB() {
  if (_db) return Promise.resolve(_db);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('cache')) {
        db.createObjectStore('cache', { keyPath: 'key' });
      }
    };
    req.onsuccess = () => { _db = req.result; resolve(_db); };
    req.onerror = () => reject(req.error);
  });
}

export async function cacheSet(key, data, ttlMs = 5 * 60 * 1000) {
  const db = await openDB();
  const tx = db.transaction('cache', 'readwrite');
  tx.objectStore('cache').put({ key, data, expiresAt: Date.now() + ttlMs });
  return new Promise(r => { tx.oncomplete = r; });
}

export async function cacheGet(key) {
  const db = await openDB();
  return new Promise((resolve) => {
    const tx = db.transaction('cache', 'readonly');
    const req = tx.objectStore('cache').get(key);
    req.onsuccess = () => {
      const row = req.result;
      if (!row) return resolve(null);
      if (Date.now() > row.expiresAt) return resolve(null); // expired
      resolve(row.data);
    };
    req.onerror = () => resolve(null);
  });
}

// ── Token helpers (localStorage — never leaves the device) ────

export function saveTokens(tokens) {
  localStorage.setItem('mm_tokens', JSON.stringify(tokens));
}

export function loadTokens() {
  try {
    return JSON.parse(localStorage.getItem('mm_tokens')) || {};
  } catch {
    return {};
  }
}

export function clearTokens() {
  localStorage.removeItem('mm_tokens');
}

// ── Settings ──────────────────────────────────────────────────

export function saveSettings(s) {
  localStorage.setItem('mm_settings', JSON.stringify(s));
}

export function loadSettings() {
  try {
    return JSON.parse(localStorage.getItem('mm_settings')) || {};
  } catch {
    return {};
  }
}
