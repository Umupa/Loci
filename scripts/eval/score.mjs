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

/** A lesson file's text: an absolute path, else a path inside one of the mentor's folders. */
export function lessonFileText(library, file) {
  if (!file) return null;
  if (file.startsWith("/") || /^[A-Za-z]:[\\/]/.test(file)) return library.readFile(file);
  for (const root of library.roots ?? []) {
    const text = library.readFile(`${root.replace(/\/+$/, "")}/${file}`);
    if (text != null) return text;
  }
  return library.readFile(file);
}

/**
 * Whether each lesson points at something real: a document in the library and
 * its section, or an existing file and a line range inside it. A pinned code
 * lesson is read at its commit through `readPinned` when the caller has it, so
 * the range is checked against the file as the lesson shows it.
 * @param {{ sources: Map<string, {body: string, kind?: string}>, readFile: (path: string) => string | null, roots?: string[], readPinned?: (path: string, commit: string) => string | null }} library
 */
export function checkLessons(course, library) {
  return lessonsOf(course).map((lesson) => {
    const result = { id: lesson.id, title: lesson.title, chapter: lesson.chapter, ok: true, problems: [], commit: lesson.commit ?? null, lines: lesson.lines ?? null };
    if (lesson.document) {
      const document = library.sources.get(lesson.document);
      result.target = `source:${lesson.document}`;
      result.kind = document?.kind;
      if (!document) { result.ok = false; result.problems.push(`no document ${lesson.document}`); }
      else if (lesson.section && !sectionResolves(document.body, lesson.section)) { result.ok = false; result.problems.push(`section "${lesson.section}" not found`); }
    } else if (lesson.file) {
      result.target = `file:${lesson.file}`;
      const text = lesson.commit && library.readPinned ? library.readPinned(lesson.file, lesson.commit) : lessonFileText(library, lesson.file);
      if (text == null) {
        result.ok = false;
        result.problems.push(lesson.commit ? `no file ${lesson.file} at commit ${lesson.commit}` : `no file ${lesson.file}`);
      } else if (lesson.lines) {
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

/** A lesson that reads code or a repository file: not a PDF, and either a line range, a pin, or a path under repos/. */
export function isCodeLesson(lesson) {
  if (!lesson?.file || lesson.pages) return false;
  if (/\.(pdf|epub|ps)$/i.test(lesson.file)) return false;
  return !!lesson.lines || !!lesson.commit || /(^|\/)repos\//.test(lesson.file);
}

/** How many parts a comparison lesson names; the course format has no such field until v0.4's compare lessons merge. */
function compareParts(lesson) {
  if (!Array.isArray(lesson?.compare)) return null;
  return lesson.compare.filter((part) => part && (part.file || part.document)).length;
}

/**
 * The v0.4 acceptance checks over one run: a learning path of 3–5 short
 * courses, pinned code tours whose ranges resolve at their commit, first-hand
 * sources with an address and a version, comparison lessons when the format
 * has them, and a mentor folder `library check` could read without problems.
 * @param {object} run collected run: { scenario, sources, courses, path, pins, libraryProblems, timings }
 * @param {{ readFile: (path: string) => string | null, roots: string[], readPinned?: (path: string, commit: string) => string | null }} files
 */
export function checkSandbox(run, files) {
  const scenario = run.scenario ?? {};
  const expect = scenario.expect ?? {};
  const problems = [];
  const library = { sources: new Map(run.sources.map((source) => [source.id, source])), readFile: files.readFile, roots: files.roots ?? [], readPinned: files.readPinned };

  // The learning path and the length of each course on it.
  const read = run.path ?? null;
  const path = read?.path ?? null;
  const pathCourses = Array.isArray(path?.courses) ? path.courses : [];
  const pathConfigured = Array.isArray(expect.pathCourses);
  const [minCourses, maxCourses] = expect.pathCourses ?? [3, 5];
  const [minLessons, maxLessons] = expect.lessonsPerCourse ?? [6, 12];
  const courseById = new Map(run.courses.map((course) => [course.id, course]));
  const pathRows = pathCourses.map((entry, index) => {
    const course = courseById.get(entry.id);
    const lessons = course ? lessonsOf(course).length : 0;
    const after = Array.isArray(entry.after) ? entry.after : [];
    const afterProblems = after.filter((before) => !pathCourses.slice(0, index).some((earlier) => earlier.id === before));
    return {
      id: entry.id, title: entry.title ?? course?.title ?? null, planned: entry.planned === true || !course,
      lessons, withinRange: lessons >= minLessons && lessons <= maxLessons, after, afterProblems,
    };
  });
  const pathExists = !!path && pathCourses.length > 0;
  const pathWithinRange = pathCourses.length >= minCourses && pathCourses.length <= maxCourses;
  if (read?.error) problems.push(`path read failed: ${read.error}`);
  if (pathConfigured && !pathExists) problems.push("no learning path (path read returns none)");
  if (pathConfigured && pathExists && !pathWithinRange) problems.push(`the path has ${pathCourses.length} courses; expected ${minCourses}–${maxCourses}`);
  for (const row of pathRows) {
    if (row.planned) problems.push(`${row.id} is on the path but has not been written`);
    else if (!row.withinRange) problems.push(`${row.id} has ${row.lessons} lessons; expected ${minLessons}–${maxLessons}`);
    for (const before of row.afterProblems) problems.push(`${row.id} lists ${before} after it in the path`);
  }
  // Without a path, a single course still has a length to meet.
  const courseLessons = run.courses.map((course) => {
    const count = lessonsOf(course).length;
    const low = expect.minLessons ?? 1;
    const high = expect.maxLessons ?? Infinity;
    return { id: course.id, title: course.title, lessons: count, withinRange: count >= low && count <= high };
  });
  if (!pathConfigured) for (const course of courseLessons) if (!course.withinRange) problems.push(`${course.id} has ${course.lessons} lessons; expected ${expect.minLessons ?? 1}–${expect.maxLessons ?? "∞"}`);

  // Code tours: every code lesson pinned, each pin current or moved, each range inside the pinned file.
  const checked = new Map();
  for (const course of run.courses) for (const lesson of checkLessons(course, library)) checked.set(`${course.id}\u0000${lesson.id}`, lesson);
  const codeLessons = run.courses.flatMap((course) => lessonsOf(course).filter(isCodeLesson).map((lesson) => ({ course: course.id, ...lesson })));
  const pins = run.pins && Array.isArray(run.pins.pins) ? run.pins.pins : null;
  const pinByLesson = new Map((pins ?? []).map((pin) => [`${pin.course}\u0000${pin.lesson}`, pin]));
  const codeRows = codeLessons.map((lesson) => {
    const key = `${lesson.course}\u0000${lesson.id}`;
    const result = checked.get(key);
    const pin = pinByLesson.get(key);
    return {
      course: lesson.course, lesson: lesson.id, title: lesson.title, file: lesson.file, commit: lesson.commit ?? null,
      lines: lesson.lines ?? null, pinned: !!lesson.commit, state: pin?.state ?? null,
      lineOk: lesson.lines ? !!result?.ok : null, problems: result?.problems ?? [],
    };
  });
  const unpinned = codeRows.filter((row) => !row.pinned);
  if (pins === null && codeRows.length) problems.push("code pins did not run");
  for (const row of unpinned) problems.push(`${row.course}/${row.lesson} is a code lesson without a commit`);
  for (const row of codeRows.filter((entry) => entry.pinned)) {
    if (row.state === null) problems.push(`${row.course}/${row.lesson} is pinned but code pins does not list it`);
    else if (row.state !== "current" && row.state !== "moved") problems.push(`${row.course}/${row.lesson} pin is ${row.state}`);
    for (const problem of row.problems) problems.push(`${row.course}/${row.lesson}: ${problem}`);
  }
  const pinsByState = Object.fromEntries(["current", "moved", "changed", "missing-commit", "missing-file", "no-repo", "error"].map((state) => [state, codeRows.filter((row) => row.state === state).length]));
  const pinnedLines = codeRows.filter((row) => row.pinned && row.lines);
  const minCode = expect.minCodeLessonsPerCourse ?? 0;
  const codePerCourse = run.courses.map((course) => {
    const own = codeRows.filter((row) => row.course === course.id);
    return { id: course.id, codeLessons: own.length, pinned: own.filter((row) => row.pinned).length, withinRange: own.length >= minCode };
  });
  const requiredCourses = pathConfigured ? new Set(pathCourses.map((entry) => entry.id)) : new Set(run.courses.map((course) => course.id));
  if (minCode > 0) for (const course of codePerCourse) if (requiredCourses.has(course.id) && !course.withinRange) problems.push(`${course.id} has ${course.codeLessons} code lessons; expected at least ${minCode}`);

  // First-hand sources: enough of them, each with an address and a version, early enough.
  const firstHand = run.sources.filter((source) => (source.kind ?? (source.sourceUrl ? "source" : "guide")) === "source");
  const minFirstHand = expect.minFirstHand ?? (scenario.id === "sandbox-path" ? 10 : 0);
  const missingAddress = firstHand.filter((source) => !source.sourceUrl).map((source) => source.id);
  const missingVersion = firstHand.filter((source) => !String(source.version ?? "").trim()).map((source) => source.id);
  const firstSourceSeconds = run.timings?.firstSource ?? null;
  const firstSourceWithin = expect.firstSourceWithinSeconds ?? null;
  if (firstHand.length < minFirstHand) problems.push(`${firstHand.length} first-hand sources; expected at least ${minFirstHand}`);
  for (const id of missingAddress) problems.push(`source ${id} has no sourceUrl`);
  for (const id of missingVersion) problems.push(`source ${id} has no version`);
  if (firstSourceWithin !== null && (firstSourceSeconds === null || firstSourceSeconds > firstSourceWithin))
    problems.push(firstSourceSeconds === null ? `no first-hand source within ${firstSourceWithin}s` : `first source after ${firstSourceSeconds}s; expected within ${firstSourceWithin}s`);

  // Comparison lessons, when this build's course format has them.
  const compareRows = run.courses.flatMap((course) => lessonsOf(course).map((lesson) => ({ course: course.id, lesson: lesson.id, title: lesson.title, parts: compareParts(lesson) })).filter((row) => row.parts !== null));
  const compareLessons = compareRows.filter((row) => row.parts >= 2);
  const compareExpected = expect.compareLessons ?? 0;
  const compareTolerated = compareExpected > 0 && compareRows.length === 0 && expect.tolerateMissingCompare === true;
  for (const row of compareRows.filter((entry) => entry.parts < 2)) problems.push(`${row.course}/${row.lesson} compares fewer than two parts`);
  if (compareExpected > 0 && compareLessons.length < compareExpected && !compareTolerated)
    problems.push(`${compareLessons.length} comparison lessons; expected at least ${compareExpected}`);

  // The library on disk: every source, guide and course is a file Loci could read.
  const libraryProblems = run.libraryProblems;
  if (!Array.isArray(libraryProblems)) problems.push("library check did not run");
  for (const problem of (libraryProblems ?? []).slice(0, 20)) problems.push(`library: ${problem.kind}/${problem.id}: ${problem.error}`);

  return {
    ok: problems.length === 0,
    problems,
    path: {
      checked: pathConfigured, exists: pathExists, file: read?.file ?? null,
      count: pathCourses.length, withinRange: pathWithinRange, expected: expect.pathCourses ?? null,
      title: path?.title ?? null, courses: pathRows,
      otherCourses: Array.isArray(read?.otherCourses) ? read.otherCourses.map((entry) => entry.id) : [],
    },
    courseLessons,
    code: {
      lessons: codeRows.length, pinned: codeRows.filter((row) => row.pinned).length, unpinned: unpinned.map((row) => `${row.course}/${row.lesson}`),
      pins: { listed: pins?.length ?? null, stale: run.pins?.stale ?? null, byState: pinsByState },
      lines: {
        checked: pinnedLines.length, resolved: pinnedLines.filter((row) => row.lineOk).length,
        withoutLines: codeRows.filter((row) => row.pinned && !row.lines).map((row) => `${row.course}/${row.lesson}`),
        problems: pinnedLines.filter((row) => !row.lineOk).map((row) => `${row.course}/${row.lesson}: ${row.problems.join("; ")}`),
      },
      perCourse: codePerCourse,
    },
    firstHand: {
      count: firstHand.length, min: minFirstHand, ok: firstHand.length >= minFirstHand,
      missingAddress, missingVersion,
      firstSourceSeconds, withinSeconds: firstSourceWithin,
    },
    compare: {
      lessons: compareLessons.map((row) => `${row.course}/${row.lesson}`), count: compareLessons.length,
      present: compareRows.length, expected: compareExpected, tolerated: compareTolerated,
      rows: compareRows,
    },
    library: {
      checked: Array.isArray(libraryProblems), problems: Array.isArray(libraryProblems) ? libraryProblems.length : null,
      list: (libraryProblems ?? []).slice(0, 20).map((problem) => `${problem.kind}/${problem.id}: ${problem.error}`),
    },
  };
}

/**
 * All automatic checks for one scenario.
 * @param {object} run what the runner collected: { scenario, sources: [{id,title,kind,sourceUrl,body}], courses: [{id,title,data}], turns: [{role,text,at}], timings, failures, nudges, path, pins, libraryProblems }
 * @param {{ readFile: (path: string) => string | null, roots: string[], readPinned?: (path: string, commit: string) => string | null }} files
 */
export function scoreRun(run, files) {
  const { scenario } = run;
  const sources = new Map(run.sources.map((source) => [source.id, source]));
  const library = { sources, readFile: files.readFile, roots: files.roots, readPinned: files.readPinned };
  const firstHand = run.sources.filter((source) => (source.kind ?? (source.sourceUrl ? "source" : "guide")) === "source");
  const guides = run.sources.filter((source) => !firstHand.includes(source));
  const firstParty = firstHand.filter((source) => isFirstParty(source.sourceUrl, scenario.firstPartyDomains));
  const suspicious = firstHand.map((source) => ({ id: source.id, reasons: summarySignals(source) })).filter((entry) => entry.reasons.length);

  const lessons = run.courses.flatMap((course) => checkLessons(course, library).map((lesson) => ({ course: course.id, ...lesson })));
  const order = run.courses.flatMap((course) => orderProblems(course, sources));
  // First-hand files read in place: a cloned repository, a downloaded paper.
  const fileLessons = lessons.filter((lesson) => lesson.ok && lesson.target?.startsWith("file:")).map((lesson) => lesson.target.slice(5));
  const inPlace = [...new Set(fileLessons)];
  const repoFiles = inPlace.filter((path) => /\/repos\//.test(path));
  const documents = inPlace.filter((path) => /\.(pdf|epub|ps)$/i.test(path));
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
      filesReadInPlace: inPlace.length,
      repoFiles: repoFiles.length,
      downloadedDocuments: documents.length,
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
    ...(scenario.acceptance === "v0.4" ? { sandbox: checkSandbox(run, files) } : {}),
  };
}
