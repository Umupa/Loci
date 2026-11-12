import { normalizeProjectPath } from "../../projects/model/recents";
import { isMarkdownBlockquotePosition } from "../../sessions/model/quoteDraft";
import type { HarnessId } from "../../sessions/model/session";
import { getHarness } from "../../../integrations/harness/core/registry";
import type { NativeCommand } from "../../../integrations/harness/core/nativeCommands";

export {
  rankSkills,
  replaceSlashToken,
  slashTokenAt,
  type SlashToken,
} from "./slashCommands";

/**
 * What the composer's slash menu offers: Loci's own commands (/new, /compact,
 * /draft, /btw) and the provider CLI's native ones. Skill files are not read.
 */
type SkillCommon = {
  name: string;
  description: string;
  invocation: string;
};

export type BuiltinSkill = SkillCommon & {
  kind: "builtin";
  scope: "builtin";
  source: "loci";
};

export type NativeSkill = NativeCommand & {
  kind: "native";
};

export type Skill = BuiltinSkill | NativeSkill;

const SKILL_TOKEN_RE =
  /(^|\s)\/([a-z0-9]+(?:-[a-z0-9]+)*(?::[a-z0-9]+(?:-[a-z0-9]+)*)?)(?=\s|$)/g;
const NATIVE_SKILL_TTL_MS = 30_000;
const NATIVE_SKILL_RETRY_MS = 5_000;

export type SkillCatalogContext = {
  harness: HarnessId;
  cwd: string;
  sessionId?: string;
};

type CatalogRequest = {
  generation: number;
  promise: Promise<Skill[]>;
};

type CatalogEntry = {
  cwd: string;
  skills: Skill[] | null;
  loadedAt: number;
  retryAt: number;
  generation: number;
  inFlight: CatalogRequest | null;
};

const catalogEntries = new Map<string, CatalogEntry>();

export function skillCatalogKey(context: SkillCatalogContext): string {
  const sessionScoped = !!getHarness(context.harness)?.commands?.subscribe;
  return `${context.harness}\0${normalizeProjectPath(context.cwd)}${sessionScoped && context.sessionId ? `\0${context.sessionId}` : ""}`;
}

export function hasNativeCommands(harness: HarnessId): boolean {
  return !!getHarness(harness)?.commands;
}

export function isNativeCommandPrompt(
  text: string,
  harness: HarnessId,
): boolean {
  return (
    getHarness(harness)?.commands?.rawSlashCommands === true &&
    /^\s*\/[^\s/\\]+(?=\s|$)/.test(text)
  );
}

/** A live update supersedes any cold probe already in flight. */
export function subscribeSkills(
  context: SkillCatalogContext,
  onSkills: (skills: Skill[]) => void,
): () => void {
  return (
    getHarness(context.harness)?.commands?.subscribe?.(context, (commands) => {
      const key = skillCatalogKey(context);
      const previous = catalogEntries.get(key);
      const skills: Skill[] = commands.map((command) => ({
        ...command,
        kind: "native",
      }));
      catalogEntries.set(key, {
        cwd: normalizeProjectPath(context.cwd),
        skills,
        loadedAt: Date.now(),
        retryAt: 0,
        generation: (previous?.generation ?? 0) + 1,
        inFlight: null,
      });
      onSkills(skills);
    }) ?? (() => undefined)
  );
}

export function peekSkills(context: SkillCatalogContext): Skill[] | null {
  return catalogEntries.get(skillCatalogKey(context))?.skills ?? null;
}

export function invalidateSkills(context?: { cwd: string }) {
  if (!context) {
    catalogEntries.clear();
    return;
  }
  const cwd = normalizeProjectPath(context.cwd);
  for (const entry of catalogEntries.values()) {
    if (entry.cwd !== cwd) continue;
    entry.generation += 1;
    entry.loadedAt = 0;
    entry.retryAt = 0;
    entry.inFlight = null;
  }
}

export function loadSkills(
  context: SkillCatalogContext,
  options?: { refresh?: boolean },
): Promise<Skill[]> {
  const normalized = {
    harness: context.harness,
    cwd: normalizeProjectPath(context.cwd),
    ...(context.sessionId ? { sessionId: context.sessionId } : {}),
  } satisfies SkillCatalogContext;
  const key = skillCatalogKey(normalized);
  let entry = catalogEntries.get(key);
  if (!entry) {
    entry = {
      cwd: normalized.cwd,
      skills: null,
      loadedAt: 0,
      retryAt: 0,
      generation: 0,
      inFlight: null,
    };
    catalogEntries.set(key, entry);
  }

  const now = Date.now();
  if (options?.refresh) {
    if (entry.inFlight?.generation === entry.generation) {
      return entry.inFlight.promise;
    }
    entry.generation += 1;
    entry.retryAt = 0;
    return startCatalogLoad(key, entry, normalized);
  }

  if (entry.inFlight?.generation === entry.generation) {
    return entry.inFlight.promise;
  }
  if (!hasNativeCommands(normalized.harness) && entry.skills) {
    return Promise.resolve(entry.skills);
  }
  if (
    hasNativeCommands(normalized.harness) &&
    entry.skills &&
    now - entry.loadedAt < NATIVE_SKILL_TTL_MS
  ) {
    return Promise.resolve(entry.skills);
  }
  if (hasNativeCommands(normalized.harness) && now < entry.retryAt) {
    return Promise.resolve(entry.skills ?? []);
  }
  return startCatalogLoad(key, entry, normalized);
}

function startCatalogLoad(
  key: string,
  entry: CatalogEntry,
  context: SkillCatalogContext,
): Promise<Skill[]> {
  const generation = entry.generation;
  const promise = loadCatalog(context)
    .then((skills) => {
      if (
        catalogEntries.get(key) !== entry ||
        entry.generation !== generation
      ) {
        return catalogEntries.get(key)?.skills ?? [];
      }
      entry.skills = skills;
      entry.loadedAt = Date.now();
      entry.retryAt = 0;
      return skills;
    })
    .catch(() => {
      if (
        catalogEntries.get(key) !== entry ||
        entry.generation !== generation
      ) {
        return catalogEntries.get(key)?.skills ?? [];
      }
      if (hasNativeCommands(context.harness)) {
        entry.retryAt = Date.now() + NATIVE_SKILL_RETRY_MS;
        return entry.skills ?? [];
      }
      entry.skills = [];
      entry.loadedAt = Date.now();
      return [];
    })
    .finally(() => {
      if (
        catalogEntries.get(key) === entry &&
        entry.generation === generation &&
        entry.inFlight?.promise === promise
      ) {
        entry.inFlight = null;
      }
    });
  entry.inFlight = { generation, promise };
  return promise;
}

async function loadCatalog(context: SkillCatalogContext): Promise<Skill[]> {
  const provider = getHarness(context.harness)?.commands;
  if (!provider) return [];
  const commands = await provider.discover(context);
  return commands.map((command): NativeSkill => ({
    kind: "native",
    ...command,
  }));
}

export type SkillTextPart = {
  text: string;
  skill: boolean;
};

/** Split composer text so known `/skill` tokens can be highlighted. */
export function skillTextParts(
  text: string,
  names: ReadonlySet<string>,
): SkillTextPart[] {
  if (!text) return [];
  if (names.size === 0) return [{ text, skill: false }];

  const parts: SkillTextPart[] = [];
  const push = (value: string, skill: boolean) => {
    if (!value) return;
    const last = parts[parts.length - 1];
    if (last && last.skill === skill) {
      last.text += value;
      return;
    }
    parts.push({ text: value, skill });
  };

  SKILL_TOKEN_RE.lastIndex = 0;
  let cursor = 0;
  let match: RegExpExecArray | null;
  while ((match = SKILL_TOKEN_RE.exec(text))) {
    const name = match[2];
    const lead = match[1] ?? "";
    const start = match.index + lead.length;
    if (
      !name ||
      !names.has(name) ||
      isMarkdownBlockquotePosition(text, start)
    ) {
      continue;
    }
    const end = start + 1 + name.length;
    push(text.slice(cursor, start), false);
    push(text.slice(start, end), true);
    cursor = end;
  }
  push(text.slice(cursor), false);
  return parts;
}

type SkillLoader = typeof loadSkills;

export function warmNativeSkills(
  context: SkillCatalogContext,
  load: SkillLoader = loadSkills,
): void {
  if (!hasNativeCommands(context.harness)) return;
  void load(context).catch(() => undefined);
}
