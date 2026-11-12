import { expect, it } from "vitest";
import { parseGlossaryInput } from "./glossary";

it("takes terms with a definition, aliases and the lesson that teaches them, and refuses the rest", () => {
  expect(parseGlossaryInput([{ term: " watch ", definition: "A stream of changes.", aliases: ["watches"], course: "k8s", lesson: "watch" }]))
    .toEqual([{ term: "watch", definition: "A stream of changes.", aliases: ["watches"], course: "k8s", lesson: "watch" }]);
  expect(parseGlossaryInput({ term: "PLEG", definition: "Pod lifecycle events." })).toEqual([{ term: "PLEG", definition: "Pod lifecycle events." }]);
  expect(() => parseGlossaryInput([])).toThrow("non-empty");
  expect(() => parseGlossaryInput([{ term: "x" }])).toThrow("definition");
  expect(() => parseGlossaryInput([{ term: "x", definition: "y", lesson: "l" }])).toThrow("course");
  expect(() => parseGlossaryInput([{ term: "x", definition: "y", aliases: "z" }])).toThrow("aliases");
});
