import { markTurnInterrupted, type ResumedWorkspace } from "../../sessions/model/inFlight";
import { courseLeaf, documentLeaf, fileLeaf, filePanePath, layoutLeaves, leafIds, newTab, type LayoutNode, type WorkspaceTab } from "./layout";
import { workspaceTabCwd } from "./workspaceTabGroups";
import { pathKey } from "../../../shared/lib/paths";
import { reconcileProjectReturn, type ProjectReturnMemory } from "../../projects/model/projectReturn";
import { HARNESSES, RUNTIME_MODES, newSession, type HarnessId, type RuntimeMode, type Session } from "../../sessions/model/session";
export type WorkspaceSessionStub = {
    id: string;
    cwd: string;
    harness: HarnessId;
    model: string;
    modelSettings: Record<string, string>;
    runtimeMode: RuntimeMode;
    title: string;
    providerSessionId?: string;
    providerAccountId?: string;
};
export type WorkspaceSnapshot = {
    tabs: WorkspaceTab[];
    sessions: WorkspaceSessionStub[];
    activeTabId: string;
    projectCwd: string;
    projectReturnTargets?: {
        projectPath: string;
        tabId?: string;
        paneId?: string;
    }[];
};
function withProjectReturnTargets(snapshot: WorkspaceSnapshot, memory: ProjectReturnMemory): WorkspaceSnapshot {
    const valid = reconcileProjectReturn({
        ...snapshot,
        memory,
        activeTabId: "",
    });
    return {
        ...snapshot,
        projectReturnTargets: [...valid].map(([projectPath, paneId]) => ({
            projectPath,
            tabId: paneId,
        })),
    };
}
function parseProjectReturnTargets(raw: unknown): ProjectReturnMemory {
    const memory = new Map<string, string>();
    if (!Array.isArray(raw))
        return memory;
    for (const entry of raw) {
        if (!entry || typeof entry !== "object")
            continue;
        if (!("projectPath" in entry))
            continue;
        const projectPath = (entry as {
            projectPath?: unknown;
        }).projectPath;
        if (typeof projectPath !== "string" || !projectPath.trim())
            continue;
        const remembered = (entry as {
            paneId?: unknown;
        }).paneId ??
            (entry as {
                tabId?: unknown;
            }).tabId;
        if (typeof remembered !== "string" || !remembered.trim())
            continue;
        memory.set(pathKey(projectPath), remembered.trim());
    }
    return memory;
}
export function workspaceSnapshotKey(snapshot: WorkspaceSnapshot): string {
    return JSON.stringify(snapshot);
}
/**
 * Reopen the saved tabs/panes. Transcripts come from `loaded` when the
 * session was persisted; blank tabs fall back to the stub.
 */
export function hydrateWorkspaceSnapshot(snapshot: WorkspaceSnapshot, loaded: Map<string, Session>, interruptedIds: ReadonlySet<string> = new Set()): ResumedWorkspace | null {
    const parsed = parseWorkspaceSnapshot(snapshot);
    if (!parsed)
        return null;
        const stubs = new Map(parsed.sessions.map((stub) => [stub.id, stub]));
    const sessions = new Map<string, Session>();
    const take = (id: string): Session | null => {
        const existing = sessions.get(id);
        if (existing)
            return existing;
        const record = loaded.get(id);
        const stub = stubs.get(id);
        const base = record ?? (stub ? sessionFromStub(stub) : null);
        if (!base)
            return null;
        const next = interruptedIds.has(id)
            ? markTurnInterrupted(base)
            : { ...base, busy: false };
        sessions.set(id, next);
        return next;
    };
    for (const stub of parsed.sessions)
        take(stub.id);
    const tabs: WorkspaceTab[] = [];
    for (const tab of parsed.tabs) {
        for (const { id, kind } of layoutLeaves(tab.layout)) {
            if (kind !== "session") continue;
            if (take(id))
                continue;
            sessions.set(id, sessionFromStub({
                id,
                cwd: parsed.projectCwd,
                harness: "claude",
                model: "",
                modelSettings: {},
                runtimeMode: "supervised",
                title: "",
            }));
        }
        tabs.push(tab);
    }
    for (const id of interruptedIds) {
        const session = take(id);
        if (!session)
            continue;
        if (tabs.some((tab) => leafIds(tab.layout).includes(id)))
            continue;
        tabs.push(newTab(id));
    }
    if (tabs.length === 0)
        return null;
    const activeTabId = tabs.some((tab) => tab.id === parsed.activeTabId)
        ? parsed.activeTabId
        : tabs[0].id;
    const projectCwd = parsed.projectCwd !== "~"
        ? parsed.projectCwd
        : (sessions.values().next().value?.cwd ?? "~");
    return {
        tabs,
        sessions: [...sessions.values()],
        activeTabId,
        projectCwd,
        projectReturnMemory: reconcileProjectReturn({
            memory: parseProjectReturnTargets(parsed.projectReturnTargets),
            tabs,
            sessions: [...sessions.values()],
            activeTabId,
        }),
    };
}
function sessionStub(session: Session): WorkspaceSessionStub | null {
    if (!session.id)
        return null;
    return {
        id: session.id,
        cwd: session.cwd || "~",
        harness: session.harness,
        model: session.model,
        modelSettings: { ...session.modelSettings },
        runtimeMode: session.runtimeMode,
        title: session.title,
        ...(session.providerSessionId
            ? { providerSessionId: session.providerSessionId }
            : {}),
        ...(session.providerAccountId
            ? { providerAccountId: session.providerAccountId }
            : {}),
    };
}
function sessionFromStub(stub: WorkspaceSessionStub): Session {
    const session = newSession(stub.harness, stub.cwd, stub.model, stub.runtimeMode, stub.modelSettings);
    return {
        ...session,
        id: stub.id,
        // A snapshot is a saved choice, not a new conversation. Catalog discovery
        // and the current picker preferences must not replace its model.
        model: stub.model || session.model,
        modelSettings: { ...stub.modelSettings },
        title: stub.title,
        ...(stub.providerSessionId
            ? { providerSessionId: stub.providerSessionId }
            : {}),
        ...(stub.providerAccountId
            ? { providerAccountId: stub.providerAccountId }
            : {}),
    };
}
function sanitizeStub(raw: unknown): WorkspaceSessionStub | null {
    if (!raw || typeof raw !== "object")
        return null;
    const value = raw as Record<string, unknown>;
    if (typeof value.id !== "string" || !value.id)
        return null;
    const harness = asHarness(value.harness);
    const runtimeMode = asRuntimeMode(value.runtimeMode);
    if (!harness || !runtimeMode)
        return null;
    const modelSettings = value.modelSettings &&
        typeof value.modelSettings === "object" &&
        !Array.isArray(value.modelSettings)
        ? Object.fromEntries(Object.entries(value.modelSettings as Record<string, unknown>).filter((entry): entry is [
            string,
            string
        ] => typeof entry[1] === "string"))
        : {};
    return {
        id: value.id,
        cwd: typeof value.cwd === "string" && value.cwd.trim()
            ? value.cwd.trim()
            : "~",
        harness,
        model: typeof value.model === "string" ? value.model : "",
        modelSettings,
        runtimeMode,
        title: typeof value.title === "string" ? value.title : "",
        ...(typeof value.providerSessionId === "string" && value.providerSessionId
            ? { providerSessionId: value.providerSessionId }
            : {}),
        ...(typeof value.providerAccountId === "string" &&
            /^[A-Za-z0-9_-]+$/.test(value.providerAccountId)
            ? { providerAccountId: value.providerAccountId }
            : {}),
    };
}
export function sanitizeLayout(raw: unknown): LayoutNode | null {
    if (!raw || typeof raw !== "object")
        return null;
    const value = raw as Record<string, unknown>;
    if (value.type === "leaf") {
        if (value.leafKind !== undefined && value.leafKind !== "canvas" && value.leafKind !== "file" && value.leafKind !== "document" && value.leafKind !== "course")
            return null;
        if (typeof value.id !== "string" || !value.id)
            return null;
        if (value.leafKind === "file")
            return fileLeaf(filePanePath(value.id), value.preview === true);
        if (value.leafKind === "course") {
            const course = value.course as Record<string, unknown> | undefined;
            if (!course || typeof course.courseId !== "string" || !/^[A-Za-z0-9_-]+$/.test(course.courseId)
                || typeof course.agentId !== "string" || !/^[A-Za-z0-9_-]+$/.test(course.agentId)
                || typeof course.title !== "string" || !course.title.trim()) return null;
            return courseLeaf({ courseId: course.courseId, agentId: course.agentId, title: course.title,
                ...(typeof course.sourceSessionId === "string" ? { sourceSessionId: course.sourceSessionId } : {}) });
        }
        if (value.leafKind === "document") {
            if (!value.document || typeof value.document !== "object" || Array.isArray(value.document))
                return null;
            const document = value.document as Record<string, unknown>;
            if (typeof document.id !== "string" || !document.id || typeof document.title !== "string" || typeof document.body !== "string")
                return null;
            if (value.agentId !== undefined && (typeof value.agentId !== "string" || !/^[A-Za-z0-9-]+$/.test(value.agentId)))
                return null;
            return documentLeaf({
                id: document.id,
                title: document.title,
                body: document.body,
                ...(typeof document.subject === "string" ? { subject: document.subject } : {}),
            }, value.agentId as string | undefined);
        }
        return { type: "leaf", id: value.id, ...(value.leafKind === "canvas" ? { leafKind: value.leafKind } : {}) };
    }
    if (value.type !== "split" || typeof value.id !== "string" || !value.id) {
        return null;
    }
    const dir = value.dir === "down" ? "down" : value.dir === "right" ? "right" : null;
    if (!dir || !Array.isArray(value.children) || value.children.length < 2) {
        return null;
    }
    const children = value.children
        .map(sanitizeLayout)
        .filter((node): node is LayoutNode => node != null);
    if (children.length === 0)
        return null;
    if (children.length === 1)
        return children[0];
    const sizes = Array.isArray(value.sizes)
        ? value.sizes.filter((size): size is number => typeof size === "number" && Number.isFinite(size))
        : [];
    const normalized = sizes.length === children.length
        ? sizes
        : children.map(() => 1 / children.length);
    return { type: "split", id: value.id, dir, children, sizes: normalized };
}
function asHarness(value: unknown): HarnessId | null {
    return typeof value === "string" && (HARNESSES as string[]).includes(value)
        ? (value as HarnessId)
        : null;
}
function asRuntimeMode(value: unknown): RuntimeMode | null {
    return typeof value === "string" &&
        (RUNTIME_MODES as string[]).includes(value)
        ? (value as RuntimeMode)
        : null;
}

export function collectWorkspaceSnapshot(tabs: WorkspaceTab[], sessions: Session[], activeTabId: string, projectCwd: string, memory: ProjectReturnMemory): WorkspaceSnapshot {
 return withProjectReturnTargets({ tabs: tabs.map(sanitizeTab).filter((tab): tab is WorkspaceTab => tab !== null), sessions: sessions.map(sessionStub).filter((stub): stub is WorkspaceSessionStub => stub !== null), activeTabId, projectCwd: projectCwd.trim() || "~" }, memory);
}
export function parseWorkspaceSnapshot(raw: unknown): WorkspaceSnapshot | null {
 if (!raw || typeof raw !== "object") return null;
 const value = raw as Record<string, unknown>;
 if (!Array.isArray(value.tabs) || typeof value.activeTabId !== "string") return null;
 const tabs = value.tabs.map(sanitizeTab).filter((tab): tab is WorkspaceTab => tab !== null);
 if (!tabs.length) return null;
 const sessions = Array.isArray(value.sessions) ? value.sessions.map(sanitizeStub).filter((stub): stub is WorkspaceSessionStub => stub !== null) : [];
 let projectCwd = typeof value.projectCwd === "string" && value.projectCwd.trim() ? value.projectCwd.trim() : "~";
 let activeTab = tabs.find((tab) => tab.id === value.activeTabId);
 if (!activeTab) {
   activeTab = tabs.find((tab) => {
     const cwd = workspaceTabCwd(tab, sessions);
     return cwd !== null && pathKey(cwd) === pathKey(projectCwd);
   }) ?? tabs[0];
   projectCwd = workspaceTabCwd(activeTab, sessions) ?? projectCwd;
 }
 return withProjectReturnTargets({ tabs, sessions, activeTabId: activeTab.id, projectCwd }, parseProjectReturnTargets(value.projectReturnTargets));
}
function sanitizeTab(raw: unknown): WorkspaceTab | null {
 if (!raw || typeof raw !== "object") return null;
 const value = raw as Record<string,unknown>;
 if (typeof value.id !== "string" || !value.id) return null;
 const layout = sanitizeLayout(value.layout);
 if (!layout) return null;
 const ids = leafIds(layout);
 return {kind:"session", id:value.id, layout, focusedId: typeof value.focusedId === "string" && ids.includes(value.focusedId) ? value.focusedId : ids[0], ...(typeof value.cwd === "string" && value.cwd ? {cwd:value.cwd} : {}), ...(typeof value.groupId === "string" && value.groupId ? {groupId:value.groupId} : {}), ...(value.pinned === true ? {pinned:true} : {})};
}
