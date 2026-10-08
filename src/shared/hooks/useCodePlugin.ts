import { useSyncExternalStore } from "react";
import type { CodeHighlighterPlugin } from "@streamdown/code";
import {
  loadThemeId,
  THEME_CHANGE_EVENT,
} from "../../features/settings/model/appearance";
import { buildCodeTheme, findTheme } from "../../features/settings/model/themes";
import {
  boundedCode,
  DEFAULT_CODE_THEMES,
  themedCodePlugin,
} from "../lib/markdown/codeHighlightPlugin";

function subscribe(onChange: () => void) {
  window.addEventListener(THEME_CHANGE_EVENT, onChange);
  return () => window.removeEventListener(THEME_CHANGE_EVENT, onChange);
}

/**
 * Only the half of the pair that matches the theme's mode is ever shown, so the
 * other keeps the default GitHub colors.
 */
function snapshot(): CodeHighlighterPlugin {
  const theme = findTheme(loadThemeId());
  if (!theme) return boundedCode;
  const [light, dark] = DEFAULT_CODE_THEMES;
  const colors = buildCodeTheme(theme);
  return themedCodePlugin(
    theme.id,
    theme.mode === "dark" ? [light, colors] : [colors, dark],
  );
}

/** The code highlighter for the theme in effect, which changes when the theme does. */
export function useCodePlugin(): CodeHighlighterPlugin {
  return useSyncExternalStore(subscribe, snapshot, () => boundedCode);
}
