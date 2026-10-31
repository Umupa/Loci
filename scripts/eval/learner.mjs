// The scripted learner: short answers to what a mentor typically asks, picked
// by keyword, and "Your call — go ahead." for anything the scenario does not
// cover. Deterministic, so two runs of a scenario differ only by the mentor.

export const FALLBACK = "Your call — go ahead.";
export const NUDGE = "Go ahead and prepare the reading.";
/** An answer is given at most this many times; after that the learner defers. */
const REPEAT_MAX = 2;

/**
 * Topics in priority order: the first that matches a question wins its place.
 * Each pattern covers English and Chinese, since the Mentor template is written in Chinese.
 */
export const TOPICS = [
  ["confirm", /\b(shall i|should i (start|begin|go|proceed)|ready (for me )?to|sound good|does (this|that|the) (plan|route|outline|look)|ok(ay)? (with|to)|confirm|green light|can i (start|begin|go))\b|开始吗|可以开始|确认|是否同意|同意吗|行吗|可以吗/i],
  ["time", /\b(how (much|many) (time|hours)|hours? (a|per) (day|week)|time budget|deadline|by when|how long)\b|多少时间|每天|每周|时间/i],
  ["language", /\b(english|chinese|mandarin|which language (do you|should i) (read|prefer)|translat)/i, /中文|英文|英语|语种|翻译/],
  ["goal", /\b(goal|why (do|are) you|what (do|are) you (want|trying|hoping)|use case|purpose|problem (are you|you're) (solving|facing)|end result|what will you (do|build))\b|目标|为什么|用途|场景|要解决|落地/i],
  ["scope", /\b(scope|breadth|cover|which (parts|areas|topics)|focus on|skip|exclude|end[- ]to[- ]end|overview)\b|范围|广度|覆盖|跳过|排除|聚焦|全景/i],
  ["depth", /\b(depth|deep|how far|source code|internals|level of detail|vertical)\b|深度|纵深|源码|击穿|细节/i],
  ["level", /\b(level|familiar|experience|already know|comfortable|beginner|new to|have you (used|read|worked|seen))\b|熟悉|经验|掌握|了解|基础|盲区|困惑/i],
  ["background", /\b(background|stack|language runtime|kernel|anchor|strongest|day job|role)\b|技术栈|锚点|背景|熟练|运行时/i],
];

/** The sentences of a reply that ask something, or the whole reply when none does. */
export function questionsIn(reply) {
  const text = String(reply ?? "").replace(/```[\s\S]*?```/g, " ");
  const sentences = text.split(/(?<=[?？])|\n+/).map((part) => part.trim()).filter(Boolean);
  return sentences.filter((sentence) => /[?？]\s*$/.test(sentence));
}

/** Whether the mentor ends its reply waiting for an answer. */
export function asksSomething(reply) {
  const text = String(reply ?? "").replace(/```[\s\S]*?```/g, " ").trim();
  if (!text) return false;
  const tail = text.slice(-700);
  return /[?？]/.test(tail);
}

/** The topics a set of questions touches, in priority order. */
export function topicsOf(questions) {
  const text = questions.join("\n");
  return TOPICS.filter(([, ...patterns]) => patterns.some((pattern) => pattern.test(text))).map(([name]) => name);
}

/**
 * The learner's next message.
 * @param {string} reply the mentor's last reply
 * @param {{answers: Record<string, string>}} learner the scenario's learner
 * @param {{used: Record<string, number>, hasCourse: boolean, nudged: boolean}} state updated in place
 * @returns {{text: string, why: string, topics: string[], done?: boolean, nudge?: boolean}}
 */
export function nextMessage(reply, learner, state) {
  state.used ??= {};
  if (!asksSomething(reply)) {
    if (state.hasCourse) return { text: "", why: "no question and a course exists", topics: [], done: true };
    if (state.nudged) return { text: "", why: "no question, no course, already nudged once", topics: [], done: true };
    state.nudged = true;
    return { text: NUDGE, why: "no question and no course yet: one nudge", topics: [], nudge: true };
  }
  const questions = questionsIn(reply);
  const topics = topicsOf(questions.length ? questions : [reply]);
  const parts = [];
  const answered = [];
  for (const topic of topics) {
    const answer = learner.answers?.[topic];
    if (!answer || (state.used[topic] ?? 0) >= REPEAT_MAX) continue;
    parts.push(answer);
    answered.push(topic);
    state.used[topic] = (state.used[topic] ?? 0) + 1;
    // A short learner: at most three facts per message.
    if (parts.length === 3) break;
  }
  if (!parts.length) return { text: FALLBACK, why: topics.length ? `already answered ${topics.join(", ")}` : "question not covered by the scenario", topics };
  return { text: parts.join(" "), why: `answered ${answered.join(", ")}`, topics: answered };
}
