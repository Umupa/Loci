import type { ReactNode } from "react";
import { basename } from "../../../platform/tauri/fs";
import { looksLikeProject } from "../../projects/model/recents";

import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";


type Props = {
  cwd: string;
  composer?: ReactNode;
  /** Stands in for the question above the composer, such as an agent's introduction. */
  intro?: ReactNode;
};

export function EmptySession({ cwd, composer, intro }: Props) {
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();

  const project = looksLikeProject(cwd) ? basename(cwd) : null;
  const title = project
    ? `What should we work on in ${project}?`
    : "What should we work on?";

  return (
    <div
      ref={lockOverscroll}
      className="relative flex h-full min-h-0 overflow-y-auto overscroll-none"
    >

      {composer || intro ? (
        // Same box as the docked composer (max-w-4xl, p-1.5), so the input
        // keeps its width when the first message docks it.
        <div className="pointer-events-none relative z-10 mx-auto flex w-full max-w-4xl flex-1 flex-col justify-center px-1.5 py-12">
          <div className={`pointer-events-auto px-2.5${composer ? " mb-4" : ""}`}>
            {intro ?? (
              <h1
                className="truncate text-lg text-content"
                title={project ? cwd : undefined}
              >
                {title}
              </h1>
            )}
          </div>

          {composer ? <div className="pointer-events-auto w-full">{composer}</div> : null}
        </div>
      ) : null}
    </div>
  );
}
