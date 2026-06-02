// encrypt.js — Browser (WebCrypto)
// Env var: PUBLIC_KEY — Base64-encoded raw P-256 public key (65 bytes uncompressed)
//
// Usage:
//   const result = await encryptEmail('user@example.com');
//   // result = { ephemeralPublicKey: '...', iv: '...', ciphertext: '...' }
//   // All fields are Base64 strings, safe to store as-is on SUI.

const PUBLIC_KEY = import.meta.env.PUBLIC_KEY; // e.g. Vite/Astro
// If using plain HTML, replace with:
// const PUBLIC_KEY = window.ENV_PUBLIC_KEY;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function base64ToBytes(b64) {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function bytesToBase64(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)));
}

// ---------------------------------------------------------------------------
// Import the recipient's static public key from the env var
// ---------------------------------------------------------------------------

async function importRecipientPublicKey() {
  const raw = base64ToBytes(PUBLIC_KEY);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [] // public keys have no key usages in ECDH
  );
}

// ---------------------------------------------------------------------------
// Core encrypt function
// ---------------------------------------------------------------------------

/**
 * Encrypts a plain-text email address.
 *
 * @param {string} email - The email address to encrypt.
 * @returns {Promise<{ ephemeralPublicKey: string, iv: string, ciphertext: string }>}
 *   All values are Base64 strings ready to be stored on SUI.
 */
export async function encryptEmail(email) {
  // 1. Import recipient's static public key
  const recipientPublicKey = await importRecipientPublicKey();

  // 2. Generate a one-time ephemeral key pair (never reused)
  const ephemeralKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true, // extractable so we can export the public half
    ["deriveKey"]
  );

  // 3. Derive a shared AES-256-GCM key via ECDH
  const aesKey = await crypto.subtle.deriveKey(
    { name: "ECDH", public: recipientPublicKey },
    ephemeralKeyPair.privateKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"]
  );

  // 4. Encrypt the email with a random 96-bit IV
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    aesKey,
    new TextEncoder().encode(email)
  );

  // 5. Export the ephemeral public key (raw = 65 bytes uncompressed P-256)
  const ephemeralPublicKeyRaw = await crypto.subtle.exportKey(
    "raw",
    ephemeralKeyPair.publicKey
  );

  // 6. Return everything as Base64 — these three blobs go on-chain
  return {
    ephemeralPublicKey: bytesToBase64(ephemeralPublicKeyRaw),
    iv: bytesToBase64(iv),
    ciphertext: bytesToBase64(ciphertext),
  };
}

// ---------------------------------------------------------------------------
// Example (remove in production)
// ---------------------------------------------------------------------------

// encryptEmail("user@example.com").then(console.log);