import { describe, expect, it } from "vitest";
import { shouldCelebrateTurn } from "./turnCelebration";
describe("turn celebrations", () => {
    it("celebrates only a turn sent moments ago", () => {
        const now = 1000000;
        expect(shouldCelebrateTurn("fresh", now - 500, now)).toBe(true);
        expect(shouldCelebrateTurn("old", now - 60000, now)).toBe(false);
        expect(shouldCelebrateTurn("unknown", undefined, now)).toBe(false);
    });
});
