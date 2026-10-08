import { t, useLocale } from "../../../shared/i18n/locale";
import { type ReactNode,useSyncExternalStore } from "react";
import { basename } from "../../../platform/tauri/fs";
import { projectKey } from "../../../shared/lib/paths";
import { looksLikeProject } from "../../projects/model/recents";
import {
loadTabGroupLabels,
resolveTabGroupLabel,
subscribeTabGroupLabels,
} from "../../workspace/model/tabGroups";

import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";


type Props = {
  cwd: string;
  composer?: ReactNode;
};

export function EmptySession({ cwd, composer }: Props) {
  useLocale();
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();

  const getProjectLabel = () =>
    looksLikeProject(cwd)
      ? resolveTabGroupLabel(
          projectKey(cwd),
          loadTabGroupLabels(),
          basename(cwd),
        )
      : null;
  const project = useSyncExternalStore(
    subscribeTabGroupLabels,
    getProjectLabel,
    getProjectLabel,
  );
  const title = project
    ? t("What should we work on in {0}?", project)
    : t("What should we work on?");

  return (
    <div
      ref={lockOverscroll}
      className="relative flex h-full min-h-0 overflow-y-auto overscroll-none"
    >

      {composer ? (
        // Same box as the docked composer (max-w-4xl, p-1.5), so the input
        // keeps its width when the first message docks it.
        <div className="pointer-events-none relative z-10 mx-auto flex w-full max-w-4xl flex-1 flex-col justify-center px-1.5 py-12">
          <div className="pointer-events-auto mb-4 px-2.5">
            <h1
              className="truncate text-lg text-content"
              title={project ? cwd : undefined}
            >
              {title}
            </h1>
          </div>

          <div className="pointer-events-auto w-full">{composer}</div>
        </div>
      ) : null}
    </div>
  );
}
