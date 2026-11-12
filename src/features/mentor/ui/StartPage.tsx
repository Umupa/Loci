import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { getHarnessAvailabilitySnapshot, hasProbedHarnessAvailability, isHarnessAvailable, probeHarnessAvailability, subscribeHarnessAvailability } from "../../../integrations/harness/core/availability";
import { HARNESSES } from "../../sessions/model/session";
import { X } from "../../../shared/ui/icons";
import { START_EXAMPLES } from "../model/startMentor";
import "./StartPage.css";

/** The agent CLIs a learner is most likely to have an account for, with how to install and sign in. */
const INSTALL = [
  { name: "Claude Code", install: "npm install -g @anthropic-ai/claude-code", login: "claude" },
  { name: "Codex", install: "npm install -g @openai/codex", login: "codex login" },
  { name: "Grok Build", install: "curl -fsSL https://x.ai/cli/install.sh | bash", login: "grok" },
] as const;

type Props = {
  /** Makes the mentor and sends the request as its first message. */
  onStart: (text: string) => Promise<void>;
  /** The template gallery, for a mentor made another way. */
  onTemplates: () => void;
  /** Back to the mentor that was open; absent when there is none. */
  onClose?: () => void;
  /** At the end of the top row, such as the window's buttons. */
  trailing?: ReactNode;
};

/** Whether any agent CLI was found on this computer, once the first look is done. */
function useAnyAgentCli(): { known: boolean; any: boolean; checking: boolean; check: () => void } {
  useSyncExternalStore(subscribeHarnessAvailability, getHarnessAvailabilitySnapshot, getHarnessAvailabilitySnapshot);
  const [checking, setChecking] = useState(false);
  const [looked, setLooked] = useState(false);
  const check = () => {
    setChecking(true);
    void probeHarnessAvailability({ force: true }).finally(() => { setChecking(false); setLooked(true); });
  };
  // Looked at afresh each time the page opens: a CLI may have been installed since.
  useEffect(() => { check(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const any = HARNESSES.some(isHarnessAvailable);
  return { known: any || (looked && hasProbedHarnessAvailability()), any, checking, check };
}

/**
 * Where a mentor begins: one question, a box for the answer and a few
 * answers to start from. Without an agent CLI on the computer it says what
 * to install instead.
 */
export function StartPage({ onStart, onTemplates, onClose, trailing }: Props) {
  const [text, setText] = useState("");
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string>();
  const field = useRef<HTMLTextAreaElement>(null);
  const cli = useAnyAgentCli();
  const missing = cli.known && !cli.any;

  const start = async () => {
    const request = text.trim();
    if (!request || starting) return;
    setStarting(true); setError(undefined);
    try { await onStart(request); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); setStarting(false); }
  };

  return <div className="start-page" data-start-page onKeyDown={(event) => {
    if (event.key === "Escape" && onClose && !event.defaultPrevented) { event.preventDefault(); onClose(); }
  }}>
    <div className="start-page__bar" data-tauri-drag-region="deep">
      {onClose ? <button type="button" className="mentor-bar-button" aria-label="Close" title="Close" onClick={onClose}><X className="size-4" /></button> : null}
      {trailing}
    </div>
    <main className="start-page__body">
      {missing ? <section className="start-page__install" aria-label="Install an agent CLI">
        <h1>Install an agent CLI</h1>
        <p>Your mentor runs on an agent CLI on this computer. Install one, then sign in from a terminal.</p>
        <ul>
          {INSTALL.map((entry) => <li key={entry.name}>
            <span className="start-page__cli">{entry.name}</span>
            <code>{entry.install}</code>
            <code>{entry.login}</code>
          </li>)}
        </ul>
        <button type="button" className="primary-action rounded-md px-3 py-1.5 text-sm font-medium" disabled={cli.checking} onClick={cli.check}>
          {cli.checking ? "Checking…" : "Check again"}
        </button>
      </section> : <>
        <h1 id="start-question">What do you want to learn?</h1>
        <textarea ref={field} className="start-page__field" aria-labelledby="start-question" autoFocus rows={4} value={text} disabled={starting}
          placeholder="What for, and what you already know…"
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key !== "Enter" || event.shiftKey || event.nativeEvent.isComposing) return;
            event.preventDefault();
            void start();
          }} />
        {starting ? <p role="status" className="start-page__status">Starting…</p> : null}
        {error ? <p role="alert" className="start-page__error">{error}</p> : null}
        <ul className="start-page__examples" aria-label="Examples">
          {START_EXAMPLES.map((example) => <li key={example}>
            <button type="button" disabled={starting} onClick={() => { setText(example); field.current?.focus(); }}>{example}</button>
          </li>)}
        </ul>
      </>}
      <button type="button" className="start-page__templates" onClick={onTemplates}>From a template…</button>
    </main>
  </div>;
}
