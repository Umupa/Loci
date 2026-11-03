import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, hkdfSync, sign } from 'node:crypto';
import { b64urlEncode, signingMessage } from '../src/protocol.mjs';

// An Ed25519 private key is this PKCS#8 wrapper around the 32-byte seed.
const PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');

const rawPublicKey = key => key.export({ format: 'der', type: 'spki' }).subarray(-32);
const signWith = (key, type, payload) => b64urlEncode(sign(null, signingMessage(type, payload), key));

/**
 * The group key the client derives: seed = HKDF-SHA256(groupSecret, "", info, 32),
 * groupId = base64url(Ed25519 public key).
 */
export function createGroup(secret = Buffer.alloc(32, 7)) {
    const seed = Buffer.from(hkdfSync('sha256', secret, Buffer.alloc(0), 'loci-group-sign-v1', 32));
    const privateKey = createPrivateKey({
        key: Buffer.concat([PKCS8_PREFIX, seed]),
        format: 'der',
        type: 'pkcs8',
    });
    const publicKey = createPublicKey(privateKey);
    return {
        groupId: b64urlEncode(rawPublicKey(publicKey)),
        sign: (type, payload) => signWith(privateKey, type, payload),
    };
}

export function createDevice(name = 'MacBook') {
    const { privateKey } = generateKeyPairSync('ed25519');
    return deviceFromKey(privateKey, name);
}

/** A deterministic device for fixed test vectors; `seed` is 32 bytes. */
export function createDeviceFromSeed(seed, name = 'Fixed') {
    const privateKey = createPrivateKey({
        key: Buffer.concat([PKCS8_PREFIX, seed]),
        format: 'der',
        type: 'pkcs8',
    });
    return deviceFromKey(privateKey, name);
}

function deviceFromKey(privateKey, name) {
    const raw = rawPublicKey(createPublicKey(privateKey));
    return {
        name,
        platform: 'macOS',
        devicePubKey: b64urlEncode(raw),
        // Independent of protocol.mjs: sha256 over the raw key, base64url, 22 chars.
        deviceId: b64urlEncode(createHash('sha256').update(raw).digest()).slice(0, 22),
        sign: (type, payload) => signWith(privateKey, type, payload),
    };
}

export function recordFor(device, addedAt, overrides = {}) {
    return {
        deviceId: device.deviceId,
        name: device.name,
        devicePubKey: device.devicePubKey,
        platform: device.platform,
        addedAt,
        ...overrides,
    };
}

export class MemoryStorage {
    constructor() {
        this.map = new Map();
    }

    async get(key) {
        return this.map.get(key);
    }

    async put(key, value) {
        this.map.set(key, structuredClone(value));
    }

    async delete(key) {
        this.map.delete(key);
    }

    async list(prefix) {
        return [...this.map]
            .filter(([key]) => key.startsWith(prefix))
            .map(([key, value]) => [key, structuredClone(value)]);
    }
}
