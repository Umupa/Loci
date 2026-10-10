import { diffLines } from "diff";
import type { HighlightResult } from "@streamdown/code";
import type { BundledLanguage } from "shiki";
import { useEffect, useMemo, useState } from "react";
import { copyText } from "../../../platform/tauri/clipboard";
import { useCodePlugin } from "../../../shared/hooks/useCodePlugin";
import { useColorScheme } from "../../../shared/hooks/useColorScheme";
import { Copy } from "../../../shared/ui/icons";
import { parseDiff, type DiffSpec } from "../model/course";
import "./DiffCard.css";

export type DiffLine = { kind: "add" | "remove" | "equal"; text: string; beforeLine?: number; afterLine?: number };
export function computeLineDiff(before: string, after: string): DiffLine[] | undefined {
  // Agent-authored files can be large or completely different. Bound both the
  // diff search and rendered rows; the fallback retains the complete code.
  if (before.length + after.length > 200_000) return undefined;
  const changes = diffLines(before, after, { timeout: 50, maxEditLength: 1000 });
  if (!changes) return undefined;
  let beforeLine = 0, afterLine = 0;
  const result = changes.flatMap((part) => {
    const lines = part.value.split("\n");
    if (part.value.endsWith("\n")) lines.pop();
    return lines.map((text): DiffLine => {
      const kind = part.added ? "add" : part.removed ? "remove" : "equal";
      return { kind, text, ...(kind !== "add" ? { beforeLine: ++beforeLine } : {}), ...(kind !== "remove" ? { afterLine: ++afterLine } : {}) };
    });
  });
  return result.length > 2000 ? undefined : result;
}

function languageFromFile(file: string): BundledLanguage {
  const name = file.split(/[/\\]/).pop()!.toLowerCase();
  const extension = name.includes(".") ? name.slice(name.lastIndexOf(".") + 1) : name;
  const aliases: Record<string, BundledLanguage> = { py: "python", js: "javascript", jsx: "jsx", ts: "typescript", tsx: "tsx", rs: "rust", rb: "ruby", sh: "bash", zsh: "bash", yml: "yaml", md: "markdown", h: "c", cpp: "cpp", cs: "csharp", dockerfile: "dockerfile", makefile: "makefile" };
  return aliases[extension] ?? extension as BundledLanguage;
}

export type DiffCardProps = DiffSpec;
export function DiffCard({ id, title, file, before, after, runCommand }: DiffCardProps) {
  const lines = useMemo(() => computeLineDiff(before, after), [before, after]);
  const plugin = useCodePlugin();
  const scheme = useColorScheme();
  const [tokens, setTokens] = useState<{ before?: HighlightResult; after?: HighlightResult }>({});
  const [copyState, setCopyState] = useState<"idle" | "busy" | "copied">("idle");
  const [copyError, setCopyError] = useState<string | null>(null);
  useEffect(() => {
    let current = true;
    setTokens({});
    if (!lines) return;
    const language = languageFromFile(file);
    for (const [side, code] of [["before", before], ["after", after]] as const) {
      const apply = (result: HighlightResult) => { if (current) setTokens((previous) => ({ ...previous, [side]: result })); };
      const result = plugin.highlight({ code, language, themes: plugin.getThemes() }, apply);
      if (result) apply(result);
    }
    return () => { current = false; };
  }, [plugin, file, before, after, lines]);
  useEffect(() => { setCopyState("idle"); setCopyError(null); }, [runCommand]);
  const copy = async () => {
    if (!runCommand || copyState === "busy") return;
    setCopyState("busy"); setCopyError(null);
    try { await copyText(runCommand); setCopyState("copied"); }
    catch (cause) { setCopyState("idle"); setCopyError(`Could not copy command: ${cause instanceof Error ? cause.message : String(cause)}`); }
  };
  const additions = lines?.filter((line) => line.kind === "add").length;
  const removals = lines?.filter((line) => line.kind === "remove").length;
  return <section className="diff-card" data-card="diff" data-diff-id={id} data-file={file} aria-label={title}>
    <header className="diff-card__header"><span className="diff-card__file" title={title}>{file}</span>{lines ? <span className="diff-card__stats"><span className="diff-card__add">+{additions}</span><span className="diff-card__remove">−{removals}</span></span> : null}{runCommand ? <button type="button" className="diff-card__run-btn" disabled={copyState === "busy"} onClick={() => void copy()} title={runCommand}><Copy className="size-3.5" />{copyState === "copied" ? "Copied" : "Copy command"}</button> : null}</header>
    {lines ? <pre className="diff-card__body"><code>{lines.length ? lines.map((line, index) => {
      const lineTokens = line.kind === "remove" ? tokens.before?.tokens[(line.beforeLine ?? 1) - 1] : tokens.after?.tokens[(line.afterLine ?? 1) - 1];
      return <span key={index} className={`diff-card__line diff-card__line--${line.kind}`}><span className="diff-card__number" aria-hidden="true">{line.beforeLine ?? ""}</span><span className="diff-card__number" aria-hidden="true">{line.afterLine ?? ""}</span><span className="diff-card__gutter" aria-hidden="true">{line.kind === "add" ? "+" : line.kind === "remove" ? "−" : " "}</span><span className="diff-card__text">{lineTokens?.length ? lineTokens.map((token, tokenIndex) => <span key={tokenIndex} style={{ color: scheme === "dark" ? token.htmlStyle?.["--shiki-dark"] ?? token.color : token.color }}>{token.content}</span>) : line.text || " "}</span></span>;
    }) : <span className="diff-card__empty">Both files are empty.</span>}</code></pre> : <div className="diff-card__fallback"><p role="status">This change is too large for a line diff. Read the full code below.</p><details><summary>Before</summary><pre><code>{before || "(empty file)"}</code></pre></details><details><summary>After</summary><pre><code>{after || "(empty file)"}</code></pre></details></div>}
    {runCommand ? <div className="diff-card__command"><code>{runCommand}</code></div> : null}
    {copyError ? <p className="diff-card__error" role="alert">{copyError}</p> : null}
  </section>;
}

export function DiffCardFromSource({ source }: { source: string }) {
  const result = useMemo(() => parseDiff(source), [source]);
  return result.diff ? <DiffCard {...result.diff} /> : <div data-card="diff" className="diff-card diff-card--error"><p role="alert">{result.error}</p><details><summary>View source</summary><pre>{source}</pre></details></div>;
}
