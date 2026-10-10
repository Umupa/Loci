import { useCallback, useEffect, useRef, useState } from "react";
import { listLearningWidgets, subscribeLearningChanges } from "../model/learningStore";
import type { StoredWidget, WidgetOwner } from "../model/types";

/** Saved widgets for one owner, retained while a refreshed list is loading. */
export function useSavedWidgets(owner: WidgetOwner) {
  const { kind, id } = owner;
  const [widgets, setWidgets] = useState<StoredWidget[]>();
  const [error, setError] = useState<string>();
  const mounted = useRef(false);
  const request = useRef(0);

  const reload = useCallback(() => {
    if (!mounted.current) return;
    const sequence = ++request.current;
    setError(undefined);
    void listLearningWidgets({ kind, id }, true).then(
      (found) => {
        if (!mounted.current || sequence !== request.current) return;
        setWidgets(found);
        setError(undefined);
      },
      (cause: unknown) => {
        if (!mounted.current || sequence !== request.current) return;
        setError(cause instanceof Error ? cause.message : String(cause));
      },
    );
  }, [kind, id]);

  useEffect(() => {
    mounted.current = true;
    setWidgets(undefined);
    setError(undefined);
    reload();
    const stop = subscribeLearningChanges(reload);
    return () => {
      mounted.current = false;
      request.current += 1;
      stop();
    };
  }, [reload]);

  return { widgets, error, reload };
}
