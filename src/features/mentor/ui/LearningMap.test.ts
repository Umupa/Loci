import { describe, expect, it } from "vitest";
import { mapLabel, wrapLabel } from "./LearningMap";

describe("map labels", () => {
  it("names a course by its subject, cut to fit", () => {
    expect(mapLabel("sds 深读：一个 C 字符串库", 400)).toBe("sds 深读");
    expect(mapLabel("一二三四五六七八九十", 60)).toMatch(/…$/);
  });

  it("breaks a lesson's name over lines, words whole, CJK anywhere", () => {
    expect(wrapLabel("sdsRemoveFreeSpace", 200, 3, 12.5)).toEqual(["sdsRemoveFreeSpace"]);
    expect(wrapLabel("hello world again", 50, 3, 12.5)).toEqual(["hello", "world", "again"]);
    const cjk = wrapLabel("收缩时为何要特判类型", 60, 3, 12.5);
    expect(cjk.join("")).toBe("收缩时为何要特判类型");
    expect(cjk.length).toBeGreaterThan(1);
  });

  it("ends in an ellipsis when the name runs past the last line", () => {
    const lines = wrapLabel("one two three four five six", 40, 2, 12.5);
    expect(lines).toHaveLength(2);
    expect(lines[1]).toMatch(/…$/);
  });
});
