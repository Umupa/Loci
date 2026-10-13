/**
 * Split tree for a tab. Same-direction splits share a group so
 * new panes divide space equally until the user drags a sash.
 * Panes can be dragged onto another pane's edge: same-axis
 * siblings reorder, a perpendicular edge nests a new split, and
 * a drop in another group relocates the leaf there. Session cards
 * from the sidebar use the same edges to open or move a chat into
 * that pane. cmd-d splits right, shift-cmd-d splits down,
 * cmd-opt-arrows move focus to the adjacent pane.
 */
import type { AgentDocument } from "../../sessions/model/cards";
import type { OpenCourseDetail } from "../../learning/model/course";

export type SplitDir = "right" | "down";
export type FocusDir = "left" | "right" | "up" | "down";
export type LayoutNode = {
    type: "leaf";
    id: string;
    /** When absent, the leaf is a session pane. */
    leafKind?: "canvas" | "file" | "document" | "course";
    course?: OpenCourseDetail;
    /** A library document carries its text so it can reopen without a session. */
    document?: AgentDocument;
    agentId?: string;
    /** A file opened by a single click: the next file opened takes its pane. */
    preview?: boolean;
} | {
    type: "split";
    id: string;
    dir: SplitDir;
    children: LayoutNode[];
    sizes: number[];
};
export type WorkspaceTab = {
    kind: "session";
    id: string;
    layout: LayoutNode;
    focusedId: string;
    /** Project context when a tab contains non-session panes. */
    cwd?: string;
    /** Explicit tab group; absent means ungrouped. */
    groupId?: string;
    /** Kept at the left of the strip as an icon, and spared by the bulk close actions. */
    pinned?: boolean;
};
const MIN_SIZE = 0.08;
export function leaf(sessionId: string): LayoutNode {
    return { type: "leaf", id: sessionId };
}
export function canvasLeaf(canvasId: string): LayoutNode {
    return { type: "leaf", id: canvasId, leafKind: "canvas" };
}
const FILE_PANE_PREFIX = "file:";
/** File panes are identified by their path, so a file has at most one pane. */
export function filePaneId(path: string): string {
    return `${FILE_PANE_PREFIX}${path}`;
}
export function filePanePath(paneId: string): string {
    return paneId.slice(FILE_PANE_PREFIX.length);
}
export function fileLeaf(path: string, preview = false): LayoutNode {
    return { type: "leaf", id: filePaneId(path), leafKind: "file", ...(preview ? { preview } : {}) };
}
/** Documents with the same name in different agents' libraries are distinct panes. */
export function documentPaneId(documentId: string, agentId?: string): string {
    return `document:${encodeURIComponent(agentId ?? "")}:${encodeURIComponent(documentId)}`;
}
export function documentLeaf(document: AgentDocument, agentId?: string): LayoutNode {
    return { type: "leaf", id: documentPaneId(document.id, agentId), leafKind: "document", document, ...(agentId ? { agentId } : {}) };
}
export function coursePaneId(courseId: string, agentId: string): string {
    return `course:${encodeURIComponent(agentId)}:${encodeURIComponent(courseId)}`;
}
export function courseLeaf(course: OpenCourseDetail): LayoutNode {
    return { type: "leaf", id: coursePaneId(course.courseId, course.agentId), leafKind: "course", course, agentId: course.agentId };
}
export function findLeaf(node: LayoutNode, id: string): Extract<LayoutNode, { type: "leaf" }> | undefined {
    if (node.type === "leaf") return node.id === id ? node : undefined;
    for (const child of node.children) {
        const found = findLeaf(child, id);
        if (found) return found;
    }
    return undefined;
}
export function newTab(sessionId: string): WorkspaceTab {
    return {
        kind: "session",
        id: crypto.randomUUID(),
        layout: leaf(sessionId),
        focusedId: sessionId,
    };
}
/** Keep the tab's identity and group; replace its contents with one session leaf. */
export function resetTabToSession(tab: WorkspaceTab, sessionId: string): WorkspaceTab {
    return {
        ...tab,
        layout: leaf(sessionId),
        focusedId: sessionId,
    };
}
function equalSizes(n: number): number[] {
    return Array.from({ length: n }, () => 1 / n);
}
function normalize(sizes: number[]): number[] {
    const total = sizes.reduce((sum, n) => sum + n, 0);
    if (total <= 0)
        return equalSizes(sizes.length);
    return sizes.map((n) => n / total);
}
export function splitPane(node: LayoutNode, focusedId: string, dir: SplitDir, newSessionId: string): LayoutNode {
    return splitPaneRelative(node, focusedId, dir, newSessionId, false);
}
function splitPaneRelative(node: LayoutNode, focusedId: string, dir: SplitDir, newSessionId: string, before: boolean): LayoutNode {
    if (node.type === "leaf") {
        if (node.id !== focusedId)
            return node;
        return {
            type: "split",
            id: crypto.randomUUID(),
            dir,
            children: before
                ? [leaf(newSessionId), node]
                : [node, leaf(newSessionId)],
            sizes: [0.5, 0.5],
        };
    }
    const direct = node.children.findIndex((child) => child.type === "leaf" && child.id === focusedId);
    if (direct >= 0) {
        if (node.dir === dir) {
            const insertAt = before ? direct : direct + 1;
            const children = [
                ...node.children.slice(0, insertAt),
                leaf(newSessionId),
                ...node.children.slice(insertAt),
            ];
            return { ...node, children, sizes: equalSizes(children.length) };
        }
        return {
            ...node,
            children: node.children.map((child, i) => i === direct
                ? {
                    type: "split",
                    id: crypto.randomUUID(),
                    dir,
                    children: before
                        ? [leaf(newSessionId), child]
                        : [child, leaf(newSessionId)],
                    sizes: [0.5, 0.5],
                }
                : child),
        };
    }
    return {
        ...node,
        children: node.children.map((child) => splitPaneRelative(child, focusedId, dir, newSessionId, before)),
    };
}
/** Swap one leaf id for another, keeping the split tree intact. */
export function replaceLeafId(node: LayoutNode, fromId: string, toId: string): LayoutNode {
    if (fromId === toId)
        return node;
    if (node.type === "leaf") {
        return node.id === fromId ? { ...node, id: toId } : node;
    }
    return {
        ...node,
        children: node.children.map((child) => replaceLeafId(child, fromId, toId)),
    };
}
/** Drop a leaf. Parent splits collapse to the remaining child. */
export function removePane(node: LayoutNode, sessionId: string): LayoutNode | null {
    if (node.type === "leaf")
        return node.id === sessionId ? null : node;
    const kept: {
        child: LayoutNode;
        size: number;
    }[] = [];
    for (let i = 0; i < node.children.length; i++) {
        const child = removePane(node.children[i], sessionId);
        if (child)
            kept.push({ child, size: node.sizes[i] ?? 0 });
    }
    if (kept.length === 0)
        return null;
    if (kept.length === 1)
        return kept[0].child;
    return {
        ...node,
        children: kept.map((item) => item.child),
        sizes: normalize(kept.map((item) => item.size)),
    };
}
/**
 * Close one pane in a tab. Remaining chats stay;
 * returns null only when this was the last leaf.
 */
export function closeLeaf(tab: WorkspaceTab, leafId: string): WorkspaceTab | null {
    const nextLayout = removePane(tab.layout, leafId);
    if (!nextLayout)
        return null;
    const nextFocus = tab.focusedId === leafId
        ? (siblingLeafId(tab.layout, leafId) ?? firstLeafId(nextLayout))
        : tab.focusedId;
    return { ...tab, layout: nextLayout, focusedId: nextFocus };
}
/** Move the sash between `index` and `index + 1` to `boundary` (0–1 of the group). */
export function setSplitRatio(node: LayoutNode, splitId: string, index: number, boundary: number): LayoutNode {
    if (node.type === "leaf")
        return node;
    if (node.id !== splitId) {
        return {
            ...node,
            children: node.children.map((child) => setSplitRatio(child, splitId, index, boundary)),
        };
    }
    if (index < 0 || index >= node.sizes.length - 1)
        return node;
    return { ...node, sizes: splitSizesAtBoundary(node.sizes, index, boundary) };
}
export function splitSizesAtBoundary(current: number[], index: number, boundary: number): number[] {
    if (index < 0 || index >= current.length - 1)
        return current;
    const sizes = [...current];
    const before = sizes.slice(0, index).reduce((sum, n) => sum + n, 0);
    const pair = sizes[index] + sizes[index + 1];
    const min = Math.min(MIN_SIZE, pair / 2);
    const first = Math.min(pair - min, Math.max(min, boundary - before));
    sizes[index] = first;
    sizes[index + 1] = pair - first;
    return sizes;
}
export function leafIds(node: LayoutNode): string[] {
    if (node.type === "leaf")
        return [node.id];
    return node.children.flatMap(leafIds);
}
export function firstLeafId(node: LayoutNode): string {
    return node.type === "leaf" ? node.id : firstLeafId(node.children[0]);
}
export type LayoutRect = {
    x: number;
    y: number;
    w: number;
    h: number;
};
export type LayoutLeaf = {
    id: string;
    kind: "session" | "canvas" | "file" | "document" | "course";
    course?: OpenCourseDetail;
    document?: AgentDocument;
    agentId?: string;
    preview?: boolean;
    rect: LayoutRect;
    axis: "x" | "y";
};
export type LayoutSash = {
    splitId: string;
    index: number;
    dir: SplitDir;
    group: LayoutRect;
    sizes: number[];
};
export function layoutLeaves(node: LayoutNode, rect: LayoutRect = { x: 0, y: 0, w: 1, h: 1 }, parentDir?: SplitDir): LayoutLeaf[] {
    const axis = parentDir === "down" ? "y" : "x";
    if (node.type === "leaf") {
        const kind = node.leafKind ?? "session";
        return [{ id: node.id, kind, ...(node.preview ? { preview: true } : {}), ...(node.document ? { document: node.document } : {}), ...(node.agentId ? { agentId: node.agentId } : {}), ...(node.course ? { course: node.course } : {}), rect, axis }];
    }
    const row = node.dir === "right";
    let offset = 0;
    const out: LayoutLeaf[] = [];
    for (let i = 0; i < node.children.length; i++) {
        const size = node.sizes[i] ?? 0;
        const child: LayoutRect = row
            ? { x: rect.x + offset * rect.w, y: rect.y, w: size * rect.w, h: rect.h }
            : { x: rect.x, y: rect.y + offset * rect.h, w: rect.w, h: size * rect.h };
        offset += size;
        out.push(...layoutLeaves(node.children[i], child, node.dir));
    }
    return out;
}
export function layoutSashes(node: LayoutNode, rect: LayoutRect = { x: 0, y: 0, w: 1, h: 1 }): LayoutSash[] {
    if (node.type === "leaf")
        return [];
    const row = node.dir === "right";
    let offset = 0;
    const out: LayoutSash[] = [];
    for (let i = 0; i < node.children.length; i++) {
        const size = node.sizes[i] ?? 0;
        if (i > 0) {
            out.push({
                splitId: node.id,
                index: i - 1,
                dir: node.dir,
                group: rect,
                sizes: node.sizes,
            });
        }
        const child: LayoutRect = row
            ? { x: rect.x + offset * rect.w, y: rect.y, w: size * rect.w, h: rect.h }
            : { x: rect.x, y: rect.y + offset * rect.h, w: rect.w, h: size * rect.h };
        offset += size;
        out.push(...layoutSashes(node.children[i], child));
    }
    return out;
}
function leafRects(node: LayoutNode): LayoutLeaf[] {
    return layoutLeaves(node);
}
function rangeOverlap(a0: number, a1: number, b0: number, b1: number): number {
    return Math.max(0, Math.min(a1, b1) - Math.max(a0, b0));
}
/** Adjacent leaf in `dir`, preferring panes that share an edge. */
export function neighborLeafId(node: LayoutNode, focusedId: string, dir: FocusDir): string | null {
    const panes = leafRects(node);
    const current = panes.find((p) => p.id === focusedId);
    if (!current)
        return null;
    const c = current.rect;
    let best: {
        id: string;
        hit: number;
        gap: number;
        overlap: number;
    } | null = null;
    for (const pane of panes) {
        if (pane.id === focusedId)
            continue;
        const r = pane.rect;
        let gap = Infinity;
        let perp = 0;
        if (dir === "left" && r.x + r.w <= c.x + 1e-6) {
            gap = c.x - (r.x + r.w);
            perp = rangeOverlap(c.y, c.y + c.h, r.y, r.y + r.h);
        }
        else if (dir === "right" && r.x >= c.x + c.w - 1e-6) {
            gap = r.x - (c.x + c.w);
            perp = rangeOverlap(c.y, c.y + c.h, r.y, r.y + r.h);
        }
        else if (dir === "up" && r.y + r.h <= c.y + 1e-6) {
            gap = c.y - (r.y + r.h);
            perp = rangeOverlap(c.x, c.x + c.w, r.x, r.x + r.w);
        }
        else if (dir === "down" && r.y >= c.y + c.h - 1e-6) {
            gap = r.y - (c.y + c.h);
            perp = rangeOverlap(c.x, c.x + c.w, r.x, r.x + r.w);
        }
        else {
            continue;
        }
        const hit = perp > 0 ? 0 : 1;
        if (!best ||
            hit < best.hit ||
            (hit === best.hit && gap < best.gap) ||
            (hit === best.hit && gap === best.gap && perp > best.overlap)) {
            best = { id: pane.id, hit, gap, overlap: perp };
        }
    }
    return best?.id ?? null;
}
/** Session to focus after closing `sessionId` — a neighbor's first leaf. */
export function siblingLeafId(node: LayoutNode, sessionId: string): string | null {
    if (node.type === "leaf")
        return null;
    const index = node.children.findIndex((child) => child.type === "leaf" && child.id === sessionId);
    if (index >= 0) {
        const neighbor = node.children[index - 1] ?? node.children[index + 1];
        return neighbor ? firstLeafId(neighbor) : null;
    }
    for (const child of node.children) {
        const found = siblingLeafId(child, sessionId);
        if (found)
            return found;
    }
    return null;
}
export type PanePlace = "before" | "after";
export type PaneEdge = "left" | "right" | "top" | "bottom";
type SplitNode = Extract<LayoutNode, {
    type: "split";
}>;
export function paneEdgeFromPoint(x: number, y: number, rect: {
    left: number;
    top: number;
    width: number;
    height: number;
}): PaneEdge {
    const nx = rect.width <= 0 ? 0 : (x - rect.left) / rect.width - 0.5;
    const ny = rect.height <= 0 ? 0 : (y - rect.top) / rect.height - 0.5;
    if (Math.abs(nx) > Math.abs(ny))
        return nx < 0 ? "left" : "right";
    return ny < 0 ? "top" : "bottom";
}
function edgeSplit(edge: PaneEdge): {
    dir: SplitDir;
    place: PanePlace;
} {
    if (edge === "left")
        return { dir: "right", place: "before" };
    if (edge === "right")
        return { dir: "right", place: "after" };
    if (edge === "top")
        return { dir: "down", place: "before" };
    return { dir: "down", place: "after" };
}
function leafParent(node: LayoutNode, leafId: string): {
    parentId: string;
    index: number;
    dir: SplitDir;
} | null {
    if (node.type === "leaf")
        return null;
    for (let i = 0; i < node.children.length; i++) {
        const child = node.children[i];
        if (child.type === "leaf" && child.id === leafId) {
            return { parentId: node.id, index: i, dir: node.dir };
        }
        const found = leafParent(child, leafId);
        if (found)
            return found;
    }
    return null;
}
function reorderChild(split: SplitNode, fromIndex: number, toIndex: number, place: PanePlace): SplitNode {
    const n = split.children.length;
    if (fromIndex < 0 || fromIndex >= n || toIndex < 0 || toIndex >= n) {
        return split;
    }
    let insertAt = place === "after" ? toIndex + 1 : toIndex;
    insertAt = Math.max(0, Math.min(n, insertAt));
    if (fromIndex < insertAt)
        insertAt -= 1;
    if (fromIndex === insertAt)
        return split;
    const children = [...split.children];
    const sizes = [...split.sizes];
    const [child] = children.splice(fromIndex, 1);
    const [size] = sizes.splice(fromIndex, 1);
    children.splice(insertAt, 0, child);
    sizes.splice(insertAt, 0, size);
    return { ...split, children, sizes };
}
function reorderInSplit(node: LayoutNode, splitId: string, fromIndex: number, toIndex: number, place: PanePlace): LayoutNode {
    if (node.type === "leaf")
        return node;
    if (node.id === splitId)
        return reorderChild(node, fromIndex, toIndex, place);
    return {
        ...node,
        children: node.children.map((child) => reorderInSplit(child, splitId, fromIndex, toIndex, place)),
    };
}
function extractLeaf(node: LayoutNode, leafId: string): {
    tree: LayoutNode | null;
    leaf: Extract<LayoutNode, {
        type: "leaf";
    }>;
} | null {
    if (node.type === "leaf") {
        return node.id === leafId ? { tree: null, leaf: node } : null;
    }
    const children: LayoutNode[] = [];
    const sizes: number[] = [];
    let leaf: Extract<LayoutNode, {
        type: "leaf";
    }> | null = null;
    for (let i = 0; i < node.children.length; i++) {
        const extracted = extractLeaf(node.children[i], leafId);
        if (!extracted) {
            children.push(node.children[i]);
            sizes.push(node.sizes[i] ?? 0);
            continue;
        }
        leaf = extracted.leaf;
        if (extracted.tree) {
            children.push(extracted.tree);
            sizes.push(node.sizes[i] ?? 0);
        }
    }
    if (!leaf)
        return null;
    if (children.length === 0)
        return { tree: null, leaf };
    if (children.length === 1)
        return { tree: children[0], leaf };
    return {
        tree: { ...node, children, sizes: normalize(sizes) },
        leaf,
    };
}
function insertBeside(node: LayoutNode, targetId: string, incoming: LayoutNode, place: PanePlace): LayoutNode {
    if (node.type === "leaf")
        return node;
    const index = node.children.findIndex((child) => child.type === "leaf" && child.id === targetId);
    if (index >= 0) {
        const insertAt = place === "before" ? index : index + 1;
        const children = [...node.children];
        const sizes = [...node.sizes];
        const share = (sizes[index] ?? 0) / 2;
        sizes[index] = share;
        children.splice(insertAt, 0, incoming);
        sizes.splice(insertAt, 0, share);
        return { ...node, children, sizes };
    }
    return {
        ...node,
        children: node.children.map((child) => insertBeside(child, targetId, incoming, place)),
    };
}
function wrapBeside(node: LayoutNode, targetId: string, incoming: LayoutNode, dir: SplitDir, place: PanePlace): LayoutNode {
    if (node.type === "leaf") {
        if (node.id !== targetId)
            return node;
        return {
            type: "split",
            id: crypto.randomUUID(),
            dir,
            children: place === "before" ? [incoming, node] : [node, incoming],
            sizes: [0.5, 0.5],
        };
    }
    return {
        ...node,
        children: node.children.map((child) => wrapBeside(child, targetId, incoming, dir, place)),
    };
}
/**
 * Drag a leaf onto another pane's edge. Same-axis siblings keep their
 * sizes and only swap order; a perpendicular edge nests a new split
 * around the target; dropping onto a pane in another group of the
 * same axis relocates the leaf there.
 */
export function movePane(node: LayoutNode, fromId: string, toId: string, edge: PaneEdge): LayoutNode {
    if (fromId === toId)
        return node;
    const fromAt = leafParent(node, fromId);
    const toAt = leafParent(node, toId);
    if (!fromAt || !toAt)
        return node;
    const { dir, place } = edgeSplit(edge);
    if (toAt.dir === dir && fromAt.parentId === toAt.parentId) {
        return reorderInSplit(node, fromAt.parentId, fromAt.index, toAt.index, place);
    }
    const extracted = extractLeaf(node, fromId);
    if (!extracted?.tree)
        return node;
    if (!leafIds(extracted.tree).includes(toId))
        return node;
    const targetAt = leafParent(extracted.tree, toId);
    if (targetAt?.dir === dir) {
        return insertBeside(extracted.tree, toId, extracted.leaf, place);
    }
    return wrapBeside(extracted.tree, toId, extracted.leaf, dir, place);
}
/**
 * Open `sessionId` on `toId`'s edge, or move it there when it is
 * already a leaf in this tree.
 */
export function placePane(node: LayoutNode, sessionId: string, toId: string, edge: PaneEdge): LayoutNode {
    if (sessionId === toId)
        return node;
    const ids = leafIds(node);
    if (!ids.includes(toId))
        return node;
    if (ids.includes(sessionId))
        return movePane(node, sessionId, toId, edge);
    return placeLayout(node, leaf(sessionId), toId, edge);
}
/** Place an intact layout tree beside one pane in another layout. */
export function placeLayout(node: LayoutNode, incoming: LayoutNode, toId: string, edge: PaneEdge): LayoutNode {
    if (!leafIds(node).includes(toId))
        return node;
    const { dir, place } = edgeSplit(edge);
    const targetAt = leafParent(node, toId);
    if (targetAt?.dir === dir) {
        return insertBeside(node, toId, incoming, place);
    }
    return wrapBeside(node, toId, incoming, dir, place);
}
/**
 * Show a drawing an agent just drew beside its session. The tab's existing
 * canvas pane is reused, so repeated drawings do not keep splitting the tab;
 * focus stays where the user left it.
 */
export function showCanvasBeside(tab: WorkspaceTab, canvasId: string, sessionId: string): WorkspaceTab {
    const leaves = layoutLeaves(tab.layout);
    if (!leaves.some((entry) => entry.id === sessionId) || leaves.some((entry) => entry.id === canvasId))
        return tab;
    const slot = leaves.find((entry) => entry.kind === "canvas");
    return {
        ...tab,
        layout: slot
            ? replacePaneWithLayout(tab.layout, slot.id, canvasLeaf(canvasId))
            : placeLayout(tab.layout, canvasLeaf(canvasId), sessionId, "right"),
        focusedId: tab.focusedId === slot?.id ? canvasId : tab.focusedId,
    };
}
/**
 * Open a drawing picked from the sidebar: it takes the tab's canvas pane, or
 * opens right of the focused pane, and takes focus.
 */
export function showCanvasInTab(tab: WorkspaceTab, canvasId: string): WorkspaceTab {
    const leaves = layoutLeaves(tab.layout);
    if (leaves.some((entry) => entry.id === canvasId))
        return { ...tab, focusedId: canvasId };
    const slot = leaves.find((entry) => entry.kind === "canvas");
    return {
        ...tab,
        layout: slot
            ? replacePaneWithLayout(tab.layout, slot.id, canvasLeaf(canvasId))
            : placeLayout(tab.layout, canvasLeaf(canvasId), tab.focusedId, "right"),
        focusedId: canvasId,
    };
}
/** Open a document beside the focused pane, keeping other documents available. */
export function showDocumentInTab(tab: WorkspaceTab, document: AgentDocument, agentId?: string): WorkspaceTab {
    const incoming = documentLeaf(document, agentId);
    return {
        ...tab,
        layout: findLeaf(tab.layout, incoming.id)
            ? replacePaneWithLayout(tab.layout, incoming.id, incoming)
            : placeLayout(tab.layout, incoming, tab.focusedId, "right"),
        focusedId: incoming.id,
    };
}
export function showCourseInTab(tab: WorkspaceTab, course: OpenCourseDetail): WorkspaceTab {
    const incoming = courseLeaf(course);
    return { ...tab, layout: findLeaf(tab.layout, incoming.id)
        ? replacePaneWithLayout(tab.layout, incoming.id, incoming)
        : placeLayout(tab.layout, incoming, tab.focusedId, "right"), focusedId: incoming.id };
}
/**
 * Where a drawing goes when a session draws on it. A drawing has one pane, so
 * one that is open in another tab moves beside the session, but only while
 * the user is looking at that session's tab.
 */
export function showCanvasForSession(tabs: WorkspaceTab[], activeTabId: string, canvasId: string, sessionId: string): WorkspaceTab[] {
    const home = tabs.find((tab) => leafIds(tab.layout).includes(sessionId));
    const current = tabs.find((tab) => leafIds(tab.layout).includes(canvasId));
    if (!home || current?.id === home.id || (current && home.id !== activeTabId))
        return tabs;
    return tabs.flatMap((tab) => {
        if (tab.id === home.id)
            return [showCanvasBeside(tab, canvasId, sessionId)];
        return tab.id === current?.id ? closeLeaf(tab, canvasId) ?? [] : [tab];
    });
}
/**
 * Show a file in a tab. A single click previews: it reuses the tab's preview
 * pane, or opens one right of the focused pane. Pinning keeps the pane, so the
 * next preview opens beside it instead of replacing it.
 */
export function showFileInTab(tab: WorkspaceTab, path: string, pin: boolean): WorkspaceTab {
    const id = filePaneId(path);
    const leaves = layoutLeaves(tab.layout);
    const open = leaves.find((entry) => entry.id === id);
    if (open) {
        return {
            ...tab,
            layout: pin && open.preview ? replacePaneWithLayout(tab.layout, id, fileLeaf(path)) : tab.layout,
            focusedId: id,
        };
    }
    const slot = leaves.find((entry) => entry.kind === "file" && entry.preview);
    return {
        ...tab,
        layout: slot
            ? replacePaneWithLayout(tab.layout, slot.id, fileLeaf(path, !pin))
            : placeLayout(tab.layout, fileLeaf(path, !pin), tab.focusedId, "right"),
        focusedId: id,
    };
}
/** Drop a file from the Files tree onto a pane's edge; the pane it makes is kept. */
export function placeFileOnPane(tab: WorkspaceTab, path: string, toId: string, edge: PaneEdge): WorkspaceTab {
    const id = filePaneId(path);
    if (id === toId || !findLeaf(tab.layout, toId))
        return tab;
    const pinned = findLeaf(tab.layout, id) ? replacePaneWithLayout(tab.layout, id, fileLeaf(path)) : null;
    return {
        ...tab,
        layout: pinned ? movePane(pinned, id, toId, edge) : placeLayout(tab.layout, fileLeaf(path), toId, edge),
        focusedId: id,
    };
}
/** Follow a renamed or moved file or folder: its panes keep showing it. */
export function rebaseFilePanes(tab: WorkspaceTab, rebase: (path: string) => string): WorkspaceTab {
    let changed = false;
    const rename = (id: string) => {
        const next = filePaneId(rebase(filePanePath(id)));
        if (next !== id) changed = true;
        return next;
    };
    const walk = (node: LayoutNode): LayoutNode => node.type === "leaf"
        ? node.leafKind === "file" ? { ...node, id: rename(node.id) } : node
        : { ...node, children: node.children.map(walk) };
    const layout = walk(tab.layout);
    if (!changed) return tab;
    const focused = findLeaf(tab.layout, tab.focusedId);
    return { ...tab, layout, focusedId: focused?.leafKind === "file" ? rename(tab.focusedId) : tab.focusedId };
}
/** Replace one pane with an intact layout tree. */
export function replacePaneWithLayout(node: LayoutNode, targetId: string, incoming: LayoutNode): LayoutNode {
    if (node.type === "leaf")
        return node.id === targetId ? incoming : node;
    return {
        ...node,
        children: node.children.map((child) => replacePaneWithLayout(child, targetId, incoming)),
    };
}
