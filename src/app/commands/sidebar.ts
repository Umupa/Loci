import { loadCourse, loadCourseSummaries } from "../../features/learning/model/course";
import { isLibrarySegment, LIBRARY_SEGMENTS, type LibrarySegment } from "../../features/mentor/model/libraryCourse";
import type { CommandContext } from "./context";
import { resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition } from "./registry";

const mentor = field("mentor", "string", "The mentor whose library to use, by id or name (a mentor's own turn: itself)", { max: 200 });

/** The segment the library shows: the one chosen, else Courses when there is a course to show, else Sources. */
async function shownSegment(ctx: CommandContext, agentId: string): Promise<LibrarySegment> {
  const state = ctx.library.current(agentId);
  if (state.segment) return state.segment;
  if (ctx.reader.current(agentId).page?.kind === "course") return "courses";
  const courses = await loadCourseSummaries();
  return courses.some((course) => course.agentId === agentId) ? "courses" : "sources";
}

export const sidebarCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "library.open",
    summary: "Show a mentor's library at one segment (courses, sources, notes, files), a course in its Courses segment, or a filter.",
    fields: [
      mentor,
      field("segment", "string", `One of ${LIBRARY_SEGMENTS.join(", ")}`),
      field("course", "string", "A course id to show in the Courses segment (it does not open the reader; reader open does)"),
      field("filter", "string", "Filter text for the segment's list; empty clears it (not for courses)", { max: 200 }),
      field("switch", "boolean", "Also bring the mentor on screen"),
    ],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      if (input.segment !== undefined && !isLibrarySegment(input.segment))
        throw new CommandError(`segment is one of ${LIBRARY_SEGMENTS.join(", ")}`, "usage");
      const course = input.course as string | undefined;
      if (course !== undefined && !await loadCourse(course, agent.id)) throw new CommandError(`No course ${course} for this mentor`, "not_found");
      // A course is shown in the Courses segment.
      const segment = (input.segment as LibrarySegment | undefined) ?? (course !== undefined ? "courses" : undefined);
      if (course !== undefined && segment !== "courses") throw new CommandError("--course goes with the courses segment", "usage");
      const filter = input.filter as string | undefined;
      // A filter belongs to the segment it is typed in, chosen or not.
      const target = segment ?? (filter !== undefined ? await shownSegment(ctx, agent.id) : undefined);
      if (filter !== undefined && target === "courses") throw new CommandError("The courses segment has no filter", "usage");
      ctx.library.open(agent.id, { ...(target ? { segment: target } : {}), ...(course !== undefined ? { course } : {}), ...(filter !== undefined ? { filter } : {}) });
      if (meta.caller === "external" && input.switch === true) await ctx.switchAgent(agent.id);
      return { mentor: agent.id, ...await libraryView(ctx, agent.id) };
    },
  },
  {
    name: "library.show",
    summary: "What a mentor's library shows now: whether it is visible, the segment, the course and the filter.",
    fields: [mentor],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      return { mentor: agent.id, ...await libraryView(ctx, agent.id) };
    },
  },
];

async function libraryView(ctx: CommandContext, agentId: string) {
  const state = ctx.library.current(agentId);
  const segment = await shownSegment(ctx, agentId);
  return {
    visible: state.visible, segment,
    ...(state.course ? { course: state.course } : {}),
    ...(state.filter && state.filter.segment === segment ? { filter: state.filter.text } : {}),
  };
}
