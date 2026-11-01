// Automatic checks over what a scenario run collected. Pure functions: the
// runner hands in plain data (sources with their text, courses, replies and a
// way to read files), so the checks are unit-tested without an app or model.
//
// Quotes and sections are resolved with the reader's own code, so a citation
// that passes here is one the reader can find: textAnchor.ts (exact, then by
// context, then ignoring white space and case) and markdownSection.ts (the
// heading match a lesson's `section` uses). Node >= 22.18 strips their types.
import { quoteInText } from "../../src/features/learning/model/textAnchor.ts";
import { sectionHeadingIndex } from "../../src/shared/lib/markdown/markdownSection.ts";
import { fileResourcePath, parseAppResourceUrl } from "../../src/shared/lib/appResourceLinks.ts";
import { questionCount } from "./learner.mjs";

/** Inline Markdown (links, emphasis, code, tags) reduced to its text. */
function flattenInline(text) {
  return String(text ?? "")
    .replace(/<\/?[A-Za-z][^>]*>/g, "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__|\*|~~|`)/g, "")
    .replace(/\\([\\`*_{}[\]()#+\-.!|])/g, "$1");
}

/** Markdown reduced to roughly the text the reader renders, for resolving quotes. */
export function flattenMarkdown(markdown) {
  return String(markdown ?? "")
    .replace(/^---\n[\s\S]*?\n---\n/, "")
    .replace(/^(`{3,}|~{3,}).*$/gm, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<\/?[A-Za-z][^>]*>/g, "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\[[^\]]*\]/g, "$1")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s{0,3}>\s?/gm, "")
    .replace(/^\s*(?:[-*+]|\d+[.)])\s+/gm, "")
    .replace(/^\s*\|?[\s:|-]+\|[\s:|-]*$/gm, "")
    .replace(/\|/g, " ")
    .replace(/(\*\*|__|\*|_|~~|`)/g, "")
    .replace(/\\([\\`*_{}[\]()#+\-.!|])/g, "$1");
}

/** The visible titles of a Markdown document's headings, outside code blocks. */
export function headingsOf(markdown) {
  const titles = [];
  let fence = null;
  for (const line of String(markdown ?? "").split("\n")) {
    const opener = /^\s{0,3}(`{3,}|~{3,})/.exec(line);
    if (opener) {
      if (!fence) fence = opener[1][0];
      else if (opener[1][0] === fence) fence = null;
      continue;
    }
    if (fence) continue;
    const heading = /^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    // Inline only: a numbered heading ("1. Overview") keeps its number, as the reader shows it.
    if (heading) titles.push(flattenInline(heading[1]).trim());
  }
  return titles;
}

/** Whether a section name resolves to a heading, as the reader would focus it. */
export function sectionResolves(markdown, section) {
  return sectionHeadingIndex(headingsOf(markdown), section) >= 0;
}

/** Whether a quote is found in a Markdown document's text. */
export function quoteResolves(markdown, quote) {
  return !!quoteInText(flattenMarkdown(markdown), quote) || !!quoteInText(String(markdown ?? ""), quote);
}

/**
 * Whether a URL is first-party for a scenario. Domains are host suffixes
 * ("sqlite.org") or host plus path prefix ("github.com/kubernetes").
 */
export function isFirstParty(url, domains) {
  let parsed;
  try { parsed = new URL(url); } catch { return false; }
  const host = parsed.hostname.toLowerCase().replace(/^www\./, "");
  const path = parsed.pathname.toLowerCase();
  return domains.some((entry) => {
    const [domain, ...rest] = entry.toLowerCase().split("/");
    const prefix = rest.length ? `/${rest.join("/")}` : "";
    const hostOk = host === domain || host.endsWith(`.${domain}`)
      // raw/codeload copies of a GitHub repo are the repo.
      || (domain === "github.com" && ["raw.githubusercontent.com", "codeload.github.com"].includes(host));
    if (!hostOk) return false;
    if (!prefix) return true;
    return path === prefix || path.startsWith(`${prefix}/`) || path.startsWith(`${prefix}`);
  });
}

const SUMMARY_PHRASES = [
  /\b(in this (guide|summary|overview|document),? (we|you) (will|'ll))\b/i,
  /\byou will learn\b/i,
  /\bkey takeaways?\b/i,
  /\b(tl;dr|summary of|this summary)\b/i,
  /\b(let'?s (dive|explore)|we'?ll (explore|cover))\b/i,
  /\b(as your mentor|for the learner|learning objectives?)\b/i,
  /本文将|总结|要点|学习目标|导读|我们将/,
];

/**
 * Reasons a saved source looks like something the mentor wrote rather than
 * the published text. A heuristic: the judge sees the flagged ids too.
 */
export function summarySignals(source) {
  const reasons = [];
  const body = String(source.body ?? source.text ?? "");
  const words = body.split(/\s+/).filter(Boolean).length;
  for (const phrase of SUMMARY_PHRASES) if (phrase.test(body)) reasons.push(`phrase ${phrase.source.slice(0, 40)}`);
  if (words < 250 && !/\.(md|txt|rst)$/i.test(source.sourceUrl ?? "")) reasons.push(`short (${words} words)`);
  return reasons;
}

/** The lessons of a reading course, flattened with their chapter. */
export function lessonsOf(course) {
  const data = course?.data ?? course;
  return (data?.chapters ?? []).flatMap((chapter, at) => (chapter.lessons ?? []).map((lesson) => ({ ...lesson, chapter: chapter.title ?? `#${at + 1}` })));
}

/**
 * Whether each lesson points at something real: a document in the library and
 * its section, or an existing file and a line range inside it.
 * @param {{ sources: Map<string, {body: string, kind?: string}>, readFile: (path: string) => string | null }} library
 */
export function checkLessons(course, library) {
  return lessonsOf(course).map((lesson) => {
    const result = { id: lesson.id, title: lesson.title, chapter: lesson.chapter, ok: true, problems: [] };
    if (lesson.document) {
      const document = library.sources.get(lesson.document);
      result.target = `source:${lesson.document}`;
      result.kind = document?.kind;
      if (!document) { result.ok = false; result.problems.push(`no document ${lesson.document}`); }
      else if (lesson.section && !sectionResolves(document.body, lesson.section)) { result.ok = false; result.problems.push(`section "${lesson.section}" not found`); }
    } else if (lesson.file) {
      result.target = `file:${lesson.file}`;
      const text = library.readFile(lesson.file);
      if (text == null) { result.ok = false; result.problems.push(`no file ${lesson.file}`); }
      else if (lesson.lines) {
        const count = text.split("\n").length;
        const [first, last] = lesson.lines;
        if (!(first >= 1 && last >= first && last <= count)) { result.ok = false; result.problems.push(`lines ${first}-${last} outside 1-${count}`); }
      }
    } else { result.ok = false; result.problems.push("no document or file"); }
    return result;
  });
}

/**
 * Lessons that share a document should read it front to back; a lesson whose
 * section comes before the previous lesson's in the same document is out of order.
 */
export function orderProblems(course, sources) {
  const last = new Map();
  const problems = [];
  for (const lesson of lessonsOf(course)) {
    if (!lesson.document || !lesson.section) continue;
    const document = sources.get(lesson.document);
    if (!document) continue;
    const at = sectionHeadingIndex(headingsOf(document.body), lesson.section);
    if (at < 0) continue;
    const before = last.get(lesson.document);
    if (before !== undefined && at < before.at) problems.push(`${lesson.id} ("${lesson.section}") comes before ${before.id} in ${lesson.document}`);
    last.set(lesson.document, { at, id: lesson.id });
  }
  return problems;
}

/** Every link a reply makes into the library or the file system. */
export function citationsIn(text) {
  const links = [];
  const pattern = /\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g;
  for (const match of String(text ?? "").matchAll(pattern)) {
    const href = match[2];
    if (href.startsWith("loci://")) links.push({ label: match[1], href, resource: parseAppResourceUrl(href) ?? null });
    else if (href.startsWith("/") || href.startsWith("file://")) links.push({ label: match[1], href, path: decodeURIComponent(href.replace(/^file:\/\//, "")) });
  }
  return links;
}

/**
 * Whether each citation resolves: the source exists, its section is a heading,
 * its quote is in the text, its lines are inside the file.
 * @param {{ sources: Map<string, {body: string}>, readFile: (path: string) => string | null, roots: string[] }} library
 */
export function checkCitation(citation, library) {
  const out = { href: citation.href, ok: true, problems: [] };
  const fail = (problem) => { out.ok = false; out.problems.push(problem); };
  const linesOk = (text, lines) => {
    const count = text.split("\n").length;
    if (lines && !(lines[0] >= 1 && lines[1] <= count)) fail(`lines ${lines.join("-")} outside 1-${count}`);
  };
  if (citation.path !== undefined) {
    out.kind = "path";
    const [path, fragment] = citation.path.split("#");
    const text = library.readFile(path);
    if (text == null) return fail(`no file ${path}`), out;
    const lines = /^L(\d+)(?:-L?(\d+))?$/.exec(fragment ?? "");
    if (lines) linesOk(text, [Number(lines[1]), Number(lines[2] ?? lines[1])]);
    return out;
  }
  const resource = citation.resource;
  if (!resource) return fail("not a valid loci:// link"), out;
  out.kind = resource.kind;
  if (resource.kind === "source") {
    const document = library.sources.get(resource.id);
    if (!document) return fail(`no source ${resource.id}`), out;
    const place = resource.place ?? {};
    if (place.section && !sectionResolves(document.body, place.section)) fail(`section "${place.section}" not found`);
    if (place.quote) { out.quoted = true; if (!quoteResolves(document.body, place.quote)) fail(`quote not found: "${place.quote.slice(0, 80)}"`); }
    if (place.lines) linesOk(document.body, place.lines);
    return out;
  }
  if (resource.kind === "file") {
    const relative = fileResourcePath(resource);
    const text = library.roots.map((root) => library.readFile(`${root}/${relative}`)).find((found) => found != null);
    if (text == null) return fail(`no file ${relative}`), out;
    const place = resource.place ?? {};
    if (place.lines) linesOk(text, place.lines);
    if (place.quote) { out.quoted = true; if (!quoteInText(text, place.quote)) fail(`quote not found: "${place.quote.slice(0, 80)}"`); }
    return out;
  }
  return out;
}

const share = (part, whole) => (whole ? Math.round((part / whole) * 100) : null);

/**
 * All automatic checks for one scenario.
 * @param {object} run what the runner collected: { scenario, sources: [{id,title,kind,sourceUrl,body}], courses: [{id,title,data}], turns: [{role,text,at}], timings, failures, nudges }
 * @param {{ readFile: (path: string) => string | null, roots: string[] }} files
 */
export function scoreRun(run, files) {
  const { scenario } = run;
  const sources = new Map(run.sources.map((source) => [source.id, source]));
  const library = { sources, readFile: files.readFile, roots: files.roots };
  const firstHand = run.sources.filter((source) => (source.kind ?? (source.sourceUrl ? "source" : "guide")) === "source");
  const guides = run.sources.filter((source) => !firstHand.includes(source));
  const firstParty = firstHand.filter((source) => isFirstParty(source.sourceUrl, scenario.firstPartyDomains));
  const suspicious = firstHand.map((source) => ({ id: source.id, reasons: summarySignals(source) })).filter((entry) => entry.reasons.length);

  const lessons = run.courses.flatMap((course) => checkLessons(course, library).map((lesson) => ({ course: course.id, ...lesson })));
  const order = run.courses.flatMap((course) => orderProblems(course, sources));
  const lessonCount = run.courses.reduce((sum, course) => sum + lessonsOf(course).length, 0);
  const mainCourse = run.courses[0];
  const chapters = mainCourse ? ((mainCourse.data ?? mainCourse).chapters ?? []).length : 0;

  const replies = run.turns.filter((turn) => turn.role === "mentor");
  const citations = replies.flatMap((turn, index) => citationsIn(turn.text).map((citation) => ({ reply: index, probe: !!turn.probe, ...checkCitation(citation, library) })));
  const quoted = citations.filter((citation) => citation.quoted);
  const probe = replies.find((turn) => turn.probe);
  const probeCitations = citations.filter((citation) => citation.probe);
  const questionCounts = replies.filter((turn) => !turn.probe).map((turn) => questionCount(turn.text));

  return {
    sources: {
      firstHand: firstHand.length,
      guides: guides.length,
      firstParty: firstParty.length,
      firstPartyShare: share(firstParty.length, firstHand.length),
      offDomain: firstHand.filter((source) => !firstParty.includes(source)).map((source) => ({ id: source.id, url: source.sourceUrl })),
      suspectedSummaries: suspicious,
    },
    course: {
      courses: run.courses.length,
      chapters,
      lessons: lessonCount,
      withinExpected: lessonCount >= (scenario.expect?.minLessons ?? 1) && lessonCount <= (scenario.expect?.maxLessons ?? Infinity),
      lessonsResolved: lessons.filter((lesson) => lesson.ok).length,
      lessonProblems: lessons.filter((lesson) => !lesson.ok).map((lesson) => `${lesson.course}/${lesson.id}: ${lesson.problems.join("; ")}`),
      lessonsOnGuides: lessons.filter((lesson) => lesson.kind === "guide").length,
      lessonsOnFiles: lessons.filter((lesson) => lesson.target?.startsWith("file:")).length,
      orderProblems: order,
    },
    citations: {
      total: citations.length,
      resolved: citations.filter((citation) => citation.ok).length,
      quoted: quoted.length,
      quotesResolved: quoted.filter((citation) => citation.ok).length,
      repliesWithCitations: new Set(citations.map((citation) => citation.reply)).size,
      replies: replies.length,
      probeCited: probe ? probeCitations.length > 0 : null,
      probeResolved: probe ? probeCitations.filter((citation) => citation.ok).length : null,
      problems: citations.filter((citation) => !citation.ok).map((citation) => `${citation.href.slice(0, 120)}: ${citation.problems.join("; ")}`),
    },
    firstTenMinutes: {
      firstReplySeconds: run.timings.firstReply ?? null,
      firstSourceSeconds: run.timings.firstSource ?? null,
      courseSeconds: run.timings.course ?? null,
      mentorTurnsBeforeFirstSource: run.timings.turnsBeforeFirstSource ?? null,
      questionsPerReply: questionCounts,
      maxQuestionsInOneReply: questionCounts.length ? Math.max(...questionCounts) : 0,
      nudges: run.nudges ?? 0,
    },
    failures: run.failures ?? [],
  };
}
