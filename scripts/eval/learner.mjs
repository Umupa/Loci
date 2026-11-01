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
  ["goal", /\b(goal|target|aim|outcome|end state|walk away with|be able to do|when (we're|we are|this is) done|why (do|are) you|what (do|are) you (want|trying|hoping)|use case|purpose|problem (are you|you're) (solving|facing)|end result|what will you (do|build))\b|目标|为什么|用途|场景|要解决|落地/i],
  ["scope", /\b(scope|breadth|cover|which (parts|areas|topics)|focus on|skip|exclude|end[- ]to[- ]end|overview)\b|范围|广度|覆盖|跳过|排除|聚焦|全景/i],
  ["depth", /\b(depth|deep|how far|source code|internals|level of detail|vertical)\b|深度|纵深|源码|击穿|细节/i],
  ["level", /\b(level|familiar|experience|already know|comfortable|beginner|new to|have you (used|read|worked|seen))\b|熟悉|经验|掌握|了解|基础|盲区|困惑/i],
  ["background", /\b(background|stack|language runtime|kernel|anchor|strongest|day job|role)\b|技术栈|锚点|背景|熟练|运行时/i],
];

/**
 * Questions asked as a `loci-question` block (Loci's clickable question
 * card): each with its question and header. Unparseable blocks are skipped.
 */
export function structuredQuestions(reply) {
  const found = [];
  for (const match of String(reply ?? "").matchAll(/(`{3,})loci-question[^\n]*\n([\s\S]*?)\1/g)) {
    try {
      const body = JSON.parse(match[2]);
      for (const question of body.questions ?? []) if (question?.question) found.push({ question: String(question.question), header: String(question.header ?? ""), options: (question.options ?? []).map((option) => String(option.label ?? "")) });
    } catch { /* not JSON: the card would not render either */ }
  }
  return found;
}

/** Prose without code blocks (question cards included). */
const prose = (reply) => String(reply ?? "").replace(/(`{3,})[^\n]*\n[\s\S]*?\1/g, " ");

/** The questions of a reply: its question cards, then prose sentences ending in a question mark. */
export function questionsIn(reply) {
  const cards = structuredQuestions(reply).map((entry) => [entry.header, entry.question].filter(Boolean).join(": "));
  const sentences = prose(reply).split(/(?<=[?？])|\n+/).map((part) => part.trim()).filter(Boolean);
  return [...cards, ...sentences.filter((sentence) => /[?？]\s*$/.test(sentence))];
}

/** Whether the mentor ends its reply waiting for an answer: a question card, or a question near the end. */
export function asksSomething(reply) {
  if (structuredQuestions(reply).length) return true;
  const text = prose(reply).trim();
  if (!text) return false;
  return /[?？]/.test(text.slice(-700));
}

/** How many questions a reply puts to the learner. */
export function questionCount(reply) {
  return structuredQuestions(reply).length + (prose(reply).match(/[?？]/g) ?? []).length;
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
