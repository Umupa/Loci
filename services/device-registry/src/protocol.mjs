// Wire format and signature checks for the device registry.
//
// Everything here uses standard globals and WebCrypto only, so the Worker and
// `node --test` run the same code. The registry stores signed records and
// never holds a private key: clients verify what they read.

export const PROTOCOL = 'loci-registry-v1';
export const FRESHNESS_MS = 5 * 60 * 1000;
export const DEVICE_ID_LENGTH = 22;

const encoder = new TextEncoder();
const B64URL = /^[A-Za-z0-9_-]*$/;

export class RegistryError extends Error {
    constructor(status, message) {
        super(message);
        this.name = 'RegistryError';
        this.status = status;
    }
}

export const badRequest = message => new RegistryError(400, message);
export const unauthorized = message => new RegistryError(401, message);
export const notFound = message => new RegistryError(404, message);
export const conflict = message => new RegistryError(409, message);

/**
 * JSON with object keys in lexicographic order and no whitespace. Written by
 * hand because JSON.stringify reorders integer-like keys numerically.
 */
export function canonicalJson(value) {
    const json = encodeValue(value);
    if (json === undefined) throw new TypeError('Value is not JSON');
    return json;
}

function encodeValue(value) {
    if (value === null) return 'null';
    switch (typeof value) {
        case 'boolean':
            return value ? 'true' : 'false';
        case 'number':
            return Number.isFinite(value) ? JSON.stringify(value) : 'null';
        case 'string':
            return JSON.stringify(value);
        case 'object': {
            if (Array.isArray(value)) {
                return `[${value.map(item => encodeValue(item) ?? 'null').join(',')}]`;
            }
            const parts = [];
            for (const key of Object.keys(value).sort()) {
                const encoded = encodeValue(value[key]);
                if (encoded !== undefined) parts.push(`${JSON.stringify(key)}:${encoded}`);
            }
            return `{${parts.join(',')}}`;
        }
        default:
            return undefined;
    }
}

/** The exact bytes an Ed25519 key signs. */
export function signingMessage(type, payload) {
    return encoder.encode(`${PROTOCOL}\n${type}\n${canonicalJson(payload)}`);
}

export function b64urlEncode(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Strict, unpadded base64url. Throws on anything else. */
export function b64urlDecode(text) {
    if (typeof text !== 'string' || !B64URL.test(text) || text.length % 4 === 1) {
        throw new TypeError('Invalid base64url');
    }
    const base64 = text.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4));
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
}

/** The decoded bytes when `text` is base64url for exactly `length` bytes, else null. */
export function b64urlBytes(text, length) {
    if (typeof text !== 'string') return null;
    try {
        const bytes = b64urlDecode(text);
        return bytes.length === length ? bytes : null;
    } catch {
        return null;
    }
}

export function isDeviceId(value) {
    return typeof value === 'string' && value.length === DEVICE_ID_LENGTH && B64URL.test(value);
}

/** `base64url(sha256(raw public key))` truncated; the key is stored base64url. */
export async function deviceIdFor(devicePubKey) {
    const bytes = b64urlBytes(devicePubKey, 32);
    if (!bytes) throw badRequest('devicePubKey must be a 32-byte base64url Ed25519 public key');
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return b64urlEncode(new Uint8Array(digest)).slice(0, DEVICE_ID_LENGTH);
}

/** Ed25519 over `loci-registry-v1\n<type>\n<canonical JSON>`. */
export async function verifySignature(publicKey, type, payload, signature) {
    const keyBytes = b64urlBytes(publicKey, 32);
    const sigBytes = b64urlBytes(signature, 64);
    if (!keyBytes || !sigBytes) return false;
    try {
        const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'Ed25519' }, false, ['verify']);
        return await crypto.subtle.verify({ name: 'Ed25519' }, key, sigBytes, signingMessage(type, payload));
    } catch {
        return false;
    }
}

/** Timestamps are epoch milliseconds; both old and future values are bounded. */
export function isFresh(timestamp, now, windowMs = FRESHNESS_MS) {
    return Number.isSafeInteger(timestamp) && Math.abs(now - timestamp) <= windowMs;
}

export function safeEqual(a, b) {
    const x = encoder.encode(String(a));
    const y = encoder.encode(String(b));
    if (x.length !== y.length) return false;
    let diff = 0;
    for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
    return diff === 0;
}

function asObject(value, what) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
        throw badRequest(`${what} must be an object`);
    }
    return value;
}

function asString(value, what, { allowEmpty = false } = {}) {
    if (typeof value !== 'string' || (!allowEmpty && value.length === 0)) {
        throw badRequest(`${what} must be a ${allowEmpty ? '' : 'non-empty '}string`);
    }
    return value;
}

export async function validateDeviceRecord(record, pathDeviceId) {
    asObject(record, 'record');
    const deviceId = asString(record.deviceId, 'record.deviceId');
    if (!isDeviceId(deviceId)) throw badRequest('record.deviceId is malformed');
    if (deviceId !== pathDeviceId) throw badRequest('record.deviceId does not match the URL');
    asString(record.name, 'record.name');
    asString(record.devicePubKey, 'record.devicePubKey');
    asString(record.platform, 'record.platform');
    if (!Number.isSafeInteger(record.addedAt)) throw badRequest('record.addedAt must be epoch milliseconds');
    if ((await deviceIdFor(record.devicePubKey)) !== deviceId) {
        throw badRequest('record.deviceId does not match record.devicePubKey');
    }
    return record;
}

export function validateRemoval(removal, pathDeviceId) {
    asObject(removal, 'removal');
    const deviceId = asString(removal.deviceId, 'removal.deviceId');
    if (!isDeviceId(deviceId)) throw badRequest('removal.deviceId is malformed');
    if (deviceId !== pathDeviceId) throw badRequest('removal.deviceId does not match the URL');
    if (!Number.isSafeInteger(removal.removedAt)) throw badRequest('removal.removedAt must be epoch milliseconds');
    return removal;
}

export function validateBeat(beat, pathDeviceId) {
    asObject(beat, 'beat');
    const deviceId = asString(beat.deviceId, 'beat.deviceId');
    if (!isDeviceId(deviceId)) throw badRequest('beat.deviceId is malformed');
    if (deviceId !== pathDeviceId) throw badRequest('beat.deviceId does not match the URL');
    if (!Number.isSafeInteger(beat.ts)) throw badRequest('beat.ts must be epoch milliseconds');
    if (beat.route !== undefined) asString(beat.route, 'beat.route', { allowEmpty: true });
    return beat;
}

/** Parse a request body, or throw the registry's 400. */
export function parseJson(text) {
    try {
        return JSON.parse(text);
    } catch {
        throw badRequest('Body must be JSON');
    }
}

export { asObject, asString };
