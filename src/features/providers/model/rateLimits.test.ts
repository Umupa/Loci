import { describe,expect,it } from "vitest";
import {
exhaustedWindowResetAt,
formatResetDuration,
parseCodexRateLimits,
parseResetTimestamp
} from "./rateLimits";

describe("formatResetDuration", () => {
  it("floors to whole units", () => {
    expect(formatResetDuration(47 * 60_000)).toBe("47m");
    expect(formatResetDuration(3 * 3_600_000 + 54 * 60_000)).toBe("3h 54m");
    expect(formatResetDuration(3 * 3_600_000)).toBe("3h");
    expect(formatResetDuration(6 * 86_400_000 + 7 * 3_600_000)).toBe("6d 7h");
    expect(formatResetDuration(2 * 86_400_000)).toBe("2d");
  });

  it("reports an expired window as now", () => {
    expect(formatResetDuration(0)).toBe("now");
    expect(formatResetDuration(-1_000)).toBe("now");
  });
});

describe("exhaustedWindowResetAt", () => {
  it("returns the latest reset among spent windows", () => {
    const limits = {
      session: { usedPercent: 100, windowMinutes: 300, resetsAt: 2_000 },
      weekly: { usedPercent: 100, windowMinutes: 10_080, resetsAt: 9_000 },
      monthly: null,
    };
    expect(exhaustedWindowResetAt(limits)).toBe(9_000);
  });

  it("ignores windows with room left", () => {
    const limits = {
      session: { usedPercent: 100, windowMinutes: 300, resetsAt: 2_000 },
      weekly: { usedPercent: 40, windowMinutes: 10_080, resetsAt: 9_000 },
      monthly: null,
    };
    expect(exhaustedWindowResetAt(limits)).toBe(2_000);
    expect(
      exhaustedWindowResetAt({ session: null, weekly: null, monthly: null }),
    ).toBeNull();
  });
});

describe("parseResetTimestamp", () => {
  it("treats small numbers as unix seconds", () => {
    expect(parseResetTimestamp(1_738_425_600)).toBe(1_738_425_600_000);
  });

  it("keeps millisecond epochs", () => {
    expect(parseResetTimestamp(1_738_425_600_000)).toBe(1_738_425_600_000);
  });

  it("parses ISO strings", () => {
    expect(parseResetTimestamp("2026-08-27T12:00:00.000Z")).toBe(
      Date.parse("2026-08-27T12:00:00.000Z"),
    );
  });
});

describe("parseCodexRateLimits", () => {
  it("classifies primary/secondary by duration", () => {
    const limits = parseCodexRateLimits({
      rateLimits: {
        primary: {
          usedPercent: 52,
          windowDurationMins: 300,
          resetsAt: 1_738_425_600,
        },
        secondary: {
          used_percent: 37,
          window_duration_mins: 10_080,
          resets_at: 1_738_900_000,
        },
      },
    });
    expect(limits.session).toEqual({
      usedPercent: 52,
      windowMinutes: 300,
      resetsAt: 1_738_425_600_000,
    });
    expect(limits.weekly).toEqual({
      usedPercent: 37,
      windowMinutes: 10_080,
      resetsAt: 1_738_900_000_000,
    });
  });

  it("maps a free plan's lone 30-day primary window to monthly", () => {
    const limits = parseCodexRateLimits({
      rateLimits: {
        primary: {
          usedPercent: 4,
          windowDurationMins: 43_200,
          resetsAt: 1_792_550_273,
        },
        secondary: null,
      },
    });
    expect(limits.session).toBeNull();
    expect(limits.weekly).toBeNull();
    expect(limits.monthly).toEqual({
      usedPercent: 4,
      windowMinutes: 43_200,
      resetsAt: 1_792_550_273_000,
    });
  });

  it("falls back to primary=session when durations are unknown", () => {
    const limits = parseCodexRateLimits({
      primary: { usedPercent: 10, resetsAt: 100 },
      secondary: { usedPercent: 20, resetsAt: 200 },
    });
    expect(limits.session?.usedPercent).toBe(10);
    expect(limits.weekly?.usedPercent).toBe(20);
  });
});
