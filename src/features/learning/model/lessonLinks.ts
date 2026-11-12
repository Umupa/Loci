import { listAgents } from "../../agents/model/agent";
import { requestDocumentPlace } from "../../agents/model/documentPlace";
import { consumeFilePlace, peekFilePlace } from "../../files/model/filePlace";
import { lessonOfFile, lessonPlaceKey } from "./course";

/**
 * A link to a lesson's own file (a highlight's note, a citation of its text)
 * opens the lesson, not the bare Markdown file. The place the link asked for
 * moves to the lesson's text.
 */
export function lessonForFile(path: string): { agentId: string; courseId: string; lessonId: string } | null {
  for (const agent of listAgents()) {
    const lesson = lessonOfFile(agent.folder, path);
    if (!lesson) continue;
    const pending = peekFilePlace(path);
    if (pending) {
      consumeFilePlace(path, pending.token);
      if (pending.place.quote) requestDocumentPlace(agent.id, lessonPlaceKey(lesson.courseId, lesson.lessonId), { quote: pending.place.quote });
    }
    return { agentId: agent.id, ...lesson };
  }
  return null;
}
