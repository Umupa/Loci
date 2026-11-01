import { Fragment, useEffect, useRef, useState, type RefObject } from "react";
import type { HighlightResult } from "@streamdown/code";
import type { BundledLanguage } from "shiki";
import { useCodePlugin } from "../hooks/useCodePlugin";
import { useColorScheme } from "../hooks/useColorScheme";
import { languageFromFile } from "../lib/markdown/codeLanguage";
import "./CodeReader.css";

/** Files beyond this stay plain text: highlighting and a per-line gutter would cost more than they give. */
export const CODE_READER_MAX_LINES = 12_000;
/** Beyond this the tokenizer is skipped and lines render as their own text. */
const HIGHLIGHT_MAX_LINES = 4_000;

type Props = {
  text: string;
  /** The name the language is read from. */
  file: string;
  /** The file line the first line is, for excerpts that start part-way in. */
  firstLine?: number;
  /** The `<pre>` holding the text, for selection and highlight anchors. */
  preRef?: RefObject<HTMLPreElement | null>;
  /** An accessible name for the code region. */
  label?: string;
};

const lineCount = (text: string) => text.split("\n").length;

/**
 * A file read as a source: the same Shiki tokens sources use, one number per
 * line in a muted gutter, and no soft wrapping. The text nodes still hold the
 * exact file text, so selection, highlights and line links work unchanged.
 */
export function CodeReader({ text, file, firstLine = 1, preRef, label }: Props) {
  const plugin = useCodePlugin();
  const scheme = useColorScheme();
  const language = languageFromFile(file);
  const key = `${language}\u0000${text}`;
  const [highlighted, setHighlighted] = useState<{ key: string; result: HighlightResult } | null>(null);
  const fallbackRef = useRef<HTMLPreElement>(null);
  const pre = preRef ?? fallbackRef;

  useEffect(() => {
    if (lineCount(text) > HIGHLIGHT_MAX_LINES) return;
    let live = true;
    const apply = (result: HighlightResult) => {
      if (live) setHighlighted({ key, result });
    };
    const cached = plugin.highlight({ code: text, language: language as BundledLanguage, themes: plugin.getThemes() }, apply);
    if (cached) apply(cached);
    return () => { live = false; };
  }, [plugin, language, key, text]);

  const lines = text.split("\n");
  const numbered = lines.length <= CODE_READER_MAX_LINES;
  const tokens = highlighted?.key === key ? highlighted.result.tokens : null;
  const gutterWidth = `calc(${String(firstLine + lines.length - 1).length}ch + 20px)`;

  return <div className="code-reader" data-code-reader>
    {numbered ? <div className="code-reader__gutter" aria-hidden data-anchor-skip style={{ width: gutterWidth }}>
      {lines.map((_, index) => <span className="code-reader__number" key={index}>{firstLine + index}</span>)}
    </div> : null}
    <div className="code-reader__scroll">
      <pre ref={pre} className="code-reader__pre" tabIndex={0} aria-label={label}><code>
        {lines.map((line, index) => <Fragment key={index}>
          {tokens?.[index]?.length
            ? tokens[index].map((token, at) => <span key={at} style={{ color: scheme === "dark" ? token.htmlStyle?.["--shiki-dark"] ?? token.htmlStyle?.color ?? token.color : token.htmlStyle?.color ?? token.color }}>{token.content}</span>)
            : line}
          {index < lines.length - 1 ? "\n" : null}
        </Fragment>)}
      </code></pre>
    </div>
  </div>;
}
