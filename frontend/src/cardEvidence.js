import { keccak256 } from 'ethers';

const DB_NAME = 'pokevault-evidence';
const STORE_NAME = 'files';
const PROFILE_PREFIX = 'pokevault:card-profile:';

function openEvidenceDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE_NAME);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function storeFile(key, file) {
  const db = await openEvidenceDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(file, key);
    tx.oncomplete = () => { db.close(); resolve(); };
    tx.onerror = () => { db.close(); reject(tx.error); };
  });
}

export async function saveCardProfile(profileId, profile, files) {
  for (const [kind, file] of Object.entries(files)) {
    if (file) await storeFile(`${profileId}:${kind}`, file);
  }
  localStorage.setItem(`${PROFILE_PREFIX}${profileId}`, JSON.stringify(profile));
}

export function getCardProfile(profileId) {
  const value = localStorage.getItem(`${PROFILE_PREFIX}${profileId}`);
  return value ? JSON.parse(value) : null;
}

export function listCardProfiles() {
  const profiles = [];
  for (let i = 0; i < localStorage.length; i += 1) {
    const key = localStorage.key(i);
    if (key?.startsWith(PROFILE_PREFIX)) {
      try { profiles.push(JSON.parse(localStorage.getItem(key))); } catch { /* ignore invalid local records */ }
    }
  }
  return profiles;
}

export async function getEvidenceFile(profileId, kind) {
  const db = await openEvidenceDb();
  const file = await new Promise((resolve, reject) => {
    const request = db.transaction(STORE_NAME, 'readonly').objectStore(STORE_NAME).get(`${profileId}:${kind}`);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return file || null;
}

export async function getEvidenceUrl(profileId, kind) {
  const file = await getEvidenceFile(profileId, kind);
  return file ? URL.createObjectURL(file) : '';
}

export async function hashFile(file) {
  if (!file) return '';
  return keccak256(new Uint8Array(await file.arrayBuffer()));
}
