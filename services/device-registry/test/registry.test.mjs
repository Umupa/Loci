import assert from 'node:assert/strict';
import test from 'node:test';
import { DeviceGroup } from '../src/group.mjs';
import { createDevice, createGroup, MemoryStorage, recordFor } from '../test-support/helpers.mjs';

const NOW = 1_760_000_000_000;

function setup() {
    const group = createGroup();
    return { group, registry: new DeviceGroup(group.groupId, new MemoryStorage()) };
}

function put(registry, group, record, now = NOW) {
    return registry.putDevice({ record, sig: group.sign('device', record) }, record.deviceId, now);
}

function remove(registry, group, deviceId, removedAt = NOW) {
    const removal = { deviceId, removedAt };
    return registry.removeDevice({ removal, sig: group.sign('removal', removal) }, deviceId, removedAt);
}

function beat(registry, device, ts = NOW, route) {
    const body = { deviceId: device.deviceId, ts, ...(route === undefined ? {} : { route }) };
    return registry.heartbeat({ beat: body, sig: device.sign('heartbeat', body) }, device.deviceId, ts);
}

async function rejects(promise, status, pattern) {
    await assert.rejects(promise, error => {
        assert.equal(error.status, status);
        if (pattern) assert.match(error.message, pattern);
        return true;
    });
}

test('a group-signed record joins the group and appears in the list', async () => {
    const { group, registry } = setup();
    const device = createDevice('Mac mini');
    const record = recordFor(device, NOW);
    const sig = group.sign('device', record);

    assert.deepEqual(await registry.putDevice({ record, sig }, device.deviceId, NOW), { ok: true });
    assert.deepEqual(await registry.list(), {
        devices: [{ record, sig, lastSeen: null, route: null }],
        removals: [],
    });
});

test('an unknown group has an empty list', async () => {
    const { registry } = setup();
    assert.deepEqual(await registry.list(), { devices: [], removals: [] });
});

test('a signature from a different group or key is rejected', async () => {
    const { registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);

    await rejects(
        registry.putDevice({ record, sig: createGroup(Buffer.alloc(32, 9)).sign('device', record) }, device.deviceId, NOW),
        401,
        /group signature/
    );
    await rejects(
        registry.putDevice({ record, sig: device.sign('device', record) }, device.deviceId, NOW),
        401,
        /group signature/
    );
    await rejects(
        registry.putDevice({ record, sig: createGroup().sign('heartbeat', record) }, device.deviceId, NOW),
        401,
        /group signature/
    );
});

test('a record changed after signing is rejected', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);
    const sig = group.sign('device', record);

    await rejects(registry.putDevice({ record: { ...record, name: 'Other' }, sig }, device.deviceId, NOW), 401);
    await rejects(registry.putDevice({ record: { ...record, platform: 'linux' }, sig }, device.deviceId, NOW), 401);
});

test('the path, the record id and the public key must agree', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const other = createDevice('Other');
    const record = recordFor(device, NOW);
    const sig = group.sign('device', record);

    await rejects(registry.putDevice({ record, sig }, other.deviceId, NOW), 400, /does not match the URL/);

    const forged = { ...record, deviceId: 'AAAAAAAAAAAAAAAAAAAAAA' };
    await rejects(
        registry.putDevice({ record: forged, sig: group.sign('device', forged) }, forged.deviceId, NOW),
        400,
        /devicePubKey/
    );

    const malformed = { ...record, devicePubKey: 'short' };
    await rejects(
        registry.putDevice({ record: malformed, sig: group.sign('device', malformed) }, device.deviceId, NOW),
        400,
        /32-byte/
    );
});

test('record timestamps outside five minutes are rejected', async () => {
    const { group, registry } = setup();
    const device = createDevice();

    for (const addedAt of [NOW - 5 * 60 * 1000 - 1, NOW + 5 * 60 * 1000 + 1]) {
        const record = recordFor(device, addedAt);
        await rejects(put(registry, group, record), 409, /5 minute/);
    }
});

test('malformed bodies are rejected with 400', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);
    const sig = group.sign('device', record);

    await rejects(registry.putDevice(null, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record, sig: '' }, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record: null, sig }, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record: { ...record, name: '' }, sig }, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record: { ...record, platform: 1 }, sig }, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record: { ...record, addedAt: 'now' }, sig }, device.deviceId, NOW), 400);
    await rejects(registry.putDevice({ record: { ...record, deviceId: 'short' }, sig }, device.deviceId, NOW), 400);
});

test('removal deletes the device and keeps a verifiable tombstone', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);
    await put(registry, group, record);

    const removal = { deviceId: device.deviceId, removedAt: NOW + 1000 };
    const sig = group.sign('removal', removal);
    assert.deepEqual(
        await registry.removeDevice({ removal, sig }, device.deviceId, NOW + 1000),
        { ok: true }
    );
    assert.deepEqual(await registry.list(), {
        devices: [],
        removals: [{ removal, sig }],
    });
});

test('a removal signed by the device or another group is rejected', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    await put(registry, group, recordFor(device, NOW));
    const removal = { deviceId: device.deviceId, removedAt: NOW };

    await rejects(
        registry.removeDevice({ removal, sig: device.sign('removal', removal) }, device.deviceId, NOW),
        401,
        /group signature/
    );
    await rejects(
        registry.removeDevice(
            { removal, sig: createGroup(Buffer.alloc(32, 9)).sign('removal', removal) },
            device.deviceId,
            NOW
        ),
        401,
        /group signature/
    );
});

test('a stale or mismatched removal is rejected', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const other = createDevice('Other');
    await put(registry, group, recordFor(device, NOW));

    const stale = { deviceId: device.deviceId, removedAt: NOW - 5 * 60 * 1000 - 1 };
    await rejects(
        registry.removeDevice({ removal: stale, sig: group.sign('removal', stale) }, device.deviceId, NOW),
        409,
        /5 minute/
    );

    const wrongPath = { deviceId: device.deviceId, removedAt: NOW };
    await rejects(
        registry.removeDevice(
            { removal: wrongPath, sig: group.sign('removal', wrongPath) },
            other.deviceId,
            NOW
        ),
        400,
        /does not match the URL/
    );
});

test('a removed device cannot rejoin, even with a newer record', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);
    await put(registry, group, record);
    await remove(registry, group, device.deviceId, NOW + 1000);

    // Replaying the original record.
    await rejects(put(registry, group, record, NOW + 2000), 409, /cannot rejoin/);

    // A fresh record signed now does not lift the ban either.
    const again = recordFor({ ...device, name: 'Renamed' }, NOW + 1500);
    await rejects(put(registry, group, again, NOW + 2000), 409, /cannot rejoin/);

    const listed = await registry.list();
    assert.equal(listed.devices.length, 0);
    assert.equal(listed.removals.length, 1);

    await rejects(beat(registry, device, NOW + 2000), 404, /Unknown device/);
});

test('a removed device key stays banned, while a new device key can join', async () => {
    const { group, registry } = setup();
    const removed = createDevice('Old Mac mini');
    await put(registry, group, recordFor(removed, NOW));
    await remove(registry, group, removed.deviceId, NOW + 1000);

    await rejects(put(registry, group, recordFor(removed, NOW + 2000), NOW + 2000), 409, /cannot rejoin/);

    // The same machine with a new key is a new device.
    const replacement = createDevice('Mac mini');
    await put(registry, group, recordFor(replacement, NOW + 2000), NOW + 2000);
    const listed = await registry.list();
    assert.deepEqual(
        listed.devices.map(entry => entry.record.deviceId),
        [replacement.deviceId]
    );
    assert.deepEqual(
        listed.removals.map(entry => entry.removal.deviceId),
        [removed.deviceId]
    );
});

test('a repeated removal keeps the first tombstone', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const record = recordFor(device, NOW);
    await put(registry, group, record);
    await remove(registry, group, device.deviceId, NOW + 1000);

    const later = { deviceId: device.deviceId, removedAt: NOW + 2000 };
    await registry.removeDevice(
        { removal: later, sig: group.sign('removal', later) },
        device.deviceId,
        NOW + 2000
    );

    const listed = await registry.list();
    assert.equal(listed.removals.length, 1);
    assert.equal(listed.removals[0].removal.removedAt, NOW + 1000);
});

test('a heartbeat updates lastSeen and route, and only the device can sign it', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    const other = createDevice('Other');
    await put(registry, group, recordFor(device, NOW));

    assert.deepEqual(await beat(registry, device, NOW + 100, 'wss://relay.example/c/abc'), {
        ok: true,
        lastSeen: NOW + 100,
        route: 'wss://relay.example/c/abc',
    });
    let listed = await registry.list();
    assert.equal(listed.devices[0].lastSeen, NOW + 100);
    assert.equal(listed.devices[0].route, 'wss://relay.example/c/abc');

    const body = { deviceId: device.deviceId, ts: NOW + 200 };
    await rejects(
        registry.heartbeat({ beat: body, sig: other.sign('heartbeat', body) }, device.deviceId, NOW + 200),
        401,
        /device signature/
    );
    await rejects(
        registry.heartbeat({ beat: body, sig: group.sign('heartbeat', body) }, device.deviceId, NOW + 200),
        401,
        /device signature/
    );

    assert.deepEqual(await beat(registry, device, NOW + 300), {
        ok: true,
        lastSeen: NOW + 300,
        route: null,
    });
    listed = await registry.list();
    assert.equal(listed.devices[0].route, null);
});

test('heartbeat edge cases: unknown device, stale beat, mismatch, tampering', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    await put(registry, group, recordFor(device, NOW));

    const stranger = createDevice('Stranger');
    await rejects(beat(registry, stranger, NOW), 404, /Unknown device/);

    const stale = { deviceId: device.deviceId, ts: NOW - 5 * 60 * 1000 - 1 };
    await rejects(
        registry.heartbeat({ beat: stale, sig: device.sign('heartbeat', stale) }, device.deviceId, NOW),
        409,
        /5 minute/
    );

    const wrongPath = { deviceId: device.deviceId, ts: NOW };
    await rejects(
        registry.heartbeat(
            { beat: wrongPath, sig: device.sign('heartbeat', wrongPath) },
            stranger.deviceId,
            NOW
        ),
        400,
        /does not match the URL/
    );

    const body = { deviceId: device.deviceId, ts: NOW, route: 'r' };
    await rejects(
        registry.heartbeat(
            { beat: { ...body, route: 'other' }, sig: device.sign('heartbeat', body) },
            device.deviceId,
            NOW
        ),
        401,
        /device signature/
    );
});

test('updating a device keeps its last heartbeat', async () => {
    const { group, registry } = setup();
    const device = createDevice();
    await put(registry, group, recordFor(device, NOW));
    await beat(registry, device, NOW + 100, 'route');

    const renamed = recordFor({ ...device, name: 'New name' }, NOW + 200);
    await put(registry, group, renamed, NOW + 200);
    const [stored] = (await registry.list()).devices;
    assert.equal(stored.record.name, 'New name');
    assert.equal(stored.lastSeen, NOW + 100);
    assert.equal(stored.route, 'route');
});

test('devices are listed in a stable order', async () => {
    const { group, registry } = setup();
    for (const name of ['C', 'A', 'B']) {
        const device = createDevice(name);
        await put(registry, group, recordFor(device, NOW));
    }
    const ids = (await registry.list()).devices.map(entry => entry.record.deviceId);
    assert.deepEqual(ids, [...ids].sort());
});
