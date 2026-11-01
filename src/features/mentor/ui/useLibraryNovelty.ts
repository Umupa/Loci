import { useCallback, useEffect, useRef, useState } from "react";
import {
  emptyNovelty,
  noveltyIsNew,
  noveltyItems,
  noveltyOpened,
  noveltyTurn,
  type NoveltyState,
} from "../model/libraryNovelty";

/**
 * Tracks the library items saved by the turn that is running now. The listing
 * arrives through the same change events the library already listens to, so a
 * saved source shows up and gets its mark without waiting for the turn to end.
 */
export function useLibraryNovelty(
  busy: boolean,
  keys: readonly string[] | undefined,
) {
  const [state, setState] = useState<NoveltyState>(emptyNovelty);
  const keysRef = useRef(keys);
  keysRef.current = keys;
  const signature = keys?.join("\n");

  useEffect(() => {
    setState((current) => noveltyTurn(current, busy, keysRef.current));
  }, [busy]);

  useEffect(() => {
    setState((current) => noveltyItems(current, keysRef.current));
  }, [signature]);

  const markOpened = useCallback((key: string) => {
    setState((current) => noveltyOpened(current, key));
  }, []);

  const isNew = useCallback(
    (key: string) => noveltyIsNew(state, key),
    [state],
  );

  return { isNew, markOpened };
}
