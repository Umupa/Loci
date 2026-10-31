import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM script without type declarations
import { notes, release, unreleased } from "./changelog.mjs";

const FIRST = `# Changelog

Intro.

## [Unreleased]

### Added

- A thing.

[Unreleased]: https://github.com/Umupa/Loci/commits/main
`;

describe("changelog", () => {
  it("cuts the first release from Unreleased", () => {
    const next = release(FIRST, "0.1.0", "2026-11-01");
    expect(next).toBe(`# Changelog

Intro.

## [Unreleased]

## [0.1.0] - 2026-11-01

### Added

- A thing.

[Unreleased]: https://github.com/Umupa/Loci/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Umupa/Loci/releases/tag/v0.1.0
`);
    expect(unreleased(next)).toBe("");
    expect(notes(next, "0.1.0")).toBe("### Added\n\n- A thing.");
  });

  it("compares a later release with the one before", () => {
    const first = release(FIRST, "0.1.0", "2026-11-01");
    const edited = first.replace("## [Unreleased]\n", "## [Unreleased]\n\n### Fixed\n\n- B.\n");
    const second = release(edited, "0.2.0", "2026-11-08");
    expect(notes(second, "0.2.0")).toBe("### Fixed\n\n- B.");
    expect(notes(second, "0.1.0")).toBe("### Added\n\n- A thing.");
    expect(second).toContain("[Unreleased]: https://github.com/Umupa/Loci/compare/v0.2.0...HEAD\n[0.2.0]: https://github.com/Umupa/Loci/compare/v0.1.0...v0.2.0\n[0.1.0]: https://github.com/Umupa/Loci/releases/tag/v0.1.0");
  });

  it("refuses an empty or repeated release", () => {
    const first = release(FIRST, "0.1.0", "2026-11-01");
    expect(() => release(first, "0.2.0", "2026-11-08")).toThrow(/lists nothing/);
    expect(() => release(FIRST.replace("- A thing.", "- B."), "0.1.0", "x")).not.toThrow();
    expect(() => release(first.replace("## [Unreleased]\n", "## [Unreleased]\n\n- C.\n"), "0.1.0", "x")).toThrow(/already/);
    expect(() => notes(FIRST, "9.9.9")).toThrow(/no "## \[9.9.9\]"/);
  });
});
