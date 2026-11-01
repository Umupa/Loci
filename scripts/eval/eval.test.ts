import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM without types
import { FALLBACK, NUDGE, asksSomething, nextMessage, questionCount, topicsOf, questionsIn } from "./learner.mjs";
// @ts-expect-error plain ESM without types
import { checkCitation, checkLessons, checkSandbox, citationsIn, flattenMarkdown, headingsOf, isFirstParty, lessonFileText, orderProblems, quoteResolves, scoreRun, summarySignals } from "./score.mjs";
// @ts-expect-error plain ESM without types
import { DEFAULT_JUDGE_MODEL, RUBRIC, RUBRIC_EXTENSIONS, judgeCommand, judgePrompt, parseVerdict, rubricFor } from "./judge.mjs";
// @ts-expect-error plain ESM without types
import { providerErrorIn } from "./providerErrors.mjs";
// @ts-expect-error plain ESM without types
import { runSetup, summaryMarkdown } from "./report.mjs";
// @ts-expect-error plain ESM without types
import { DEFAULT_PROVIDER, defaultMentorModel } from "./defaults.mjs";
// @ts-expect-error plain ESM without types
import { countFiles, removableMentorFolder, seedRepos } from "./seed.mjs";
// @ts-expect-error plain ESM without types
import { lineCount, pinnedText } from "./pinned.mjs";

const answers = { goal: "Fix SQLITE_BUSY.", level: "Comfortable with Go.", time: "An hour a day.", confirm: "Yes, go ahead.", scope: "WAL only.", depth: "Deep.", language: "English.", background: "Go and Linux." };

describe("the scripted learner", () => {
  it("answers the topics a mentor asks about, briefly, and defers on anything else", () => {
    const state = { used: {}, hasCourse: false, nudged: false };
    const first = nextMessage("Before I start: what is your goal with WAL, and how familiar are you with SQLite's locking?", { answers }, state);
    expect(first.topics).toEqual(["goal", "level"]);
    expect(first.text).toBe("Fix SQLITE_BUSY. Comfortable with Go.");
    expect(nextMessage("Do you prefer tabs or spaces?", { answers }, state).text).toBe(FALLBACK);
  });

  it("hears a goal question however it is phrased", () => {
    expect(topicsOf(["End state: What do you need to be able to do when we're done?"])).toEqual(["goal"]);
    expect(topicsOf(["Goal: When this is done, what do you want to be able to do?"])).toEqual(["goal"]);
  });

  it("reads the Chinese the Mentor template speaks", () => {
    expect(topicsOf(questionsIn("你的真实工程目标是什么？"))).toEqual(["goal"]);
    expect(topicsOf(["方案如上，确认后我就开始收集材料，可以吗？"])).toContain("confirm");
  });

  it("gives an answer at most twice, then defers", () => {
    const state = { used: {}, hasCourse: false, nudged: false };
    for (let i = 0; i < 2; i++) expect(nextMessage("What's your goal?", { answers }, state).text).toBe("Fix SQLITE_BUSY.");
    expect(nextMessage("What's your goal?", { answers }, state).text).toBe(FALLBACK);
  });

  it("stops when the mentor asks nothing and a course exists, and nudges once when none does", () => {
    expect(asksSomething("Here is your course. Start with lesson one.")).toBe(false);
    expect(nextMessage("Saved the course.", { answers }, { used: {}, hasCourse: true, nudged: false }).done).toBe(true);
    const state = { used: {}, hasCourse: false, nudged: false };
    expect(nextMessage("I'll look for material.", { answers }, state)).toMatchObject({ text: NUDGE, nudge: true });
    expect(nextMessage("Still looking.", { answers }, state).done).toBe(true);
  });

  it("reads questions asked as a loci-question card, which is a code fence", () => {
    const card = 'WAL has several paths.\n\n```loci-question\n{"questions":[{"id":"target","header":"Learning target","question":"What is the real target behind properly?","options":[{"label":"Mechanism mastery (Recommended)"}]}]}\n```\n\nMy read: mechanism first.';
    expect(asksSomething(card)).toBe(true);
    expect(questionsIn(card)).toEqual(["Learning target: What is the real target behind properly?"]);
    expect(questionCount(card)).toBe(1);
    expect(nextMessage(card, { answers }, { used: {}, hasCourse: false, nudged: false })).toMatchObject({ text: "Fix SQLITE_BUSY.", topics: ["goal"] });
  });

  it("ignores question marks inside code", () => {
    expect(asksSomething("Run this:\n```sql\nSELECT ?;\n```\nDone.")).toBe(false);
  });
});

describe("provider error replies", () => {
  it.each([
    "User location is not supported for the API use.",
    "Agent connection was lost",
    "Unauthorized",
    "Internal error",
    "Invalid or expired credentials",
  ])("fails a turn whose whole reply is the provider's error: %s", (text) => {
    expect(providerErrorIn({ status: "done", text, tools: 0 })).toBe(text);
    expect(providerErrorIn({ status: "done", text: `${text}\n\nretry later`, tools: 0 })).toBe(text);
  });

  it("leaves a turn that did work, or that writes about errors, to the mentor", () => {
    expect(providerErrorIn({ status: "done", text: "Internal error", tools: 2 })).toBeNull();
    expect(providerErrorIn({ status: "done", text: "An internal error is raised when a lock is held.", tools: 0 })).toBeNull();
    expect(providerErrorIn({ status: "failed", text: "Unauthorized", tools: 0 })).toBeNull();
    expect(providerErrorIn({ status: "done", text: "", tools: 0 })).toBeNull();
    expect(providerErrorIn({ status: "needs-you", text: "Unauthorized?", tools: 0 })).toBeNull();
  });
});

const sqliteDoc = "# Write-Ahead Logging\n\n## Checkpointing\n\nA checkpoint moves **frames** from the WAL file back into the [database](https://sqlite.org).\n\n## Concurrency\n\nReaders do not block writers.\n";

describe("automatic checks", () => {
  it("flattens Markdown to the text a quote is found in, and lists headings outside code", () => {
    expect(flattenMarkdown("A **bold** [link](x) and `code`.")).toBe("A bold link and code.");
    expect(headingsOf("# One\n```\n# not a heading\n```\n## Two ##\n")).toEqual(["One", "Two"]);
    expect(headingsOf("# 1. Overview\n## 2.1. **Check**pointing\n")).toEqual(["1. Overview", "2.1. Checkpointing"]);
    expect(quoteResolves(sqliteDoc, "moves frames from the WAL file back into the database")).toBe(true);
    expect(quoteResolves(sqliteDoc, "MOVES   frames from the wal file")).toBe(true);
    expect(quoteResolves(sqliteDoc, "copies pages to the journal")).toBe(false);
  });

  it("knows first-party addresses by host suffix or host and path", () => {
    const domains = ["sqlite.org", "github.com/kubernetes"];
    expect(isFirstParty("https://www.sqlite.org/wal.html", domains)).toBe(true);
    expect(isFirstParty("https://github.com/kubernetes/kubernetes/blob/master/README.md", domains)).toBe(true);
    expect(isFirstParty("https://raw.githubusercontent.com/kubernetes/website/main/x.md", ["github.com"])).toBe(true);
    expect(isFirstParty("https://github.com/someone/k8s-notes", domains)).toBe(false);
    expect(isFirstParty("https://medium.com/sqlite-wal", domains)).toBe(false);
    expect(isFirstParty("not a url", domains)).toBe(false);
  });

  it("flags sources that read like the mentor's own summary", () => {
    expect(summarySignals({ body: "In this guide, we will explore WAL. Key takeaways: ...", sourceUrl: "https://sqlite.org/wal.html" }).length).toBeGreaterThan(0);
    expect(summarySignals({ body: "word ".repeat(400), sourceUrl: "https://sqlite.org/wal.html" })).toEqual([]);
  });

  it("checks that lessons point at documents, sections, files and lines that exist, in reading order", () => {
    const sources = new Map([["wal", { body: sqliteDoc, kind: "source" }]]);
    const files: Record<string, string> = { "/w/repos/x/lib.rs": "a\nb\nc\n" };
    const library = { sources, readFile: (path: string) => files[path] ?? null };
    const course = { chapters: [{ title: "WAL", lessons: [
      { id: "concurrency", title: "C", document: "wal", section: "Concurrency" },
      { id: "checkpoint", title: "K", document: "wal", section: "Checkpointing" },
      { id: "missing", title: "M", document: "wal", section: "Recovery" },
      { id: "code", title: "Code", file: "/w/repos/x/lib.rs", lines: [1, 3] },
      { id: "far", title: "Far", file: "/w/repos/x/lib.rs", lines: [2, 90] },
      { id: "gone", title: "Gone", document: "nope" },
    ] }] };
    const results = checkLessons(course, library);
    expect(results.filter((lesson: { ok: boolean }) => lesson.ok).map((lesson: { id: string }) => lesson.id)).toEqual(["concurrency", "checkpoint", "code"]);
    expect(results.find((lesson: { id: string }) => lesson.id === "far").problems[0]).toMatch(/outside/);
    expect(orderProblems(course, sources)).toEqual(['checkpoint ("Checkpointing") comes before concurrency in wal']);
  });

  it("finds citations in a reply and resolves their sections, quotes and lines", () => {
    const sources = new Map([["wal", { body: sqliteDoc }]]);
    const library = { sources, readFile: (path: string) => (path === "/w/a.rs" ? "1\n2\n3" : path === "/w/rel/b.rs" ? "x\ny" : null), roots: ["/w"] };
    const reply = [
      "[ok](loci://source/wal#section=Checkpointing&quote=moves%20frames%20from%20the%20WAL%20file)",
      "[bad quote](loci://source/wal#quote=never%20written)",
      "[no doc](loci://source/other)",
      "[code](/w/a.rs#L2-3)",
      `[rel](loci://file/${Buffer.from("rel/b.rs").toString("base64url")}#L1-2)`,
      "[web](https://sqlite.org)",
    ].join(" ");
    const links = citationsIn(reply);
    expect(links).toHaveLength(5);
    const checked = links.map((link: unknown) => checkCitation(link, library));
    expect(checked.map((entry: { ok: boolean }) => entry.ok)).toEqual([true, false, false, true, true]);
    expect(checked[0].quoted).toBe(true);
  });

  it("scores a whole run", () => {
    const scenario = { id: "sqlite-wal", template: "learning-guide", opening: "Teach me WAL", firstPartyDomains: ["sqlite.org"], expect: { minLessons: 1, maxLessons: 5 } };
    const score = scoreRun({
      scenario,
      sources: [
        { id: "wal", title: "WAL", kind: "source", sourceUrl: "https://sqlite.org/wal.html", body: sqliteDoc + "word ".repeat(300) },
        { id: "blog", title: "Blog", kind: "source", sourceUrl: "https://example.com/wal", body: "word ".repeat(300) },
        { id: "guide", title: "Guide", kind: "guide", body: "Read wal first." },
      ],
      courses: [{ id: "c", title: "C", chapters: [{ title: "A", lessons: [{ id: "l", title: "L", document: "wal", section: "Checkpointing" }, { id: "g", title: "G", document: "guide" }] }] }],
      turns: [
        { role: "learner", text: "Teach me WAL" },
        { role: "mentor", text: "What is your goal? And your level?" },
        { role: "learner", text: "probe", probe: true },
        { role: "mentor", probe: true, text: "See [here](loci://source/wal#quote=Readers%20do%20not%20block%20writers)." },
      ],
      timings: { firstReply: 20, firstSource: 200, course: 300, turnsBeforeFirstSource: 2 },
      failures: [], nudges: 0,
    }, { readFile: () => null, roots: [] });
    expect(score.sources).toMatchObject({ firstHand: 2, guides: 1, firstParty: 1, firstPartyShare: 50 });
    expect(score.sources).toMatchObject({ filesReadInPlace: 0, repoFiles: 0 });
    expect(score.course).toMatchObject({ lessons: 2, lessonsResolved: 2, lessonsOnGuides: 1, chapters: 1, withinExpected: true });
    expect(score.citations).toMatchObject({ total: 1, resolved: 1, quoted: 1, probeCited: true });
    expect(score.firstTenMinutes).toMatchObject({ maxQuestionsInOneReply: 2, firstSourceSeconds: 200 });
    expect(score.sandbox).toBeUndefined();
  });
});

describe("the v0.4 sandbox checks", () => {
  const commit = "a".repeat(40);
  const files = { readFile: (path: string) => (path.endsWith("a.go") ? "a\nb\nc" : null), roots: ["/w"], readPinned: () => "a\nb\nc" };

  function fixture() {
    const lessons = (course: string): any[] => Array.from({ length: 6 }, (_, index) => ({
      id: `${course}-l${index}`, title: `Lesson ${index}`, file: "repos/acme/box/src/a.go", commit, lines: [1, 2],
    }));
    const courses = ["c1", "c2", "c3"].map((id) => ({ id, title: id, chapters: [{ title: "Code", lessons: lessons(id) }] }));
    return {
      scenario: {
        id: "sandbox-path", template: "learning-guide", acceptance: "v0.4", rubric: ["codeTours", "path"], firstPartyDomains: ["docs.kernel.org"],
        expect: { pathCourses: [3, 5], lessonsPerCourse: [6, 12], minCodeLessonsPerCourse: 1, minFirstHand: 10, firstSourceWithinSeconds: 300, compareLessons: 1, tolerateMissingCompare: true },
      },
      sources: Array.from({ length: 10 }, (_, index) => ({ id: `s${index}`, title: `Source ${index}`, kind: "source", sourceUrl: `https://docs.kernel.org/${index}`, version: "6.12", body: "word ".repeat(300) })),
      courses,
      path: { path: { title: "Boxes", courses: [{ id: "c1" }, { id: "c2", after: ["c1"] }, { id: "c3", after: ["c2"] }] }, file: "courses/_path.yaml" },
      pins: { pins: courses.flatMap((course) => course.chapters[0].lessons.map((lesson) => ({ course: course.id, lesson: lesson.id, file: lesson.file, commit, lines: lesson.lines, state: "current" }))), stale: 0 },
      libraryProblems: [],
      timings: { firstSource: 120 }, turns: [], failures: [], nudges: 0,
    };
  }

  it("passes a path of three 6-lesson courses with pinned tours, ten sourced and versioned first-hand sources, and a readable folder", () => {
    const run = fixture();
    const check = checkSandbox(run, files);
    expect(check.ok).toBe(true);
    expect(check.path).toMatchObject({ checked: true, exists: true, count: 3, withinRange: true });
    expect(check.code).toMatchObject({ lessons: 18, pinned: 18, unpinned: [] });
    expect(check.code.pins.byState.current).toBe(18);
    expect(check.code.lines).toMatchObject({ checked: 18, resolved: 18 });
    expect(check.firstHand).toMatchObject({ count: 10, min: 10, ok: true, missingAddress: [], missingVersion: [], firstSourceSeconds: 120 });
    expect(check.compare).toMatchObject({ count: 0, expected: 1, tolerated: true });
    expect(check.library).toMatchObject({ checked: true, problems: 0 });
    expect(scoreRun(run, files).sandbox.ok).toBe(true);
  });

  it("fails a missing path, a course outside 6–12 lessons, and a course with no code tour", () => {
    const missing = fixture();
    missing.path = null as never;
    expect(checkSandbox(missing, files).problems.join(" ")).toContain("no learning path");

    const short = fixture();
    short.courses[0].chapters[0].lessons = short.courses[0].chapters[0].lessons.slice(0, 5);
    expect(checkSandbox(short, files).problems.join(" ")).toContain("c1 has 5 lessons");

    const prose = fixture();
    for (const lesson of prose.courses[1].chapters[0].lessons) {
      lesson.file = undefined as never;
      lesson.document = "s0";
      lesson.section = "Overview";
    }
    const check = checkSandbox(prose, files);
    expect(check.problems.join(" ")).toContain("c2 has 0 code lessons");
  });

  it("fails an unpinned code lesson, a pin that moved to changed or went missing, and a range outside its pinned file", () => {
    const unpinned = fixture();
    unpinned.courses[0].chapters[0].lessons[0].commit = undefined as never;
    unpinned.pins.pins.shift();
    expect(checkSandbox(unpinned, files).problems.join(" ")).toContain("c1/c1-l0 is a code lesson without a commit");

    const changed = fixture();
    changed.pins.pins[0].state = "changed";
    expect(checkSandbox(changed, files).problems.join(" ")).toContain("pin is changed");

    const missing = fixture();
    missing.pins = null as never;
    expect(checkSandbox(missing, files).problems.join(" ")).toContain("code pins did not run");

    const far = fixture();
    far.courses[0].chapters[0].lessons[0].lines = [1, 99];
    far.pins.pins[0].lines = [1, 99];
    const check = checkSandbox(far, files);
    expect(check.problems.join(" ")).toContain("lines 1-99 outside 1-3");
    expect(check.code.lines).toMatchObject({ checked: 18, resolved: 17 });
  });

  it("fails first-hand sources without an address or a version, too few of them, and a late first source", () => {
    const noAddress = fixture();
    noAddress.sources[0].sourceUrl = null as never;
    expect(checkSandbox(noAddress, files).problems.join(" ")).toContain("source s0 has no sourceUrl");

    const noVersion = fixture();
    noVersion.sources[1].version = "" as never;
    expect(checkSandbox(noVersion, files).problems.join(" ")).toContain("source s1 has no version");

    const few = fixture();
    few.sources = few.sources.slice(0, 9);
    expect(checkSandbox(few, files).problems.join(" ")).toContain("9 first-hand sources; expected at least 10");

    const late = fixture();
    late.timings.firstSource = 400;
    expect(checkSandbox(late, files).problems.join(" ")).toContain("first source after 400s");
  });

  it("counts comparison lessons with two parts, tolerates their absence, and flags a one-part comparison", () => {
    const present = fixture();
    present.courses[0].chapters[0].lessons[0].compare = [{ file: "repos/acme/box/a.go", commit, lines: [1, 2] }, { file: "repos/acme/box/b.go", commit, lines: [1, 2] }];
    const check = checkSandbox(present, files);
    expect(check.compare).toMatchObject({ count: 1, present: 1, expected: 1, tolerated: false });
    expect(check.ok).toBe(true);

    const onePart = fixture();
    onePart.courses[0].chapters[0].lessons[0].compare = [{ file: "repos/acme/box/a.go" }];
    expect(checkSandbox(onePart, files).problems.join(" ")).toContain("compares fewer than two parts");

    const absent = fixture();
    absent.scenario.expect.compareLessons = 1;
    expect(checkSandbox(absent, files).compare.tolerated).toBe(true);
  });

  it("fails when library check found a file it could not read", () => {
    const broken = fixture();
    broken.libraryProblems = [{ kind: "source", id: "s3", error: "missing sourceUrl" }];
    const check = checkSandbox(broken, files);
    expect(check.ok).toBe(false);
    expect(check.problems.join(" ")).toContain("library: source/s3: missing sourceUrl");
    expect(check.library).toMatchObject({ checked: true, problems: 1 });
  });

  it("leaves a PDF file lesson out of the code-tour count, while checking its course's length", () => {
    const run = fixture();
    run.courses[0].chapters[0].lessons.push({ id: "paper", title: "The paper", file: "papers/sandbox.pdf", pages: [1, 4] });
    const check = checkSandbox(run, files);
    expect(check.code).toMatchObject({ lessons: 18, pinned: 18 });
    expect(check.courseLessons[0]).toMatchObject({ lessons: 7, withinRange: true });
    expect(check.ok).toBe(true);
  });

  it("reads a lesson's pinned range at its commit, and resolves relative files inside the mentor folder", () => {
    const course = { chapters: [{ title: "A", lessons: [
      { id: "pinned", title: "Pinned", file: "repos/x/a.go", commit, lines: [1, 2] },
      { id: "relative", title: "Relative", file: "repos/x/a.go", lines: [1, 3] },
      { id: "missing-relative", title: "Missing", file: "repos/x/missing.go", lines: [1, 3] },
      { id: "too-far", title: "Far", file: "repos/x/a.go", commit, lines: [2, 9] },
    ] }] };
    const library = { sources: new Map(), roots: ["/mentor"], readFile: (path: string) => (path === "/mentor/repos/x/a.go" ? "1\n2\n3\n4\n5" : null), readPinned: () => "1\n2\n3" };
    const checked = checkLessons(course, library);
    expect(checked.map((lesson: { ok: boolean }) => lesson.ok)).toEqual([true, true, false, false]);
    expect(checked[1].problems).toEqual([]);
    expect(checked[2].problems[0]).toMatch(/no file repos\/x\/missing.go/);
    expect(checked[3].problems[0]).toMatch(/lines 2-9 outside 1-3/);
    expect(lessonFileText({ readFile: (path: string) => (path === "/mentor/repos/x/a.go" ? "x" : null), roots: ["/mentor"] }, "repos/x/a.go")).toBe("x");
  });
});

describe("the judge and the summary", () => {
  const verdict = { scores: { firstHand: { score: 4, reason: "docs" }, courseStructure: { score: 3, reason: "ok" }, grounding: { score: 2, reason: "few links" }, firstTenMinutes: { score: 5, reason: "fast" } }, worst: "Cite more." };

  it("reads a verdict out of plain text, a fenced block or a CLI's JSON envelope, and rejects incomplete ones", () => {
    expect(parseVerdict(`Here you go:\n\`\`\`json\n${JSON.stringify(verdict)}\n\`\`\``)).toEqual(verdict);
    expect(parseVerdict(JSON.stringify({ result: JSON.stringify(verdict) }))).toEqual(verdict);
    expect(parseVerdict(JSON.stringify({ scores: { firstHand: { score: 9 } } }))).toBeNull();
    expect(parseVerdict("no json")).toBeNull();
    const braces = { ...verdict, scores: { ...verdict.scores, grounding: { score: 2, reason: "cites `fn run() { steal(); }` without a link" } } };
    expect(parseVerdict(`Verdict: ${JSON.stringify(braces)}`)?.scores.grounding.reason).toContain("{ steal(); }");
  });

  it("fills the judge prompt kept in the repo with the evidence", () => {
    const prompt = judgePrompt({
      scenario: { opening: "Teach me WAL", template: "learning-guide", learner: { background: "Go engineer" } },
      checks: { sources: { firstHand: 1 } }, sources: [{ id: "wal", title: "WAL", sourceUrl: "https://sqlite.org/wal.html", body: "text" }],
      courses: [], turns: [{ role: "learner", text: "Teach me WAL" }, { role: "mentor", text: "Goal?" }],
    });
    expect(prompt).toContain("Go engineer");
    expect(prompt).toContain("https://sqlite.org/wal.html");
    expect(prompt).toContain("#### Mentor\nGoal?");
    expect(prompt).not.toMatch(/\{\{\w+\}\}/);
  });

  it("adds the code-tour and path rubric items only when a scenario asks for them", () => {
    const commit = "a".repeat(40);
    expect(rubricFor({})).toEqual(RUBRIC);
    expect(rubricFor({ rubric: ["codeTours", "path", "unknown"] })).toEqual([...RUBRIC, "codeTours", "path"]);
    const keys = rubricFor({ rubric: ["codeTours", "path"] });
    const prompt = judgePrompt({
      scenario: { opening: "Sandboxes", template: "learning-guide", learner: { background: "Systems engineer" }, rubric: ["codeTours", "path"] },
      checks: {}, sources: [], courses: [], turns: [],
      codeTours: [{ course: "c1", lesson: "l1", title: "Entry point", file: "repos/x/a.go", commit, lines: [1, 2], state: "current", excerpt: "func main() {}" }],
    });
    expect(prompt).toContain("**codeTours**");
    expect(prompt).toContain("**path**");
    expect(prompt).toContain("Entry point");
    expect(prompt).toContain('"codeTours":{"score":1');
    expect(prompt).not.toMatch(/\{\{\w+\}\}/);
    const verdict = { scores: Object.fromEntries(keys.map((key: string) => [key, { score: 4, reason: key }])), worst: "Pin every lesson." };
    expect(parseVerdict(JSON.stringify(verdict), keys)).toMatchObject({ worst: "Pin every lesson." });
    expect(Object.keys(parseVerdict(JSON.stringify(verdict), keys)!.scores)).toEqual(keys);
    expect(RUBRIC_EXTENSIONS.codeTours).toMatch(/call path/);
    expect(RUBRIC_EXTENSIONS.path).toMatch(/progressive/);
  });

  it("pins each judge's model and runs other judges only when named", () => {
    expect(judgeCommand("agy", "claude-opus-4-6-thinking", "/p", "prompt")).toEqual(["agy", ["-p", "prompt", "--print-timeout", "600s", "--model", "claude-opus-4-6-thinking"]]);
    expect(DEFAULT_JUDGE_MODEL).toMatchObject({ agy: "claude-opus-4-6-thinking", grok: "deepseek-flash" });
    expect(judgeCommand("grok", DEFAULT_JUDGE_MODEL.grok, "/p", "prompt")).toEqual(["grok", ["--prompt-file", "/p", "--disable-web-search", "--no-subagents", "--model", "deepseek-flash"]]);
    expect(() => judgeCommand("pi", undefined, "/p", "x")).toThrow(/No judge/);
  });

  it("names the provider, model and judge a run used, and that only matching runs compare", () => {
    const meta = {
      startedAt: "2026-11-01T10:00:00.000Z", app: "com.loci.desktop.qa-eval", provider: "grok", model: "grok:deepseek-flash",
      mode: "full-access", judge: { provider: "grok", model: null }, templates: { "learning-guide": "abc" },
    };
    const pinned = { ...meta, judge: { provider: "grok", model: "deepseek-flash" } };
    const text = summaryMarkdown(pinned, [{ scenario: { id: "sqlite-wal", template: "learning-guide" }, error: "boom" }]);
    expect(text).toContain("Mentors on `grok` / `grok:deepseek-flash`, judged by `grok` / `deepseek-flash`");
    expect(text).toContain("Compare this run only with runs whose provider, model and judge match");
    expect(text).not.toMatch(/provisional/i);
    expect(text).toContain("sqlite-wal");
    expect(runSetup(pinned)).toEqual({ provider: "grok", model: "grok:deepseek-flash", judge: "grok", judgeModel: "deepseek-flash" });
    expect(runSetup({ ...meta, judge: { provider: "none" } }).judge).toBeNull();
    expect(summaryMarkdown(meta, [])).toContain("`grok` (its configured default model)");
    expect(summaryMarkdown({ ...meta, judge: { provider: "none" } }, [])).toContain("no rubric judge");
  });

  it("prints the sandbox acceptance table and the extra rubric columns when a run has them", () => {
    const meta = {
      startedAt: "2026-11-01T10:00:00.000Z", app: "com.loci.desktop.qa-eval", provider: "grok", model: "grok:deepseek-flash",
      mode: "full-access", judge: { provider: "grok", model: "deepseek-flash" }, templates: { "learning-guide": "abc" },
    };
    const sandbox = {
      ok: true, problems: [],
      path: { checked: true, exists: true, count: 3, expected: [3, 5], title: "Boxes", courses: [{ id: "c1", lessons: 6, withinRange: true, planned: false }], otherCourses: [] },
      courseLessons: [],
      code: { lessons: 18, pinned: 18, unpinned: [], pins: { listed: 18, stale: 0, byState: { current: 18, moved: 0, changed: 0, "missing-commit": 0, "missing-file": 0, "no-repo": 0, error: 0 } }, lines: { checked: 18, resolved: 18, withoutLines: [], problems: [] }, perCourse: [] },
      firstHand: { count: 10, min: 10, ok: true, missingAddress: [], missingVersion: [], firstSourceSeconds: 120, withinSeconds: 300 },
      compare: { count: 0, expected: 1, tolerated: true, present: 0, lessons: [], rows: [] },
      library: { checked: true, problems: 0, list: [] },
    };
    const score = {
      sources: { firstHand: 10, firstPartyShare: 100, guides: 0, filesReadInPlace: 0, repoFiles: 0, downloadedDocuments: 0, offDomain: [], suspectedSummaries: [] },
      course: { courses: 3, chapters: 3, lessons: 18, withinExpected: true, lessonsOnFiles: 18, lessonsOnGuides: 0, lessonProblems: [], orderProblems: [] },
      citations: { total: 0, resolved: 0, quoted: 0, quotesResolved: 0, repliesWithCitations: 0, replies: 2, probeCited: false, probeResolved: 0, problems: [] },
      firstTenMinutes: { firstReplySeconds: 10, firstSourceSeconds: 120, courseSeconds: 200, mentorTurnsBeforeFirstSource: 0, questionsPerReply: [], maxQuestionsInOneReply: 0, nudges: 0 },
      failures: [], sandbox,
    };
    const verdict = { scores: Object.fromEntries(["firstHand", "courseStructure", "grounding", "firstTenMinutes", "codeTours", "path"].map((key) => [key, { score: 4, reason: key }])), worst: "Pin more." };
    const text = summaryMarkdown(meta, [{ scenario: { id: "sandbox-path", template: "learning-guide" }, score, judge: { verdict } }]);
    expect(text).toContain("Sandbox acceptance (v0.4)");
    expect(text).toContain("| Code tours | Path |");
    expect(text).toContain("c1=6");
    expect(text).toContain("Acceptance: pass");
    // A mixed run keeps the old scenarios' four scores and shows a dash for the new columns.
    const base = { ...verdict, scores: Object.fromEntries(["firstHand", "courseStructure", "grounding", "firstTenMinutes"].map((key) => [key, { score: 3, reason: key }])) };
    const mixed = summaryMarkdown(meta, [
      { scenario: { id: "sandbox-path", template: "learning-guide" }, score, judge: { verdict } },
      { scenario: { id: "sqlite-wal", template: "learning-guide" }, score: { ...score, sandbox: undefined }, judge: { verdict: base } },
    ]);
    expect(mixed).toContain("| **mean** |");
    expect(mixed).toContain("4");
    expect(mixed).toContain("—");
  });
});

describe("the runner's defaults", () => {
  it("runs mentors and judge on grok unless another provider is named", () => {
    expect(DEFAULT_PROVIDER).toBe("grok");
    expect(defaultMentorModel("grok")).toBe("grok:deepseek-flash");
    expect(defaultMentorModel("agy")).toBeUndefined();
  });

  it("baseline.sh runs the official grok setup, with the other providers as options", () => {
    const script = readFileSync(join(__dirname, "baseline.sh"), "utf8");
    expect(script).toContain('PROVIDER="${LOCI_EVAL_PROVIDER:-grok}"');
    expect(script).toContain('MODEL="grok:deepseek-flash"');
    expect(script).toContain('--judge "${LOCI_EVAL_JUDGE:-grok}"');
    expect(script).toContain("--provider \"$PROVIDER\"");
    expect(script).not.toContain("--provider agy");
  });
});

describe("seeding local repositories", () => {
  function tempRepo(root: string, name: string): string {
    const source = join(root, name);
    mkdirSync(source, { recursive: true });
    execFileSync("git", ["init", "-q", source]);
    writeFileSync(join(source, "README.md"), "# Box\n\nA sandbox.\n");
    execFileSync("git", ["-C", source, "add", "."]);
    execFileSync("git", ["-C", source, "-c", "user.name=Eval", "-c", "user.email=eval@example.com", "commit", "-qm", "init"]);
    return source;
  }

  it("clones a scenario's checkout into the mentor folder without changing its source, and skips a repeat", () => {
    const root = mkdtempSync(join(tmpdir(), "loci-eval-seed-test-"));
    try {
      const sourceRoot = join(root, "repos");
      const source = tempRepo(join(sourceRoot, "acme"), "box");
      const head = execFileSync("git", ["-C", source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
      const folder = join(root, "mentor");
      const [first] = seedRepos({ folder, repos: ["acme/box"], sourceRoot });
      expect(first).toMatchObject({ repo: "acme/box", head, skipped: false });
      expect(countFiles(join(folder, "repos/acme/box"))).toBeGreaterThan(0);
      expect(execFileSync("git", ["-C", source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim()).toBe(head);
      expect(execFileSync("git", ["-C", source, "status", "--porcelain"], { encoding: "utf8" }).trim()).toBe("");
      const text = pinnedText(join(folder, "repos/acme/box/README.md"), head, [folder]);
      expect(text).toBe("# Box\n\nA sandbox.\n");
      expect(lineCount(text)).toBe(3);
      const [again] = seedRepos({ folder, repos: ["acme/box"], sourceRoot });
      expect(again.skipped).toBe(true);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("refuses a missing checkout, and only removes a folder under a Loci-Dev root", () => {
    const root = mkdtempSync(join(tmpdir(), "loci-eval-seed-test-"));
    try {
      const sourceRoot = join(root, "repos");
      expect(() => seedRepos({ folder: join(root, "mentor"), repos: ["nope/missing"], sourceRoot })).toThrow(/No local checkout/);
      const home = join(root, "home");
      const qa = join(home, "Loci-Dev-qa-eval", "sandbox");
      mkdirSync(qa, { recursive: true });
      expect(removableMentorFolder(qa, { home })).toBe(true);
      const installed = join(home, "Loci", "sandbox");
      mkdirSync(installed, { recursive: true });
      expect(removableMentorFolder(installed, { home })).toBe(false);
      expect(removableMentorFolder(join(home, "Loci-Dev-qa-eval", "gone"), { home })).toBe(false);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

describe("scenarios", () => {
  const dir = join(__dirname, "scenarios");
  const scenarios = readdirSync(dir).filter((name) => name.endsWith(".json")).map((name) => ({ name, data: JSON.parse(readFileSync(join(dir, name), "utf8")) }));

  it("are 3 to 7, each complete and named after its file", () => {
    expect(scenarios.length).toBeGreaterThanOrEqual(3);
    expect(scenarios.length).toBeLessThanOrEqual(7);
    for (const { name, data } of scenarios) {
      expect(`${data.id}.json`).toBe(name);
      expect(["learning-guide", "repo-lens"]).toContain(data.template);
      expect(data.opening && data.probe && data.firstPartyDomains.length).toBeTruthy();
      for (const topic of ["goal", "level", "time", "confirm"]) expect(data.learner.answers[topic], `${name} ${topic}`).toBeTruthy();
      expect(data.maxMinutes).toBeLessThanOrEqual(20);
    }
  });

  it("seed only the sandbox scenarios, from owner/repo names under the shared checkout root", () => {
    const seeded = scenarios.filter(({ data }) => data.seed);
    expect(seeded.map(({ data }) => data.id).sort()).toEqual(["cube-snapshot", "sandbox-path"]);
    for (const { data } of seeded) {
      expect(data.acceptance).toBe("v0.4");
      for (const repo of data.seed.repos) expect(repo).toMatch(/^[^/\\]+\/[^/\\]+$/);
    }
    expect(scenarios.find(({ data }) => data.id === "sandbox-path")?.data.seed.repos).toHaveLength(3);
  });
});

it("keeps results out of git", () => {
  expect(readFileSync(join(__dirname, "../../.gitignore"), "utf8")).toMatch(/^eval\/results\/$/m);
});
