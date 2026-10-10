import { useState } from "react";
import { Globe, Plus } from "../../../shared/ui/icons";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";
import type { LearningSource } from "../model/types";
import "./AddWebSource.css";

export function AddWebSource({ onAdd, onCancel }: { onAdd: (source: LearningSource) => void; onCancel: () => void }) {
  const [url, setUrl] = useState("");
  const [quote, setQuote] = useState("");
  const [title, setTitle] = useState("");
  const [error, setError] = useState("");
  const add = () => {
    let parsed: URL;
    try {
      parsed = new URL(url.trim());
      if (!["http:", "https:"].includes(parsed.protocol)) throw new Error();
    } catch { setError("Enter an http or https URL."); return; }
    if (!quote.trim()) { setError("Paste the passage you want to discuss."); return; }
    onAdd({ id: crypto.randomUUID(), kind: "web", url: parsed.href, title: title.trim() || parsed.hostname, quote: quote.trim() });
  };
  return (
    <div className="learning-web-source" aria-label="Add web source">
      <div className="learning-web-source__heading">
        <span className="learning-web-source__icon"><Globe aria-hidden className="size-4" strokeWidth={1.75} /></span>
        <div className="min-w-0">
          <h3>Web reference</h3>
          <p>Add a passage to your question.</p>
        </div>
      </div>
      <label className="learning-web-source__field">
        <span>URL</span>
        <input autoFocus aria-label="Source URL" placeholder="https://…" value={url} onChange={(event) => setUrl(event.target.value)} autoCapitalize="none" spellCheck={false} />
      </label>
      <label className="learning-web-source__field">
        <span>Title <span className="learning-web-source__optional">Optional</span></span>
        <input aria-label="Source title" placeholder="Page title" value={title} onChange={(event) => setTitle(event.target.value)} />
      </label>
      <label className="learning-web-source__field">
        <span>Passage</span>
        <textarea aria-label="Quoted passage" placeholder="Paste the passage you want to discuss…" value={quote} onChange={(event) => setQuote(event.target.value)} rows={3} />
      </label>
      {error ? <p role="alert" className="learning-web-source__error text-red-400">{error}</p> : null}
      <div className="learning-web-source__actions">
        <SecondaryButton onClick={onCancel}>Cancel</SecondaryButton>
        <button type="button" onClick={add} className="learning-web-source__add">
          <Plus aria-hidden className="size-3" strokeWidth={1.75} />
          Add source
        </button>
      </div>
    </div>
  );
}
