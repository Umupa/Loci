import { expect, it } from "vitest";
import { firstUse } from "./LessonTerms";

it("finds a term's first use as a whole word in Latin letters, anywhere in CJK, by its aliases too", () => {
  expect(firstUse("The kubelet watches; a watch is a stream.", { term: "watch", aliases: ["watches"] })).toEqual([12, 19]);
  expect(firstUse("stopwatch only", { term: "watch" })).toBeNull();
  expect(firstUse("Kubelet 从 PLEG 重建状态", { term: "pleg" })).toEqual([10, 14]);
  expect(firstUse("用水平触发对账", { term: "水平触发" })).toEqual([1, 5]);
  expect(firstUse("a.b and a+b", { term: "a+b" })).toEqual([8, 11]);
});
