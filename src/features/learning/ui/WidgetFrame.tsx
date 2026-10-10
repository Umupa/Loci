import { useEffect, useRef, useState } from "react";
import { useColorScheme } from "../../../shared/hooks/useColorScheme";
import { changeWidgetState, parseRuntimeMessage, WIDGET_PROXY_URL } from "../model/widgetRuntime";
import { widgetRef } from "../model/widgets";
import type { StoredWidget } from "../model/types";

type Props = {
  widget: StoredWidget;
  expanded?: boolean;
  onAsk: (text: string, selection?: string) => void | Promise<void>;
  onOpenSource: (id: string) => void | Promise<void>;
};

/** Copy presentation tokens only; the sandbox never reads the host document. */
function themeTokens() {
  const styles = getComputedStyle(document.documentElement);
  return Object.fromEntries([
    ["--loci-background", "--color-background-base"],
    ["--loci-text", "--color-content"],
    ["--loci-accent", "--color-accent"],
    ["--loci-font", "--font-sans"],
    ["--loci-mono", "--font-mono"],
  ].map(([target, source]) => [target, styles.getPropertyValue(source).trim()]).filter(([, value]) => value));
}

/** Only the fixed, trusted proxy receives a channel to Loci; generated HTML lives one opaque frame deeper. */
export function WidgetFrame({ widget, expanded = false, onAsk, onOpenSource }: Props) {
  const frame = useRef<HTMLIFrameElement>(null);
  const port = useRef<MessagePort | null>(null);
  const latest = useRef({ widget, onAsk, onOpenSource });
  latest.current = { widget, onAsk, onOpenSource };
  const theme = useColorScheme();
  const [height, setHeight] = useState(320);
  const [error, setError] = useState<string | null>(null);
  const [repairError, setRepairError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => () => { port.current?.close(); }, []);
  useEffect(() => { setReady(false); setError(null); setRepairError(null); }, [widget.html, widget.revision]);
  useEffect(() => { port.current?.postMessage({ type: "state", state: widget.state }); }, [widget.state]);
  useEffect(() => {
    const sync = () => port.current?.postMessage({ type: "theme", theme, tokens: themeTokens() });
    sync();
    // Palette and font changes do not necessarily change light/dark mode.
    const observer = new MutationObserver(sync);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class", "style"] });
    return () => observer.disconnect();
  }, [theme]);

  const connect = () => {
    const target = frame.current?.contentWindow;
    if (!target) return;
    port.current?.close();
    const channel = new MessageChannel();
    port.current = channel.port1;
    channel.port1.onmessage = (event) => {
      const current = latest.current;
      const message = parseRuntimeMessage(event.data, current.widget.sourceIds);
      if (!message) return;
      if (message.type === "ready") { setReady(true); return; }
      if (message.type === "resize") { setHeight(message.height); return; }
      if (message.type === "error") { setError(message.message); return; }
      const result = message.type === "state" ? changeWidgetState(widgetRef(current.widget), message.state)
        : message.type === "ask" ? current.onAsk(message.text, message.selection)
          : current.onOpenSource(message.id);
      if (result) void result.catch((cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)));
    };
    channel.port1.start();
    // The proxy's response CSP also sandboxes its origin. The capability goes
    // only to this fixed frame's WindowProxy, never a global message listener.
    target.postMessage({ type: "loci-widget-init", html: widget.html, state: widget.state, theme, tokens: themeTokens() }, "*", [channel.port2]);
  };
  const prepareFix = () => {
    if (!error) return;
    setRepairError(null);
    void Promise.resolve().then(() => latest.current.onAsk(`请修复这个交互讲解，沿用 id "${latest.current.widget.id}"，保留当前状态、教学意图与来源，并返回完整的新版本。\n\n运行错误：${error}`))
      .catch((cause: unknown) => setRepairError(cause instanceof Error ? cause.message : String(cause)));
  };

  return (
    <div className={`relative min-h-40 min-w-0 ${expanded ? "flex h-full min-h-0 flex-col" : ""}`}>
      {!ready && !error ? <div className="pointer-events-none absolute inset-0 grid place-items-center text-xs text-content/45"><span className="flex items-center gap-2"><span className="size-1.5 rounded-full bg-content/25" />Opening explanation…</span></div> : null}
      <iframe key={`${widget.revision}:${widget.html}`} ref={frame} title={widget.title} src={WIDGET_PROXY_URL}
        onLoad={connect} sandbox="allow-scripts" referrerPolicy="no-referrer"
        className={`block w-full border-0 ${expanded ? "min-h-0 flex-1" : ""}`} style={expanded ? undefined : { height }} />
      {error ? <div role="alert" className="learning-widget-error">{error}<button type="button" className="learning-widget-action mt-2" onClick={prepareFix}>Prepare fix</button>{repairError ? <p className="mt-1">{repairError}</p> : null}<details className="learning-widget-code mt-2"><summary>View generated source</summary><pre>{widget.html}</pre></details></div> : null}
    </div>
  );
}
