#!/usr/bin/env node
// CHANGELOG.md follows Keep a Changelog: an "## [Unreleased]" section that
// every user-visible change adds to, then one "## [x.y.z] - date" section per
// release. A release section is the GitHub release's notes and the text the
// in-app updater shows.
//
//   node scripts/changelog.mjs check            Unreleased lists something
//   node scripts/changelog.mjs notes 0.2.0      print that release's notes
//   node scripts/changelog.mjs release 0.2.0    turn Unreleased into 0.2.0
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = "https://github.com/Umupa/Loci";
const HEADING = /^## \[([^\]]+)\][^\n]*$/gm;

function sections(text) {
  const found = [...text.matchAll(HEADING)];
  return found.map((match, index) => {
    const start = match.index + match[0].length;
    const next = found[index + 1]?.index;
    const linksAt = text.slice(start).search(/^\[[^\]]+\]: /m);
    const end = next ?? (linksAt === -1 ? text.length : start + linksAt);
    return { name: match[1], heading: match.index, start, end, body: text.slice(start, end).trim() };
  });
}

function section(text, name) {
  return sections(text).find((entry) => entry.name === name);
}

export function unreleased(text) {
  return section(text, "Unreleased")?.body ?? "";
}

export function notes(text, version) {
  const entry = section(text, version);
  if (!entry) throw new Error(`CHANGELOG.md has no "## [${version}]" section.`);
  if (!entry.body) throw new Error(`The "## [${version}]" section of CHANGELOG.md is empty.`);
  return entry.body;
}

/** Turns Unreleased into the release `version` and starts a new, empty Unreleased. */
export function release(text, version, date) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`${version} is not a version like 0.2.0.`);
  if (section(text, version)) throw new Error(`CHANGELOG.md already has a "## [${version}]" section.`);
  const entry = section(text, "Unreleased");
  if (!entry) throw new Error('CHANGELOG.md has no "## [Unreleased]" section.');
  if (!entry.body) throw new Error("Unreleased in CHANGELOG.md lists nothing to release.");

  const previous = sections(text).find((other) => other.name !== "Unreleased")?.name;
  let next =
    text.slice(0, entry.heading) +
    `## [Unreleased]\n\n## [${version}] - ${date}\n\n${entry.body}\n\n` +
    text.slice(entry.end).replace(/^\n+/, "");

  const links = [
    `[Unreleased]: ${REPO}/compare/v${version}...HEAD`,
    previous
      ? `[${version}]: ${REPO}/compare/v${previous}...v${version}`
      : `[${version}]: ${REPO}/releases/tag/v${version}`,
  ].join("\n");
  next = /^\[Unreleased\]: .*$/m.test(next)
    ? next.replace(/^\[Unreleased\]: .*$/m, links)
    : `${next.trimEnd()}\n\n${links}\n`;
  return next;
}

function main([command, version]) {
  const path = join(dirname(fileURLToPath(import.meta.url)), "..", "CHANGELOG.md");
  const text = readFileSync(path, "utf8");
  switch (command) {
    case "check":
      if (!unreleased(text)) throw new Error("Unreleased in CHANGELOG.md lists nothing to release.");
      return;
    case "notes":
      process.stdout.write(`${notes(text, version)}\n`);
      return;
    case "release": {
      const date = new Date().toISOString().slice(0, 10);
      writeFileSync(path, release(text, version, date));
      return;
    }
    default:
      throw new Error("usage: changelog.mjs check | notes <version> | release <version>");
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
