import { describe, expect, it } from "vitest";
import {
  emptyNovelty,
  noveltyIsNew,
  noveltyItems,
  noveltyKey,
  noveltyOpened,
  noveltyTurn,
} from "./libraryNovelty";

const source = noveltyKey("document", "virtio");
const guide = noveltyKey("document", "guide");
const course = noveltyKey("course", "sandbox");

describe("the new mark on library items", () => {
  it("marks what appears during the turn and clears it when the turn ends", () => {
    let state = emptyNovelty();
    state = noveltyItems(state, [source]);
    state = noveltyTurn(state, true, [source]);
    expect(noveltyIsNew(state, source)).toBe(false);

    state = noveltyItems(state, [source, guide]);
    expect(noveltyIsNew(state, source)).toBe(false);
    expect(noveltyIsNew(state, guide)).toBe(true);

    state = noveltyTurn(state, false, [source, guide]);
    expect(noveltyIsNew(state, guide)).toBe(false);
  });

  it("keeps an opened item quiet for the rest of its turn", () => {
    let state = noveltyTurn(emptyNovelty(), true, []);
    state = noveltyItems(state, [source, guide, course]);
    expect([source, guide, course].filter((key) => noveltyIsNew(state, key))).toHaveLength(3);

    state = noveltyOpened(state, guide);
    expect(noveltyIsNew(state, guide)).toBe(false);
    // A revision of the same id (the mentor rewrites the guide) does not flash it again.
    state = noveltyItems(state, [source, guide, course]);
    expect(noveltyIsNew(state, guide)).toBe(false);
    expect(noveltyIsNew(state, source)).toBe(true);
  });

  it("does not mark an item the learner already has open", () => {
    let state = noveltyTurn(emptyNovelty(), true, []);
    state = noveltyOpened(state, guide);
    state = noveltyItems(state, [guide]);
    expect(noveltyIsNew(state, guide)).toBe(false);
  });

  it("does not mark the library it first sees, even when the window opened mid-turn", () => {
    let state = noveltyTurn(emptyNovelty(), true, undefined);
    state = noveltyItems(state, [source, guide]);
    expect(noveltyIsNew(state, source)).toBe(false);
    expect(noveltyIsNew(state, guide)).toBe(false);

    state = noveltyItems(state, [source, guide, course]);
    expect(noveltyIsNew(state, course)).toBe(true);
  });

  it("starts the next turn from the library as it is then", () => {
    let state = noveltyTurn(emptyNovelty(), true, [source]);
    state = noveltyItems(state, [source, guide]);
    state = noveltyTurn(state, false, [source, guide]);
    state = noveltyTurn(state, true, [source, guide]);
    state = noveltyItems(state, [source, guide]);
    expect(noveltyIsNew(state, guide)).toBe(false);
  });

  it("does not call an unchanged listing a change while idle", () => {
    const state = noveltyItems(emptyNovelty(), [source]);
    expect(noveltyItems(state, [source])).toBe(state);
    expect(noveltyItems(state, [source, guide]).baseline).toEqual([source, guide]);
  });
});
