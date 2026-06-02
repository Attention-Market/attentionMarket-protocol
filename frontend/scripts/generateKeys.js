import { webcrypto } from 'crypto';
const { subtle } = webcrypto;

async function generateWebCryptoKeys() {
  try {
    // 1. Generate an ECDH P-256 key pair
    const keyPair = await subtle.generateKey(
      { name: "ECDH", namedCurve: "P-256" },
      true, // extractable
      ["deriveKey"]
    );

    // 2. Export Public Key to 'raw' (65 bytes uncompressed)
    const rawPub = await subtle.exportKey("raw", keyPair.publicKey);
    const base64PublicKey = Buffer.from(rawPub).toString('base64');

    // 3. Export Private Key to 'pkcs8' (standard for private keys)
    const rawPriv = await subtle.exportKey("pkcs8", keyPair.privateKey);
    const base64PrivateKey = Buffer.from(rawPriv).toString('base64');

    // Output formatted for your environment variables
    console.log("=== FOR YOUR BROWSER .env ===");
    console.log(`PUBLIC_KEY="${base64PublicKey}"`);
    console.log("\n=== FOR YOUR BACKEND / CONSUMER .env ===");
    console.log(`PRIVATE_KEY="${base64PrivateKey}"`);

  } catch (error) {
    console.error("Failed to generate keys:", error);
  }
}

generateWebCryptoKeys();