import {
  ANCHOR_AFTER_MS, DAY_MS, GHOST_LIMIT, LADDER_DAYS, REVISIT_LIMIT,
  type ConceptData, type MapNode, type MapView, type RecallVerdict,
} from "./learnMap";

const lastStep = LADDER_DAYS.length - 1;
const waitFor = (step: number) => LADDER_DAYS[Math.min(Math.max(step, 0), lastStep)] * DAY_MS;

/** A concept the learner has just explained: the first revisit comes tomorrow. */
export function scheduleFirst(now: number): Pick<ConceptData, "step" | "dueAt"> {
  return { step: 0, dueAt: now + waitFor(0) };
}

/**
 * A concept after a revisit. A recall that holds moves along the ladder, and
 * anchors the node once the wait it survived was a week or more. A shaky one
 * waits the same interval again. A lost one goes back to unexplored and keeps
 * its history.
 */
export function afterRecall(data: ConceptData, verdict: RecallVerdict, now: number, sessionId: string): ConceptData {
  const from = { state: data.state, ...(data.step === undefined ? {} : { step: data.step }) };
  const history = [...data.history, { at: now, type: "recall" as const, verdict, sessionId, from }];
  if (verdict === "gone") {
    const { step: _step, dueAt: _dueAt, ...rest } = data;
    return { ...rest, state: "ghost", history };
  }
  const waited = now - (data.history[data.history.length - 1]?.at ?? now);
  const step = verdict === "solid" ? Math.min((data.step ?? 0) + 1, lastStep) : data.step ?? 0;
  return {
    ...data, history, step, dueAt: now + waitFor(step),
    state: verdict === "solid" && waited >= ANCHOR_AFTER_MS ? "anchored" : data.state === "ghost" ? "solid" : data.state,
  };
}

/**
 * The few nodes to revisit at the start of a sitting. Judgments whose date has
 * come go first. With a large backlog the most connected nodes are chosen, so
 * the learner rebuilds the frame instead of clearing a queue.
 */
export function pickRevisits(nodes: readonly MapNode[], limit = REVISIT_LIMIT): MapNode[] {
  const due = nodes.filter((node) => node.due);
  const backlog = due.length > GHOST_LIMIT;
  return [...due].sort((a, b) =>
    Number(b.kind === "judgment") - Number(a.kind === "judgment") ||
    (backlog ? b.links - a.links : 0) ||
    (a.dueAt ?? 0) - (b.dueAt ?? 0)).slice(0, limit);
}

export type MapStats = {
  concepts: { ghost: number; solid: number; anchored: number };
  judgments: { open: number; closed: number };
  /** Revisits that came a week or more after the previous evidence, and how many held. */
  delayedRecall: { total: number; held: number };
  /** Sessions that left evidence in each of the last four weeks, oldest first. */
  weeklySessions: [number, number, number, number];
};

/** The numbers that say whether learning lasts. Time spent and streaks are deliberately absent. */
export function mapStats(view: MapView, now: number): MapStats {
  const stats: MapStats = {
    concepts: { ghost: 0, solid: 0, anchored: 0 }, judgments: { open: 0, closed: 0 },
    delayedRecall: { total: 0, held: 0 }, weeklySessions: [0, 0, 0, 0],
  };
  const weeks = [new Set<string>(), new Set<string>(), new Set<string>(), new Set<string>()];
  for (const node of view.nodes) {
    if (node.kind === "concept") stats.concepts[node.state as ConceptData["state"]] += 1;
    else stats.judgments[node.state as "open" | "closed"] += 1;
    node.history.forEach((event, index) => {
      const age = Math.floor((now - event.at) / (7 * DAY_MS));
      if (age >= 0 && age < 4) weeks[3 - age].add(event.sessionId);
      if (event.type !== "recall" || index === 0 || event.at - node.history[index - 1].at < ANCHOR_AFTER_MS) return;
      stats.delayedRecall.total += 1;
      if (event.verdict === "solid") stats.delayedRecall.held += 1;
    });
  }
  stats.weeklySessions = weeks.map((sessions) => sessions.size) as MapStats["weeklySessions"];
  return stats;
}
