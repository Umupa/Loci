// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/webview", () => ({
    getCurrentWebview: () => ({ onDragDropEvent: async () => () => { } }),
}));
import { Composer, ComposerAction } from "./Composer";
import type { ComposerTurnOptions, Attachment } from "../model/session";
import { clearComposerDraft, getComposerDraft, setComposerDraft, } from "../model/draftCache";
import type { UserQuestionPrompt } from "../model/userQuestion";
function renderAction(busy: boolean, hasValue: boolean, allowBusySubmit = true) {
    return renderToStaticMarkup(createElement(ComposerAction, {
        busy,
        hasValue,
        allowBusySubmit,
        onSend: vi.fn(),
        onStop: vi.fn(),
    }));
}
describe("ComposerAction", () => {
    it("replaces Stop with Send when typing during a running turn", () => {
        const empty = renderAction(true, false);
        expect(empty).toContain('aria-label="Stop"');
        expect(empty).not.toContain('aria-label="Send"');
        const typed = renderAction(true, true);
        expect(typed).toContain('aria-label="Send"');
        expect(typed).toContain("composer-send");
        expect(typed).toContain("primary-action");
        expect(typed).not.toContain('aria-label="Stop"');
    });
    it("keeps Stop while busy when submitting follow-up text is disabled", () => {
        const typed = renderAction(true, true, false);
        expect(typed).toContain('aria-label="Stop"');
        expect(typed).not.toContain('aria-label="Send"');
    });

    it("gives Stop the same theme-aware face as Send", () => {
        const stop = renderAction(true, false);
        expect(stop).toContain("primary-action");
        expect(stop).not.toContain("bg-white");
    });

    it("names the chat field from the mentor it writes to", async () => {
        vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
        const host = document.createElement("div");
        document.body.append(host);
        const root = createRoot(host);
        try {
            await act(async () => root.render(createElement(Composer, {
                focused: false, harness: "claude", model: "claude-sonnet", runtimeMode: "supervised",
                executionCwd: "/repo", placeholder: "Message Nova", hideProjectPicker: true,
                onFocus: () => { }, onCwdChange: () => { }, onModelChange: () => { },
                onRuntimeModeChange: () => { }, onSubmit: () => { },
            })));
            expect(host.querySelector("textarea")?.getAttribute("aria-label")).toBe("Message Nova");
        } finally {
            act(() => root.unmount());
            host.remove();
        }
    });

    it("keeps a name on a field without a placeholder", async () => {
        vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
        const host = document.createElement("div");
        document.body.append(host);
        const root = createRoot(host);
        try {
            await act(async () => root.render(createElement(Composer, {
                focused: false, harness: "claude", model: "claude-sonnet", runtimeMode: "supervised",
                executionCwd: "/repo", hideProjectPicker: true,
                onFocus: () => { }, onCwdChange: () => { }, onModelChange: () => { },
                onRuntimeModeChange: () => { }, onSubmit: () => { },
            })));
            expect(host.querySelector("textarea")?.getAttribute("aria-label")).toBe("Message");
        } finally {
            act(() => root.unmount());
            host.remove();
        }
    });
});
describe("Composer question focus", () => {
    let container: HTMLDivElement;
    let root: Root;
    beforeEach(() => {
        vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
        container = document.createElement("div");
        document.body.append(container);
        root = createRoot(container);
    });
    afterEach(() => {
        act(() => root.unmount());
        container.remove();
        vi.unstubAllGlobals();
    });
    const question: UserQuestionPrompt = {
        requestId: 1,
        questions: [
            {
                id: "q1",
                prompt: "Pick one",
                multiSelect: false,
                allowCustom: false,
                options: [{ id: "a", label: "Option A" }],
            },
        ],
    };
    async function renderComposer(currentQuestion: UserQuestionPrompt | undefined, onQuestionReply: (requestId: number, reply: unknown) => void, busy = false, focusToken = 0, initialDraft?: string, onBtwCommand?: (text: string, options?: {
        draft?: boolean;
    }) => boolean | void, onSubmit: (text: string, attachments: Attachment[]) => void = () => { }, sessionId?: string, harness: "claude" | "codex" = "claude") {
        await act(async () => root.render(createElement(Composer, {
            key: sessionId,
            focused: true,
            focusToken,
            harness,
            model: "claude-sonnet",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            initialDraft,
            sessionId,
            onDraftChange: sessionId
                ? (text) => setComposerDraft(sessionId, text)
                : undefined,
            hideProjectPicker: true,
            onFocus: () => { },
            onCwdChange: () => { },
            onModelChange: () => { },
            onRuntimeModeChange: () => { },
            onSubmit,
            onBtwCommand,
            question: currentQuestion,
            onQuestionReply,
            busy,
        })));
    }
    it.each([
        ["/btw", ""],
        ["/btw some text here...", "some text here..."],
    ])("routes %s to BTW instead of the main submit", async (draft, text) => {
        const onBtwCommand = vi.fn(() => true);
        const onSubmit = vi.fn();
        await renderComposer(undefined, vi.fn(), false, 0, draft, onBtwCommand, onSubmit);
        const textarea = container.querySelector("textarea")!;
        await act(async () => textarea.dispatchEvent(new KeyboardEvent("keydown", {
            key: "Enter",
            bubbles: true,
            cancelable: true,
        })));
        expect(onBtwCommand).toHaveBeenCalledWith(text);
        expect(onSubmit).not.toHaveBeenCalled();
        expect(textarea.value).toBe("");
    });
    async function typeInto(textarea: HTMLTextAreaElement, value: string) {
        await act(async () => {
            textarea.value = value;
            textarea.dispatchEvent(new Event("input", { bubbles: true }));
        });
    }
    it("opens BTW as soon as `/btw ` is typed and hands over the rest", async () => {
        const onBtwCommand = vi.fn(() => true);
        await renderComposer(undefined, vi.fn(), false, 0, undefined, onBtwCommand);
        const textarea = container.querySelector("textarea")!;
        await typeInto(textarea, "/btw");
        expect(onBtwCommand).not.toHaveBeenCalled();
        await typeInto(textarea, "/btw why");
        expect(onBtwCommand).toHaveBeenCalledWith("why", { draft: true });
        expect(textarea.value).toBe("");
    });
    it("leaves a typed `/btw ` alone when BTW is unavailable", async () => {
        const onBtwCommand = vi.fn(() => false);
        await renderComposer(undefined, vi.fn(), false, 0, undefined, onBtwCommand);
        const textarea = container.querySelector("textarea")!;
        await typeInto(textarea, "/btw ");
        expect(textarea.value).toBe("/btw ");
    });
    it.each([false, true])("mounts the working mascot and responds to its setting live (chat: %s)", async (chat) => {
        const { saveComposerRunner } = await import("../../settings/model/settings");
        await act(async () => saveComposerRunner(true));
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "claude",
            model: "claude-sonnet",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            chat,
            runnerAvatar: chat ? createElement("svg", { "data-agent-avatar": "" }) : undefined,
            busy: true,
            onFocus: () => { },
            onCwdChange: () => { },
            onModelChange: () => { },
            onRuntimeModeChange: () => { },
            onSubmit: vi.fn(),
        })));
        expect(document.querySelector(".composer-runner")).not.toBeNull();
        expect(document.querySelector(".composer-runner [data-agent-avatar]") != null).toBe(chat);
        await act(async () => saveComposerRunner(false));
        expect(document.querySelector(".composer-runner")).toBeNull();
        await act(async () => saveComposerRunner(true));
        expect(document.querySelector(".composer-runner")).not.toBeNull();
        expect(document.querySelector(".composer-runner [data-agent-avatar]") != null).toBe(chat);
    });
    it("keeps the draft when onBtwCommand rejects the command", async () => {
        const onBtwCommand = vi.fn(() => false);
        const onSubmit = vi.fn();
        await renderComposer(undefined, vi.fn(), false, 0, "/btw", onBtwCommand, onSubmit);
        const textarea = container.querySelector("textarea")!;
        await act(async () => textarea.dispatchEvent(new KeyboardEvent("keydown", {
            key: "Enter",
            bubbles: true,
            cancelable: true,
        })));
        expect(onBtwCommand).toHaveBeenCalledWith("");
        expect(onSubmit).not.toHaveBeenCalled();
        expect(textarea.value).toBe("/btw");
    });
    it("clears the draft when the reset token advances", async () => {
        const onDraftChange = vi.fn();
        const props = {
            focused: true,
            harness: "claude" as const,
            model: "claude-sonnet",
            runtimeMode: "supervised" as const,
            executionCwd: "/repo",
            hideProjectPicker: true,
            initialDraft: "something here...",
            draftResetToken: 1,
            onDraftChange,
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit: vi.fn(),
        };
        await act(async () => root.render(createElement(Composer, props)));
        expect(container.querySelector("textarea")?.value).toBe("something here...");
        await act(async () => root.render(createElement(Composer, { ...props, draftResetToken: 2 })));
        expect(container.querySelector("textarea")?.value).toBe("");
        expect(onDraftChange).toHaveBeenLastCalledWith("");
    });
    it("places the caret at the end of an initial draft", async () => {
        const initialDraft = "Comment on src/App.tsx:42\n\n";
        await renderComposer(undefined, vi.fn(), false, 0, initialDraft);
        const textarea = container.querySelector("textarea")!;
        expect(textarea.value).toBe(initialDraft);
        expect(textarea.selectionStart).toBe(initialDraft.length);
        expect(textarea.selectionEnd).toBe(initialDraft.length);
    });
    it("clears the parent draft before submit so a remounting composer stays empty", async () => {
        let parentDraft = "Ship the empty-state fix";
        const onDraftChange = vi.fn((text: string) => {
            parentDraft = text;
        });
        const baseProps = {
            focused: true,
            harness: "claude" as const,
            model: "claude-sonnet",
            runtimeMode: "supervised" as const,
            executionCwd: "/repo",
            hideProjectPicker: true,
            initialDraft: parentDraft,
            onDraftChange,
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
        };
        const onSubmit = vi.fn(() => {
            act(() => root.render(createElement(Composer, {
                ...baseProps,
                key: "docked",
                initialDraft: parentDraft,
                onSubmit,
            })));
            return true;
        });
        await act(async () => root.render(createElement(Composer, { ...baseProps, key: "empty", onSubmit })));
        const textarea = container.querySelector("textarea")!;
        expect(textarea.value).toBe("Ship the empty-state fix");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        expect(onSubmit).toHaveBeenCalledWith("Ship the empty-state fix", [], {});
        expect(onDraftChange).toHaveBeenCalledWith("");
        expect(parentDraft).toBe("");
        expect(textarea.value).toBe("");
    });
    it("restores the draft when submit is rejected", async () => {
        let parentDraft = "Waiting for the request to be accepted";
        const onDraftChange = vi.fn((text: string) => {
            parentDraft = text;
        });
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "claude",
            model: "claude-sonnet",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            initialDraft: parentDraft,
            onDraftChange,
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit: () => false,
        })));
        const textarea = container.querySelector("textarea")!;
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        expect(textarea.value).toBe("Waiting for the request to be accepted");
        expect(parentDraft).toBe("Waiting for the request to be accepted");
    });
    it("does not restore a failed resend over newer composer text", async () => {
        let recallLastTurn: (() => void) | undefined;
        let rejectResend: ComposerTurnOptions["onResendRejected"];
        const onSubmit = vi.fn((_text: string, _files: Attachment[], options?: ComposerTurnOptions) => {
            rejectResend = options?.onResendRejected;
            return true;
        });
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "codex",
            model: "pi:default",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            editLastTurnSupported: true,
            lastTurnRecall: { text: "Original prompt", attachments: [] },
            onRecallLastTurnReady: (recall) => {
                recallLastTurn = recall;
            },
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit,
        })));
        await act(async () => recallLastTurn?.());
        const textarea = container.querySelector("textarea")!;
        expect(textarea.value).toBe("Original prompt");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        await act(async () => {
            textarea.value = "New prompt";
            textarea.dispatchEvent(new Event("input", { bubbles: true }));
        });
        await act(async () => rejectResend?.({ providerRewound: false }));
        expect(textarea.value).toBe("New prompt");
    });
    it("retries an already rewound prompt as a normal submission", async () => {
        let recallLastTurn: (() => void) | undefined;
        let rejectResend: ComposerTurnOptions["onResendRejected"];
        const onSubmit = vi.fn((_text: string, _files: Attachment[], options?: ComposerTurnOptions) => {
            rejectResend = options?.onResendRejected;
            return true;
        });
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "codex",
            model: "pi:default",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            editLastTurnSupported: true,
            lastTurnRecall: { text: "Edited prompt", attachments: [] },
            onRecallLastTurnReady: (recall) => {
                recallLastTurn = recall;
            },
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit,
        })));
        await act(async () => recallLastTurn?.());
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        await act(async () => rejectResend?.({ providerRewound: true }));
        const textarea = container.querySelector("textarea")!;
        expect(textarea.value).toBe("Edited prompt");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        expect(onSubmit).toHaveBeenCalledTimes(2);
        expect(onSubmit.mock.calls[1][2]).toEqual({});
    });
    it("preserves attachment ownership when a resend is restored", async () => {
        const createObjectURL = vi.fn(() => "blob:owned");
        const revokeObjectURL = vi.fn();
        vi.stubGlobal("URL", { createObjectURL, revokeObjectURL });
        let recallLastTurn: (() => void) | undefined;
        let rejectResend: ComposerTurnOptions["onResendRejected"];
        const borrowed: Attachment = {
            id: "borrowed",
            name: "borrowed.png",
            mimeType: "image/png",
            kind: "image",
            size: 3,
            previewUrl: "blob:borrowed",
        };
        const onSubmit = vi.fn((_text: string, _files: Attachment[], options?: ComposerTurnOptions) => {
            rejectResend = options?.onResendRejected;
            return true;
        });
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "codex",
            model: "pi:default",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            editLastTurnSupported: true,
            lastTurnRecall: {
                text: "Edited prompt",
                attachments: [borrowed],
            },
            onRecallLastTurnReady: (recall) => {
                recallLastTurn = recall;
            },
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit,
        })));
        await act(async () => recallLastTurn?.());
        const owned = new File(["new"], "owned.png", { type: "image/png" });
        const paste = new Event("paste", { bubbles: true, cancelable: true });
        Object.defineProperty(paste, "clipboardData", {
            value: {
                getData: () => "",
                files: [owned],
                items: [
                    {
                        kind: "file",
                        type: owned.type,
                        getAsFile: () => owned,
                    },
                ],
            },
        });
        await act(async () => {
            container.querySelector("textarea")!.dispatchEvent(paste);
            await new Promise((resolve) => setTimeout(resolve, 20));
        });
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Send"]')!
            .click());
        await act(async () => rejectResend?.({ providerRewound: false }));
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Remove owned.png"]')!
            .click());
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Remove borrowed.png"]')!
            .click());
        expect(createObjectURL).toHaveBeenCalledOnce();
        expect(revokeObjectURL).toHaveBeenCalledWith("blob:owned");
        expect(revokeObjectURL).not.toHaveBeenCalledWith("blob:borrowed");
    });
    it("saves a new message as a draft without submitting it", async () => {
        const onSubmit = vi.fn();
        const onSaveDraft = vi.fn();
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "claude",
            model: "claude-sonnet",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            hideProjectPicker: true,
            canSaveDraft: true,
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit,
            onSaveDraft,
        })));
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Add files or choose a mode"]')!
            .click());
        const draftMode = [
            ...document.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.includes("Save this message"));
        expect(draftMode).toBeDefined();
        await act(async () => draftMode!.click());
        const textarea = container.querySelector("textarea")!;
        await act(async () => {
            textarea.value = "Explore a quieter empty state";
            textarea.dispatchEvent(new Event("input", { bubbles: true }));
        });
        const save = container.querySelector<HTMLButtonElement>('[aria-label="Save draft"]');
        expect(save?.disabled).toBe(false);
        await act(async () => save!.click());
        expect(onSaveDraft).toHaveBeenCalledWith("Explore a quieter empty state", []);
        expect(onSubmit).not.toHaveBeenCalled();
        expect(textarea.value).toBe("");
    });
    it("saves a /draft message as a draft and keeps the command in the text", async () => {
        const onSubmit = vi.fn();
        const onSaveDraft = vi.fn();
        await act(async () => root.render(createElement(Composer, {
            focused: true,
            harness: "claude",
            model: "claude-sonnet",
            runtimeMode: "supervised",
            executionCwd: "/repo",
            initialDraft: "/dra",
            hideProjectPicker: true,
            canSaveDraft: true,
            onFocus: vi.fn(),
            onCwdChange: vi.fn(),
            onModelChange: vi.fn(),
            onRuntimeModeChange: vi.fn(),
            onSubmit,
            onSaveDraft,
        })));
        const textarea = container.querySelector("textarea")!;
        await act(async () => textarea.dispatchEvent(new Event("input", { bubbles: true })));
        const command = Array.from(container.querySelectorAll<HTMLButtonElement>('[role="option"]')).find((button) => button.textContent?.includes("/draft"));
        expect(command).toBeDefined();
        await act(async () => command!.click());
        expect(textarea.value).toBe("/draft ");
        expect(container.querySelector('[title="Turn off Draft mode"]')).not.toBeNull();
        await act(async () => {
            textarea.value += "Explore a quieter empty state";
            textarea.dispatchEvent(new Event("input", { bubbles: true }));
        });
        const save = container.querySelector<HTMLButtonElement>('[aria-label="Save draft"]');
        expect(save).not.toBeNull();
        await act(async () => save!.click());
        expect(onSaveDraft).toHaveBeenCalledWith("Explore a quieter empty state", []);
        expect(onSubmit).not.toHaveBeenCalled();
        expect(textarea.value).toBe("");
    });
    it("returns focus to the composer textarea once a question is answered", async () => {
        const onQuestionReply = vi.fn();
        await renderComposer(question, onQuestionReply);
        await act(async () => (container.querySelector("button[aria-pressed]") as HTMLButtonElement).click());
        await act(async () => (container.querySelector('button[type="submit"]') as HTMLButtonElement).click());
        expect(onQuestionReply).toHaveBeenCalledWith(1, {
            kind: "answered",
            answers: { q1: ["a"] },
        });
        // The real app clears `question` once onQuestionReply resolves it.
        await renderComposer(undefined, onQuestionReply);
        expect(document.activeElement).toBe(container.querySelector("textarea"));
    });
    it("returns focus to the composer textarea once the agent turn finishes", async () => {
        await renderComposer(undefined, vi.fn(), true);
        const textarea = container.querySelector("textarea") as HTMLTextAreaElement;
        const decoy = document.createElement("input");
        document.body.append(decoy);
        decoy.focus();
        expect(document.activeElement).toBe(decoy);
        await renderComposer(undefined, vi.fn(), false);
        expect(document.activeElement).toBe(textarea);
        decoy.remove();
    });
    it("returns focus to the composer textarea when focusToken bumps while already focused", async () => {
        await renderComposer(undefined, vi.fn());
        const textarea = container.querySelector("textarea") as HTMLTextAreaElement;
        const decoy = document.createElement("input");
        document.body.append(decoy);
        decoy.focus();
        expect(document.activeElement).toBe(decoy);
        // `focused` never changes value here (stays true throughout) — mirrors a
        // real window blur/refocus, where React's composerFocused state doesn't
        // change even though the OS took DOM focus away and back.
        await renderComposer(undefined, vi.fn(), false, 1);
        expect(document.activeElement).toBe(textarea);
        decoy.remove();
    });
    it("does not steal focus from a control inside a different composer", async () => {
        await renderComposer(undefined, vi.fn(), true);
        // Simulates focus reaching another mounted Composer's control via
        // keyboard Tab navigation, which never fires the onMouseDown-based
        // onFocus that would normally update which pane is "focused".
        const otherComposer = document.createElement("div");
        otherComposer.setAttribute("data-composer", "");
        const otherInput = document.createElement("textarea");
        otherComposer.append(otherInput);
        document.body.append(otherComposer);
        otherInput.focus();
        expect(document.activeElement).toBe(otherInput);
        await renderComposer(undefined, vi.fn(), false);
        expect(document.activeElement).toBe(otherInput);
        otherComposer.remove();
    });
    it("moves focus from a visible split composer when explicitly requested", async () => {
        await renderComposer(undefined, vi.fn(), false, 0);
        const otherComposer = document.createElement("div");
        otherComposer.setAttribute("data-composer", "");
        const otherInput = document.createElement("textarea");
        otherComposer.append(otherInput);
        document.body.append(otherComposer);
        try {
            otherInput.focus();
            expect(document.activeElement).toBe(otherInput);
            await renderComposer(undefined, vi.fn(), false, 1);
            expect(document.activeElement).toBe(container.querySelector("textarea"));
        } finally {
            otherComposer.remove();
        }
    });
    it("focuses a newly mounted split composer after an explicit split request", async () => {
        const otherComposer = document.createElement("div");
        otherComposer.setAttribute("data-composer", "");
        const otherInput = document.createElement("textarea");
        otherComposer.append(otherInput);
        document.body.append(otherComposer);
        try {
            otherInput.focus();
            await renderComposer(undefined, vi.fn(), false, 1);
            expect(document.activeElement).toBe(container.querySelector("textarea"));
        } finally {
            otherComposer.remove();
        }
    });
    it("takes focus from a composer in a hidden session", async () => {
        const hiddenSession = document.createElement("div");
        hiddenSession.setAttribute("aria-hidden", "true");
        const hiddenComposer = document.createElement("div");
        hiddenComposer.setAttribute("data-composer", "");
        const hiddenInput = document.createElement("textarea");
        hiddenComposer.append(hiddenInput);
        hiddenSession.append(hiddenComposer);
        document.body.append(hiddenSession);
        hiddenInput.focus();
        expect(document.activeElement).toBe(hiddenInput);
        await renderComposer(undefined, vi.fn());
        expect(document.activeElement).toBe(container.querySelector("textarea"));
        hiddenSession.remove();
    });
    it("does not steal focus from a picker portaled outside the composer", async () => {
        await renderComposer(undefined, vi.fn(), true);
        // Popover.tsx portals picker content directly into document.body, so it
        // never sits under this composer's own [data-composer] subtree.
        const portaledPicker = document.createElement("div");
        portaledPicker.setAttribute("data-model-picker", "");
        const searchInput = document.createElement("input");
        portaledPicker.append(searchInput);
        document.body.append(portaledPicker);
        searchInput.focus();
        expect(document.activeElement).toBe(searchInput);
        await renderComposer(undefined, vi.fn(), false);
        expect(document.activeElement).toBe(searchInput);
        portaledPicker.remove();
    });
});
