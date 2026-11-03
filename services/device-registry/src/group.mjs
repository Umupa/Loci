// Group state machine, independent of Workers. `storage` is a small async map:
// get(key), put(key, value), delete(key), list(prefix) -> [[key, value], ...].
// The Worker backs it with a Durable Object's SQLite storage; tests use a Map.

import {
    asObject,
    asString,
    conflict,
    isFresh,
    notFound,
    unauthorized,
    validateBeat,
    validateDeviceRecord,
    validateRemoval,
    verifySignature,
} from './protocol.mjs';

const deviceKey = deviceId => `device:${deviceId}`;
const removalKey = deviceId => `removal:${deviceId}`;
const byDeviceId = (a, b) => (a.deviceId < b.deviceId ? -1 : a.deviceId > b.deviceId ? 1 : 0);

export class DeviceGroup {
    constructor(groupId, storage) {
        this.groupId = groupId;
        this.storage = storage;
    }

    async list() {
        const devices = (await this.storage.list('device:')).map(([, value]) => value);
        const removals = (await this.storage.list('removal:')).map(([, value]) => value);
        devices.sort((a, b) => byDeviceId(a.record, b.record));
        removals.sort((a, b) => byDeviceId(a.removal, b.removal));
        return { devices, removals };
    }

    async putDevice(body, pathDeviceId, now = Date.now()) {
        const { record, sig } = await this.#signedDevice(body, pathDeviceId);
        if (!isFresh(record.addedAt, now)) {
            throw conflict('record.addedAt is outside the 5 minute window');
        }
        // Removal is permanent for a key: only a new device key can join.
        const tombstone = await this.storage.get(removalKey(pathDeviceId));
        if (tombstone) {
            throw conflict('This device was removed and cannot rejoin; use a new device key');
        }
        const current = await this.storage.get(deviceKey(pathDeviceId));
        await this.storage.put(deviceKey(pathDeviceId), {
            record,
            sig,
            lastSeen: current?.lastSeen ?? null,
            route: current?.route ?? null,
        });
        return { ok: true };
    }

    async removeDevice(body, pathDeviceId, now = Date.now()) {
        const envelope = asObject(body, 'body');
        const removal = validateRemoval(envelope.removal, pathDeviceId);
        const sig = asString(envelope.sig, 'sig');
        if (!(await verifySignature(this.groupId, 'removal', removal, sig))) {
            throw unauthorized('Invalid group signature');
        }
        if (!isFresh(removal.removedAt, now)) {
            throw conflict('removal.removedAt is outside the 5 minute window');
        }
        // Keep the first tombstone: a replay must not move the removal time.
        const existing = await this.storage.get(removalKey(pathDeviceId));
        if (!existing) await this.storage.put(removalKey(pathDeviceId), { removal, sig });
        await this.storage.delete(deviceKey(pathDeviceId));
        return { ok: true };
    }

    async heartbeat(body, pathDeviceId, now = Date.now()) {
        const envelope = asObject(body, 'body');
        const beat = validateBeat(envelope.beat, pathDeviceId);
        const sig = asString(envelope.sig, 'sig');
        const stored = await this.storage.get(deviceKey(pathDeviceId));
        if (!stored) throw notFound('Unknown device');
        if (!(await verifySignature(stored.record.devicePubKey, 'heartbeat', beat, sig))) {
            throw unauthorized('Invalid device signature');
        }
        if (!isFresh(beat.ts, now)) {
            throw conflict('beat.ts is outside the 5 minute window');
        }
        const route = beat.route ?? null;
        await this.storage.put(deviceKey(pathDeviceId), { ...stored, lastSeen: beat.ts, route });
        return { ok: true, lastSeen: beat.ts, route };
    }

    async #signedDevice(body, pathDeviceId) {
        const envelope = asObject(body, 'body');
        const record = await validateDeviceRecord(envelope.record, pathDeviceId);
        const sig = asString(envelope.sig, 'sig');
        if (!(await verifySignature(this.groupId, 'device', record, sig))) {
            throw unauthorized('Invalid group signature');
        }
        return { record, sig };
    }
}
