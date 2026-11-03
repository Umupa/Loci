// Loci device registry: one Durable Object per device group, named by its
// groupId. The registry only verifies and stores signed records; clients
// re-verify everything they read.

import { DurableObject } from 'cloudflare:workers';
import { DeviceGroup } from './group.mjs';
import { RegistryError, b64urlBytes, isDeviceId, parseJson, safeEqual } from './protocol.mjs';

const json = (status, body) =>
    new Response(JSON.stringify(body), {
        status,
        headers: { 'content-type': 'application/json; charset=utf-8' },
    });

const ROUTE = /^\/g\/([^/]+)\/devices(?:\/([^/]+))?(\/heartbeat)?\/?$/;

function routeOf(pathname) {
    const match = ROUTE.exec(pathname);
    if (!match) return null;
    const [, groupId, deviceId, heartbeat] = match;
    if (heartbeat) return deviceId ? { groupId, deviceId, kind: 'heartbeat' } : null;
    return deviceId ? { groupId, deviceId, kind: 'device' } : { groupId, kind: 'collection' };
}

function opFor(route, method) {
    if (route.kind === 'collection') return method === 'GET' ? 'list' : null;
    if (route.kind === 'heartbeat') return method === 'POST' ? 'heartbeat' : null;
    if (method === 'PUT') return 'put';
    if (method === 'DELETE') return 'remove';
    return null;
}

function accessDenied(request, env) {
    if (!env.REGISTRY_KEY) return null;
    const match = /^Bearer\s+(.+)$/i.exec(request.headers.get('authorization') || '');
    return match && safeEqual(match[1], env.REGISTRY_KEY) ? null : json(401, { error: 'Unauthorized' });
}

export default {
    async fetch(request, env) {
        const unauthorized = accessDenied(request, env);
        if (unauthorized) return unauthorized;

        const url = new URL(request.url);
        if (url.pathname === '/healthz') return json(200, { ok: true });

        const route = routeOf(url.pathname);
        if (!route) return json(404, { error: 'Not found' });
        if (!b64urlBytes(route.groupId, 32)) {
            return json(400, { error: 'groupId must be a 32-byte base64url Ed25519 public key' });
        }
        if (route.deviceId && !isDeviceId(route.deviceId)) {
            return json(400, { error: 'deviceId is malformed' });
        }
        const op = opFor(route, request.method);
        if (!op) return json(405, { error: 'Method not allowed' });

        const headers = { 'x-registry-op': op };
        if (route.deviceId) headers['x-registry-device'] = route.deviceId;
        const body = op === 'list' ? undefined : await request.text();
        const stub = env.DEVICE_GROUP.get(env.DEVICE_GROUP.idFromName(route.groupId));
        return stub.fetch('https://registry.internal/', { method: 'POST', headers, body });
    },
};

export class DeviceGroupDO extends DurableObject {
    constructor(ctx, env) {
        super(ctx, env);
        this.group = new DeviceGroup(ctx.id.name, new DurableObjectStorage(ctx.storage));
    }

    async fetch(request) {
        try {
            const op = request.headers.get('x-registry-op');
            const deviceId = request.headers.get('x-registry-device') || undefined;
            const body = op === 'list' ? undefined : parseJson(await request.text());
            return json(200, await this.dispatch(op, body, deviceId));
        } catch (error) {
            if (error instanceof RegistryError) return json(error.status, { error: error.message });
            console.error('[device-registry]', error);
            return json(500, { error: 'Internal error' });
        }
    }

    dispatch(op, body, deviceId) {
        switch (op) {
            case 'list':
                return this.group.list();
            case 'put':
                return this.group.putDevice(body, deviceId);
            case 'remove':
                return this.group.removeDevice(body, deviceId);
            case 'heartbeat':
                return this.group.heartbeat(body, deviceId);
            default:
                throw new RegistryError(400, 'Unknown operation');
        }
    }
}

class DurableObjectStorage {
    constructor(storage) {
        this.storage = storage;
    }

    get(key) {
        return this.storage.get(key);
    }

    put(key, value) {
        return this.storage.put(key, value);
    }

    delete(key) {
        return this.storage.delete(key);
    }

    async list(prefix) {
        return [...(await this.storage.list({ prefix }))];
    }
}
