import type { ReactNode } from "react";

/**
 * Switches off every control inside while `readOnly` (a disabled fieldset),
 * leaving what is shown as it is. Lays nothing out of its own.
 */
export function ReadOnly({ readOnly, children }: { readOnly: boolean; children: ReactNode }) {
  return <fieldset disabled={readOnly} className="contents" data-read-only={readOnly || undefined}>{children}</fieldset>;
}
