import { pathKey } from "../../../shared/lib/paths";
import type { HarnessId } from "../../sessions/model/session";

const ACCOUNTS_KEY = "loci.providerAccounts.v1";
const SELECTIONS_KEY = "loci.providerAccountSelections.v1";

export const DEFAULT_PROVIDER_ACCOUNT_ID = "default";
const DEFAULT_PROVIDER_ACCOUNT_LABEL = "Default account";

/** Legacy sessions predate persisted account ids and belong to the default profile. */
export function sameProviderAccountId(
  left: string | undefined,
  right: string | undefined,
): boolean {
  return (
    (left ?? DEFAULT_PROVIDER_ACCOUNT_ID) ===
    (right ?? DEFAULT_PROVIDER_ACCOUNT_ID)
  );
}

/** Providers whose CLIs support isolated, locally named account profiles. */
const PROVIDER_ACCOUNT_PROVIDERS = [
  "claude",
  "codex",
] as const satisfies readonly HarnessId[];

export type ProviderAccountProvider =
  (typeof PROVIDER_ACCOUNT_PROVIDERS)[number];

export function supportsProviderAccounts(
  provider: HarnessId,
): provider is ProviderAccountProvider {
  return PROVIDER_ACCOUNT_PROVIDERS.some((candidate) => candidate === provider);
}

type ProviderAccount = {
  id: string;
  provider: ProviderAccountProvider;
  label: string;
  isDefault?: boolean;
};

type StoredAccounts = Partial<
  Record<ProviderAccountProvider, ProviderAccount[]>
>;
type StoredSelections = Record<
  string,
  Partial<Record<ProviderAccountProvider, string>>
>;

function providerAccounts(
  provider: ProviderAccountProvider,
): ProviderAccount[] {
  const stored = readRecord<StoredAccounts>(ACCOUNTS_KEY);
  const seen = new Set<string>([DEFAULT_PROVIDER_ACCOUNT_ID]);
  const accounts = Array.isArray(stored[provider]) ? stored[provider] : [];
  let defaultLabel = DEFAULT_PROVIDER_ACCOUNT_LABEL;
  let foundDefault = false;
  const profiles = accounts.flatMap((account) => {
    const id = validAccountId(account?.id) ? account.id : "";
    const label = cleanLabel(account?.label);
    if (id === DEFAULT_PROVIDER_ACCOUNT_ID) {
      if (label && !foundDefault) {
        defaultLabel = label;
        foundDefault = true;
      }
      return [];
    }
    if (!id || !label || seen.has(id)) {
      return [];
    }
    seen.add(id);
    return [{ id, provider, label }];
  });
  return [
    {
      id: DEFAULT_PROVIDER_ACCOUNT_ID,
      provider,
      label: defaultLabel,
      isDefault: true,
    },
    ...profiles,
  ];
}

export function providerAccountExists(
  provider: ProviderAccountProvider,
  accountId: string | undefined,
): boolean {
  return providerAccounts(provider).some((account) => account.id === accountId);
}

export function selectedProviderAccountId(
  provider: ProviderAccountProvider,
  project: string | undefined,
): string {
  const selections = readRecord<StoredSelections>(SELECTIONS_KEY);
  const id = selections[selectionKey(project)]?.[provider];
  return providerAccounts(provider).some((account) => account.id === id)
    ? id!
    : DEFAULT_PROVIDER_ACCOUNT_ID;
}

function selectionKey(project: string | undefined): string {
  return pathKey(project?.trim() || "~");
}

function cleanLabel(value: unknown): string {
  return typeof value === "string"
    ? value.replace(/\s+/g, " ").trim().slice(0, 48)
    : "";
}

function validAccountId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 80 &&
    /^[A-Za-z0-9_-]+$/.test(value)
  );
}

function readRecord<T>(key: string): T {
  const value = readJson<unknown>(key, {});
  return isRecord(value) ? (value as T) : ({} as T);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readJson<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}
