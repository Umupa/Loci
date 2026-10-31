import { describe, expect, it } from "vitest";
import { hiddenApprovalNotices, pendingApprovalForSession, } from "./approvalToast";
import { newSession, type Block } from "../../sessions/model/session";
function block(role: Block["role"], approval?: Block["approval"]): Block {
    return {
        id: crypto.randomUUID(),
        role,
        text: role === "tool" ? "Run command" : "Approve?",
        ...(role === "tool"
            ? { tool: { title: "Run command", kind: "execute" } }
            : {}),
        ...(approval ? { approval } : {}),
    };
}
describe("pendingApprovalForSession", () => {
    it("returns the latest undecided approval", () => {
        const session = newSession();
        session.blocks = [
            block("tool", { requestId: 1, decided: "allow" }),
            block("tool", { requestId: 2 }),
        ];
        const pending = pendingApprovalForSession(session);
        expect(pending?.requestId).toBe(2);
        expect(pending?.label).toBe("Shell");
        expect(pending?.kind).toBe("approval");
    });
    it("prefers a parked clarifying question over a tool approval", () => {
        const session = newSession();
        session.blocks = [block("tool", { requestId: 2 })];
        session.pendingQuestion = {
            requestId: 9,
            title: "Which file?",
            questions: [
                {
                    id: "q1",
                    prompt: "Which file?",
                    multiSelect: false,
                    allowCustom: true,
                    options: [{ id: "a.ts", label: "a.ts" }],
                },
            ],
        };
        const pending = pendingApprovalForSession(session);
        expect(pending?.requestId).toBe(9);
        expect(pending?.kind).toBe("question");
        expect(pending?.label).toBe("Which file?");
    });
});
describe("hiddenApprovalNotices", () => {
    it("omits approvals in a conversation that is on screen", () => {
        const visible = newSession();
        visible.blocks = [block("tool", { requestId: 1 })];
        const hidden = newSession();
        hidden.blocks = [block("tool", { requestId: 2 })];
        expect(hiddenApprovalNotices([visible, hidden], new Set([visible.id])).map((notice) => notice.sessionId)).toEqual([hidden.id]);
        expect(hiddenApprovalNotices([visible, hidden], new Set()).map((notice) => notice.sessionId)).toEqual([visible.id, hidden.id]);
    });
});
