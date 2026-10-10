import { useContext, useEffect, useMemo, useState } from "react";
import { AiIdea, ChevronDown, CircleDashed, FileScript, Maximize2, MessageSquarePlus, MoreHorizontal, Pin, X } from "../../../shared/ui/icons";
import { ContextMenu } from "../../../shared/ui/ContextMenu";
import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { askAboutWidget } from "../model/widgetContext";
import { getLearningSource } from "../model/learningStore";
import { openLearningSource } from "../model/navigation";
import { retainWidget, useWidget } from "../model/widgetRuntime";
import { openWidget, parseWidget, WidgetHostContext, widgetRef, type WidgetHost } from "../model/widgets";
import type { LearningSource, StoredWidget, WidgetSpec } from "../model/types";
import { WidgetFrame } from "./WidgetFrame";
import "./WidgetCard.css";

export { WidgetHostContext } from "../model/widgets";
const shell = "learning-widget-card my-1.5 w-full max-w-[44rem] overflow-hidden rounded-2xl border border-stroke bg-background-base/50 font-sans";
const action = "learning-widget-action";

export function WidgetCard({ source, incomplete }: { source: string; incomplete: boolean }) {
  const result = useMemo(() => parseWidget(source), [source]);
  const host = useContext(WidgetHostContext);
  const [repairError, setRepairError] = useState<string | null>(null);
  const prepareFix = () => {
    if (!host) return;
    const targetSessionId = host.owner.kind === "agent" ? findAgent(host.owner.id)?.sessionId : host.sourceSessionId;
    if (!targetSessionId) { setRepairError("Open the original conversation before preparing a fix."); return; }
    const longest = Math.max(2, ...(source.match(/`+/g) ?? []).map((run) => run.length));
    const fence = "`".repeat(longest + 1);
    requestAddToChat(`请修复这个交互讲解的格式错误，保留教学意图与来源；已有合法 id 时沿用该 id，返回完整的 loci-widget。\n\n错误：${result.error}\n\n${fence}loci-widget\n${source}\n${fence}`, "plain", { targetSessionId });
    setRepairError(null);
  };
  if (incomplete) return <div data-card="widget" className={`${shell} learning-widget-pending`}><span className="learning-widget-emblem"><CircleDashed className="size-4" strokeWidth={1.75} /></span><div><span className="block text-[13px] font-medium text-content/85">Interactive explanation</span><span className="block mt-0.5 text-xs text-content/50">Building an interactive explanation…</span></div></div>;
  if (!result.spec || !host) return <div data-card="widget" className={`${shell} p-4`}><div className="flex items-start gap-2.5"><AiIdea className="mt-0.5 size-4 shrink-0 text-content/45" strokeWidth={1.75} /><p role="alert" className="text-[13px] leading-relaxed text-content/65">{result.error ?? "Open this explanation in its original conversation to interact with it."}</p></div>{host && result.error ? <button type="button" className={`${action} mt-3`} onClick={prepareFix}>Prepare fix</button> : null}{repairError ? <p role="alert" className="mt-2 text-xs text-red-400">{repairError}</p> : null}<details className="learning-widget-code mt-3"><summary>View source</summary><pre>{source}</pre></details></div>;
  return <ReadyWidgetCard spec={result.spec} host={host} />;
}

function ReadyWidgetCard({ spec, host }: { spec: WidgetSpec; host: WidgetHost }) {
  const ref = useMemo(() => ({ owner: host.owner, id: spec.id }), [host.owner.kind, host.owner.id, spec.id]);
  const widget = useWidget(ref, spec, host.sourceSessionId);
  return <div data-card="widget" className={shell}><WidgetToolbar widget={widget} /><WidgetFrame widget={widget} onAsk={(text, selection) => askAboutWidget(widget, text, selection)} onOpenSource={openLearningSource} /></div>;
}

export function WidgetToolbar({ widget, expanded = false }: { widget: StoredWidget; expanded?: boolean }) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [sourcesOpen, setSourcesOpen] = useState(false);
  const [sourceOpen, setSourceOpen] = useState(false);
  const [menuAnchor, setMenuAnchor] = useState<HTMLButtonElement | null>(null);
  const [sources, setSources] = useState<(LearningSource | null)[]>([]);
  useEffect(() => {
    let current = true;
    void Promise.all(widget.sourceIds.map(getLearningSource)).then((found) => { if (current) setSources(found); }).catch(() => { if (current) setSources([]); });
    return () => { current = false; };
  }, [widget.sourceIds.join("\0")]);
  const run = (work: () => Promise<unknown> | void) => {
    setError(null);
    void Promise.resolve().then(work).catch((cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)));
  };
  const save = async () => {
    setBusy(true);
    try { await retainWidget(widgetRef(widget), !widget.saved); }
    finally { setBusy(false); }
  };
  return <>
    <div className={`learning-widget-toolbar ${expanded ? "learning-widget-toolbar-expanded" : ""}`}>
      <span className="learning-widget-emblem" aria-hidden><AiIdea className="size-4" strokeWidth={1.75} /></span>
      <div className="learning-widget-heading"><span className="learning-widget-title" title={widget.title}>{expanded ? widget.subject ?? "Interactive explanation" : widget.title}</span>{!expanded || widget.sourceIds.length ? <div className="learning-widget-meta">{!expanded ? <span className="truncate">{widget.subject ?? "Interactive explanation"}</span> : null}{widget.sourceIds.length ? <>{!expanded ? <span aria-hidden className="opacity-50">·</span> : null}<button type="button" aria-label="Sources" aria-expanded={sourcesOpen} onClick={() => setSourcesOpen(!sourcesOpen)}>{widget.sourceIds.length} {widget.sourceIds.length === 1 ? "source" : "sources"}<ChevronDown className={`size-3 transition-transform ${sourcesOpen ? "rotate-180" : ""}`} /></button></> : null}</div> : null}</div>
      <div className="learning-widget-tools">
        <button type="button" className={`${action} learning-widget-ask`} aria-label="Ask" title="Ask about this explanation" onClick={() => run(() => askAboutWidget(widget, "这里我还没理解，请结合当前条件和原文解释。"))}><MessageSquarePlus className="size-3.5" strokeWidth={1.75} /><span>Ask</span></button>
        <button type="button" className={`${action} learning-widget-icon`} aria-label={busy ? "Saving…" : widget.saved ? "Saved · Remove" : "Keep in Library"} title={busy ? "Saving…" : widget.saved ? "Saved · Remove" : "Keep in Library"} aria-pressed={widget.saved} disabled={busy || widget.revision === 0} onClick={() => run(save)}><Pin className="size-3.5" strokeWidth={1.75} /></button>
        {!expanded ? <button type="button" className={`${action} learning-widget-icon`} aria-label="Expand" title="Expand" disabled={widget.revision === 0} onClick={() => openWidget(widgetRef(widget), widget.sourceSessionId, widget.title)}><Maximize2 className="size-3.5" strokeWidth={1.75} /></button> : null}
        <button type="button" className={`${action} learning-widget-icon`} aria-label="Explanation actions" title="Explanation actions" aria-haspopup="menu" aria-expanded={!!menuAnchor} onClick={(event) => setMenuAnchor(menuAnchor ? null : event.currentTarget)}><MoreHorizontal className="size-4" strokeWidth={1.75} /></button>
      </div>
    </div>
    {menuAnchor ? <ContextMenu ownerId="learning-widget" x={menuAnchor.getBoundingClientRect().right - 216} y={menuAnchor.getBoundingClientRect().bottom + 6} width={216} ariaLabel="Explanation actions" items={[
      { kind: "item", id: "html", label: sourceOpen ? "Hide HTML" : "HTML" },
      { kind: "sep" },
      { kind: "item", id: "canvas", label: "Prepare canvas" },
      { kind: "item", id: "article", label: "Prepare article" },
    ]} onClose={() => setMenuAnchor(null)} onPick={(id) => {
      setMenuAnchor(null);
      if (id === "html") setSourceOpen(!sourceOpen);
      else run(() => askAboutWidget(widget, id === "canvas" ? "请将这个讲解和当前条件总结成画布，保留关键关系并引用原文。" : "请将这个讲解、当前条件与原文整理为一篇博客草稿，清楚区分原文依据、推导和实验结果。"));
    }} /> : null}
    {sourcesOpen ? <div className="learning-widget-sources">{widget.sourceIds.map((id, index) => <button key={id} type="button" className={action} onClick={() => run(() => openLearningSource(id))}><FileScript className="size-3.5 shrink-0" strokeWidth={1.75} /><span className="truncate">{sources[index]?.title ?? `Source ${index + 1}`}</span></button>)}</div> : null}
    {sourceOpen ? <div className="learning-widget-source"><div className="flex items-center justify-between px-4 py-2 text-[11px] text-content/50"><span>Generated HTML</span><button type="button" className={`${action} learning-widget-icon`} aria-label="Hide HTML" onClick={() => setSourceOpen(false)}><X className="size-3" /></button></div><pre>{widget.html}</pre></div> : null}
    {error ? <p role="alert" className="learning-widget-error">{error}</p> : null}
  </>;
}
