// @vitest-environment happy-dom
import { beforeEach,describe,expect,it } from "vitest";
import {
DEFAULT_PROVIDER_ACCOUNT_ID,
providerAccountExists,
sameProviderAccountId,
selectedProviderAccountId,
supportsProviderAccounts,
} from "./providerAccounts";

beforeEach(() => {
  localStorage.clear();
});

describe("provider account resolution", () => {
  it("treats a missing account id as the default profile", () => {
    expect(sameProviderAccountId(undefined, DEFAULT_PROVIDER_ACCOUNT_ID)).toBe(
      true,
    );
    expect(sameProviderAccountId("work", DEFAULT_PROVIDER_ACCOUNT_ID)).toBe(
      false,
    );
    expect(supportsProviderAccounts("claude")).toBe(true);
    expect(supportsProviderAccounts("codex")).toBe(true);
    expect(supportsProviderAccounts("cursor")).toBe(false);
  });

  it("resolves a stored named profile and rejects unknown ids", () => {
    localStorage.setItem(
      "loci.providerAccounts.v1",
      JSON.stringify({ codex: [{ id: "account-work", label: "Work" }] }),
    );

    expect(providerAccountExists("codex", "account-work")).toBe(true);
    expect(providerAccountExists("codex", "account-missing")).toBe(false);
    expect(providerAccountExists("claude", "account-work")).toBe(false);
  });

  it("falls back to the default account for malformed stored profiles", () => {
    localStorage.setItem(
      "loci.providerAccounts.v1",
      JSON.stringify({ claude: { id: "not-an-array" } }),
    );

    expect(providerAccountExists("claude", DEFAULT_PROVIDER_ACCOUNT_ID)).toBe(
      true,
    );
    expect(providerAccountExists("claude", "account-work")).toBe(false);
  });

  it("falls back when the stored root is not a record", () => {
    for (const malformed of ["null", "[]", "42"]) {
      localStorage.setItem("loci.providerAccounts.v1", malformed);
      expect(providerAccountExists("claude", DEFAULT_PROVIDER_ACCOUNT_ID)).toBe(
        true,
      );
    }

    localStorage.setItem("loci.providerAccountSelections.v1", "null");
    expect(selectedProviderAccountId("claude", "/repo")).toBe(
      DEFAULT_PROVIDER_ACCOUNT_ID,
    );
  });

  it("remembers a selection per project and ignores unknown ids", () => {
    localStorage.setItem(
      "loci.providerAccounts.v1",
      JSON.stringify({ codex: [{ id: "account-work", label: "Work" }] }),
    );
    localStorage.setItem(
      "loci.providerAccountSelections.v1",
      JSON.stringify({ "/repo/one": { codex: "account-work" } }),
    );

    expect(selectedProviderAccountId("codex", "/repo/one")).toBe("account-work");
    expect(selectedProviderAccountId("codex", "/repo/two")).toBe(
      DEFAULT_PROVIDER_ACCOUNT_ID,
    );
    expect(selectedProviderAccountId("codex", undefined)).toBe(
      DEFAULT_PROVIDER_ACCOUNT_ID,
    );
  });

  it("ignores a selection that no longer names a stored profile", () => {
    localStorage.setItem(
      "loci.providerAccountSelections.v1",
      JSON.stringify({ "/repo/one": { codex: "account-missing" } }),
    );

    expect(selectedProviderAccountId("codex", "/repo/one")).toBe(
      DEFAULT_PROVIDER_ACCOUNT_ID,
    );
  });
});
