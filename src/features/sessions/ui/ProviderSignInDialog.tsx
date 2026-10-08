import { t, useLocale } from "../../../shared/i18n/locale";
import { useCallback,useEffect,useState } from "react";
import { loginHarness } from "../../../integrations/harness/core/auth";
import { Modal } from "../../../shared/ui/Modal";
import { HARNESS_TITLE,type HarnessId } from "../model/session";
import {
ProviderSignInPanel,
type ProviderSignInState,
} from "./ProviderSignInPanel";

type Props = {
  harness: HarnessId;
  onClose: () => void;
};

export function ProviderSignInDialog({ harness, onClose }: Props) {
  useLocale();
  const [state, setState] = useState<ProviderSignInState>("idle");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setState("idle");
    setError(null);
  }, [harness]);

  const signIn = useCallback(() => {
    setState("running");
    setError(null);
    void loginHarness(harness).then(
      () => setState("complete"),
      (reason: unknown) => {
        setState("error");
        setError(
          reason instanceof Error
            ? reason.message
            : t("Could not sign in to {0}.", HARNESS_TITLE[harness]),
        );
      },
    );
  }, [harness]);

  return (
    <Modal
      onClose={onClose}
      title={t("Authentication required")}
      description={t("Sign in to continue using {0}.", HARNESS_TITLE[harness])}
      size="sm"
      minimalHeader
    >
      <ProviderSignInPanel
        harness={harness}
        state={state}
        error={error}
        onSignIn={signIn}
        onComplete={onClose}
        completeActionLabel="Continue"
        autoFocus
      />
    </Modal>
  );
}
