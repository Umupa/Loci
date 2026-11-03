import assert from 'node:assert/strict';
import test from 'node:test';
import {
    RegistryError,
    b64urlDecode,
    b64urlEncode,
    canonicalJson,
    deviceIdFor,
    isFresh,
    signingMessage,
    verifySignature,
} from '../src/protocol.mjs';
import { createDevice, createDeviceFromSeed, createGroup, recordFor } from '../test-support/helpers.mjs';

test('canonicalJson sorts every object level and drops whitespace', () => {
    assert.equal(
        canonicalJson({ b: 1, a: { d: 2, c: [3, { z: 1, y: 2 }] } }),
        '{"a":{"c":[3,{"y":2,"z":1}],"d":2},"b":1}'
    );
    assert.equal(canonicalJson({ b: 1, 10: 2, 2: 3 }), '{"10":2,"2":3,"b":1}');
    assert.equal(canonicalJson({ a: undefined, b: null }), '{"b":null}');
    assert.equal(canonicalJson([undefined, 1, 'x']), '[null,1,"x"]');
    assert.equal(canonicalJson('a\nb'), '"a\\nb"');
});

test('signingMessage is the protocol prefix plus canonical JSON', () => {
    const message = new TextDecoder().decode(signingMessage('device', { b: 1, a: 2 }));
    assert.equal(message, 'loci-registry-v1\ndevice\n{"a":2,"b":1}');
});

test('base64url round-trips without padding and rejects other alphabets', () => {
    const bytes = new Uint8Array([0xfb, 0xff, 0x00, 0x01]);
    const encoded = b64urlEncode(bytes);
    assert.equal(encoded, '-_8AAQ');
    assert.deepEqual(b64urlDecode(encoded), bytes);
    assert.throws(() => b64urlDecode('abc='), TypeError);
    assert.throws(() => b64urlDecode('a'), TypeError);
    assert.throws(() => b64urlDecode('ab+c'), TypeError);
});

test('deviceIdFor hashes raw public key bytes and truncates to 22 chars', async () => {
    const device = createDevice();
    assert.equal(device.deviceId.length, 22);
    assert.equal(await deviceIdFor(device.devicePubKey), device.deviceId);

    const other = createDevice('Other');
    assert.notEqual(await deviceIdFor(other.devicePubKey), device.deviceId);
    await assert.rejects(deviceIdFor('not-a-key'), error => error.status === 400);
});

test('Ed25519 signatures cover type and canonical payload', async () => {
    const group = createGroup();
    const device = createDevice();
    const record = recordFor(device, 1_760_000_000_000);
    const signature = group.sign('device', record);

    assert.equal(await verifySignature(group.groupId, 'device', record, signature), true);
    assert.equal(await verifySignature(group.groupId, 'heartbeat', record, signature), false);
    assert.equal(await verifySignature(group.groupId, 'device', { ...record, name: 'x' }, signature), false);
    assert.equal(await verifySignature(device.devicePubKey, 'device', record, signature), false);
    assert.equal(await verifySignature(group.groupId, 'device', record, 'AAAA'), false);
});

test('the same group secret derives the same group id', () => {
    const secret = Buffer.from('6f'.repeat(32), 'hex');
    assert.equal(createGroup(secret).groupId, createGroup(secret).groupId);
    assert.notEqual(createGroup(secret).groupId, createGroup().groupId);
});

test('fixed key vectors match the client contract', async () => {
    const secret = Buffer.from(Array.from({ length: 32 }, (_, i) => i));
    assert.equal(createGroup(secret).groupId, 'ExRtSEDuWwz95AeKeMbsJ8_8BLBzRTU4aZ-UExezVuc');

    const device = createDeviceFromSeed(secret);
    assert.equal(device.devicePubKey, 'A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg');
    assert.equal(device.deviceId, 'Vkdap1RjR0wChd9dvyvKtz');
    assert.equal(await deviceIdFor(device.devicePubKey), device.deviceId);
});

test('isFresh accepts the five minute window and rejects anything outside', () => {
    const now = 1_760_000_000_000;
    assert.equal(isFresh(now, now), true);
    assert.equal(isFresh(now - 5 * 60 * 1000, now), true);
    assert.equal(isFresh(now + 5 * 60 * 1000, now), true);
    assert.equal(isFresh(now - 5 * 60 * 1000 - 1, now), false);
    assert.equal(isFresh(now + 5 * 60 * 1000 + 1, now), false);
    assert.equal(isFresh(now + 0.5, now), false);
});

test('RegistryError carries an HTTP status', () => {
    const error = new RegistryError(409, 'stale');
    assert.equal(error.status, 409);
    assert.equal(error.message, 'stale');
});
