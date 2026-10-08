import { createContext, useContext, useMemo, type ReactNode } from "react";
import { translate, useLocale, type Locale } from "./locale";

// Shared controls use English unless rendered within Settings, including portals.
const UiLocale = createContext<Locale>("en");

export function SettingsLanguage({ children }: { children: ReactNode }) {
  const locale = useLocale();
  return <UiLocale.Provider value={locale}>
    <div lang={locale} className="contents">{children}</div>
  </UiLocale.Provider>;
}

export function useUiText() {
  const locale = useContext(UiLocale);
  return useMemo(() => ({
    locale,
    t: (source: string, ...values: (string | number)[]) => translate(locale, source, ...values),
  }), [locale]);
}
