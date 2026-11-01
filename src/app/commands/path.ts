import { loadCourseSummaries } from "../../features/learning/model/course";
import { loadCoursePath, parsePathInput, pathSteps, saveCoursePath } from "../../features/learning/model/coursePath";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition } from "./registry";

const failed = (cause: unknown) => new CommandError(cause instanceof Error ? cause.message : String(cause), "failed");

export const pathCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "path.read",
    summary: "The mentor's learning path (courses/_path.yaml): its courses in order with prerequisites and how far each is read, and the courses not on it.",
    fields: [mentorField()],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const read = await loadCoursePath(agent.id).catch((cause) => { throw failed(cause); });
      if (!read.path) return { mentor: agent.id, path: null, hint: "No path yet. Write one with path write: { title, courses: [{ id, after? }] }." };
      const courses = (await loadCourseSummaries()).filter((course) => course.agentId === agent.id);
      const { steps, others } = pathSteps(read.path, courses);
      return {
        mentor: agent.id, file: read.file, ...(read.error ? { error: read.error } : {}),
        ...(read.path.title ? { title: read.path.title } : {}),
        courses: steps.map((step) => ({ id: step.id, title: step.title, ...(step.planned ? { planned: true } : { read: step.read, lessons: step.total }),
          ...(step.after.length ? { after: step.after.map((item) => item.id) } : {}) })),
        otherCourses: others.map((course) => ({ id: course.id, title: course.title })),
      };
    },
  },
  {
    name: "path.write",
    summary: "Replace the mentor's learning path: courses in order (3-5 short courses of 6-12 lessons), each { id, after?, title? }; after names earlier courses and is shown, never enforced. A course may be planned before it is written (give it a title). --input path.json works well.",
    fields: [
      mentorField(),
      field("title", "string", "The path's title", { max: 200 }),
      field("courses", "json", "The courses in order: [\"id\", { \"id\": \"…\", \"after\": [\"…\"], \"title\": \"…\" }]", { required: true }),
    ],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      let path;
      try { path = parsePathInput({ ...(input.title !== undefined ? { title: input.title } : {}), courses: input.courses }); }
      catch (cause) { throw new CommandError(cause instanceof Error ? cause.message : String(cause), "usage"); }
      const saved = await saveCoursePath(agent.id, path).catch((cause) => { throw failed(cause); });
      return { mentor: agent.id, file: saved.file, courses: saved.path?.courses.length ?? 0, saved: true };
    },
  },
];
