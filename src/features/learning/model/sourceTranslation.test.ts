import { describe, expect, it } from "vitest";
import {
  looksForeign,
  mergeTranslation,
  parseTranslation,
  sectionUnits,
  serializeTranslation,
  shownUnits,
  sourceUnits,
  TranslationShapeError,
} from "./sourceTranslation";

const SOURCE = `Intro text.

# Pod lifecycle

Pods are ephemeral.

## Pod phase

The phase is a summary.

\`\`\`yaml
status:
  phase: Pending
\`\`\`

## Container states

Waiting, Running, Terminated.

# Next
Done.
`;

describe("source translation", () => {
  it("cuts a source at every heading, with the opening text first", () => {
    const units = sourceUnits(SOURCE);
    expect(units.map((unit) => [unit.depth, unit.heading])).toEqual([[0, ""], [1, "Pod lifecycle"], [2, "Pod phase"], [2, "Container states"], [1, "Next"]]);
    expect(units[2].code).toEqual(["status:\n  phase: Pending"]);
    expect(sectionUnits(units, "Pod lifecycle").map((unit) => unit.heading)).toEqual(["Pod lifecycle", "Pod phase", "Container states"]);
    expect(sectionUnits(units, "pod phase").map((unit) => unit.heading)).toEqual(["Pod phase"]);
    expect(sectionUnits(units, "Nowhere")).toHaveLength(5);
  });

  it("keeps a translation that has the original's shape, and reads it back", () => {
    const units = sectionUnits(sourceUnits(SOURCE), "Pod phase");
    const kept = mergeTranslation(units, "## Pod 阶段\n\n阶段是一个概要。\n\n```yaml\nstatus:\n  phase: Pending\n```\n", { language: "zh-CN", units: [] });
    const round = parseTranslation("zh-CN", serializeTranslation("k8s-pod", kept));
    expect(round).toEqual(kept);
    const shown = shownUnits(sourceUnits(SOURCE), round);
    expect(shown[2].translation).toContain("阶段是一个概要");
    expect(shown[2].stale).toBeUndefined();
    expect(shown[3].translation).toBeUndefined();
  });

  it("refuses a translation whose headings or code differ from the original", () => {
    const units = sectionUnits(sourceUnits(SOURCE), "Pod lifecycle");
    expect(() => mergeTranslation(units, "# Pod 生命周期\n\nPod 是短暂的。\n", { language: "zh-CN", units: [] })).toThrow(TranslationShapeError);
    const phase = sectionUnits(sourceUnits(SOURCE), "Pod phase");
    expect(() => mergeTranslation(phase, "## Pod 阶段\n\n```yaml\nstatus: 已翻译\n```\n", { language: "zh-CN", units: [] })).toThrow(/Code must stay/);
  });

  it("marks a translation made from an earlier version of its section as out of date, until it is redone", () => {
    const phase = sectionUnits(sourceUnits(SOURCE), "Container states");
    const kept = mergeTranslation(phase, "## 容器状态\n\n等待、运行、终止。\n", { language: "zh-CN", units: [] });
    const changed = sourceUnits(SOURCE.replace("Waiting, Running, Terminated.", "Waiting, Running, Terminated, and more."));
    const shown = shownUnits(changed, kept);
    expect(shown[3]).toMatchObject({ translation: "## 容器状态\n\n等待、运行、终止。", stale: true });
    const redone = mergeTranslation(sectionUnits(changed, "Container states"), "## 容器状态\n\n等待、运行、终止，以及更多。\n", kept);
    expect(redone.units).toHaveLength(1);
    expect(shownUnits(changed, redone)[3].stale).toBeUndefined();
  });

  it("tells a source in another language from one already in the learner's", () => {
    expect(looksForeign(SOURCE.repeat(3), "zh-CN")).toBe(true);
    expect(looksForeign("Pod 是 Kubernetes 中最小的可部署单元，它的阶段（phase）是一个概要。".repeat(4), "zh-CN")).toBe(false);
    expect(looksForeign("短".repeat(10), "en")).toBe(false);
  });
});
