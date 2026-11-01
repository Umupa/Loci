import { useEffect, useState, type ReactNode } from "react";
import { readTextFile } from "../../../platform/tauri/fs";
import { codePinStatus, readCode, shortCommit, type PinStatus } from "../../../platform/tauri/code";

/** Which text a pinned lesson shows: the file at its commit, or as it is now. */
export type PinView = "pinned" | "current";

/** A pin the clone cannot show at its commit is read from the working tree. */
const FORCED_CURRENT = new Set(["missing-commit", "missing-file", "no-repo"]);

export type PinnedCode = {
  /** The text shown, or why it could not be read; undefined while loading. */
  loaded?: { text?: string; error?: string };
  status?: PinStatus;
  view: PinView;
  setView: (view: PinView) => void;
  /** The lines to show in the text shown (the pin's, or where they are now). */
  lines?: [number, number];
  /** The commit the shown text is at, when it is the pinned version. */
  commit?: string;
};

const message = (cause: unknown) => cause instanceof Error ? cause.message : String(cause);

/**
 * The text of a lesson's file: at the lesson's commit when it is pinned
 * (with how the pin stands against the working tree), else from disk.
 */
export function usePinnedCode(file: string, commit: string | undefined, lines: [number, number] | undefined, enabled: boolean): PinnedCode {
  const key = `${file}\u0000${commit ?? ""}\u0000${lines?.join("-") ?? ""}`;
  const [status, setStatus] = useState<{ key: string; status?: PinStatus }>();
  const [chosen, setChosen] = useState<{ key: string; view: PinView }>();
  const [loaded, setLoaded] = useState<{ key: string; view: PinView; text?: string; error?: string }>();

  useEffect(() => {
    if (!enabled || !commit) return;
    let live = true;
    void codePinStatus(file, commit, lines).then(
      (found) => { if (live) setStatus({ key, status: found }); },
      () => { if (live) setStatus({ key }); });
    return () => { live = false; };
  }, [enabled, file, commit, key]); // eslint-disable-line react-hooks/exhaustive-deps

  const current = status?.key === key ? status.status : undefined;
  const statusKnown = !commit || status?.key === key;
  const forced = !commit || (current && FORCED_CURRENT.has(current.state));
  const view: PinView = forced ? "current" : chosen?.key === key ? chosen.view : "pinned";

  useEffect(() => {
    if (!enabled || !statusKnown) return;
    let live = true;
    const read = view === "pinned" && commit ? readCode(file, commit).then((found) => found.text) : readTextFile(file);
    void read.then(
      (text) => { if (live) setLoaded({ key, view, text }); },
      (cause: unknown) => { if (live) setLoaded({ key, view, error: message(cause) }); });
    return () => { live = false; };
  }, [enabled, statusKnown, view, file, commit, key]);

  const shown = loaded?.key === key && loaded.view === view ? loaded : undefined;
  const moved = view === "current" && current?.state === "changed" && current.currentLines;
  return {
    ...(shown ? { loaded: { ...(shown.text !== undefined ? { text: shown.text } : {}), ...(shown.error ? { error: shown.error } : {}) } } : {}),
    ...(current ? { status: current } : {}),
    view,
    setView: (next) => setChosen({ key, view: next }),
    ...(moved ? { lines: current.currentLines } : lines ? { lines } : {}),
    ...(view === "pinned" && commit ? { commit: current?.commit ?? commit } : {}),
  };
}

/** One line under a pinned lesson's title: how its commit stands, and the other view. */
export function PinNotice({ name, commit, pin }: { name: string; commit: string; pin: PinnedCode }) {
  const status = pin.status;
  if (!status) return null;
  const short = shortCommit(status.commit ?? commit);
  const head = status.head ? shortCommit(status.head) : undefined;
  const button = (label: string, view: PinView) =>
    <button type="button" className="course-button course-button--quiet course-pane__pin-action" onClick={() => pin.setView(view)}>{label}</button>;
  let text: string | null = null;
  let action: ReactNode = null;
  if (status.state === "changed" && pin.view === "pinned") {
    text = `The repository moved past this lesson's commit and ${name} changed since. Showing it as it was at ${short}.`;
    action = button(`Open current${head ? ` (${head})` : ""}`, "current");
  } else if (status.state === "changed") {
    const where = status.currentLines ? `lines ${status.currentLines[0]}–${status.currentLines[1]}` : "the same line numbers";
    text = `Showing ${name} as it is now${head ? ` (HEAD ${head})` : ""}, ${where}${status.exact === false ? "; the lesson's lines were edited, so they may not match" : ""}.`;
    action = button(`Show pinned (${short})`, "pinned");
  } else if (status.state === "moved") {
    text = `HEAD${head ? ` (${head})` : ""} is ${status.ahead ?? "some"} commit${status.ahead === 1 ? "" : "s"} past this lesson's commit; ${name} is unchanged.`;
  } else if (status.state === "missing-commit") {
    text = `Commit ${short} is not in this clone, so ${name} is shown as it is now${head ? ` (HEAD ${head})` : ""}.`;
  } else if (status.state === "missing-file") {
    text = `${name} is not in commit ${short}; it is shown as it is now.`;
  } else if (status.state === "no-repo") {
    text = `${name} is not in a git repository; it is shown as it is now.`;
  }
  if (!text) return null;
  return <p className="course-pane__pin" role="status" data-pin-state={status.state}>{text}{action}</p>;
}
