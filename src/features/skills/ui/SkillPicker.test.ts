import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { SkillPicker } from "./SkillPicker";

import { COMPACT_COMMAND } from "../../sessions/model/compact";
import { SESSION_FOLDER_COMMAND } from "../../sessions/model/sessionFolderCommand";
import type { Skill } from "../model/skills";

describe("native command picker", () => {
  it("renders native commands and argument hints alongside Loci shortcuts", () => {
    const native: Skill[] = [{kind:"native",source:"codex",name:"workflow",invocation:"workflow",description:"Choose a workflow",inputHint:"<topic> [format]"},{kind:"native",source:"codex",name:"mcp",invocation:"codex:mcp",description:"List tools",subcommands:[{name:"list",usage:"list --all"}]}];
    const html = renderToStaticMarkup(
      createElement(SkillPicker, {
        skills: [
          SESSION_FOLDER_COMMAND,
          COMPACT_COMMAND,
          ...native,
        ],
        query: "",
        active: 0,
        creating: false,
        cwd: "/repo",
        onActive: vi.fn(),
        onPick: vi.fn(),
        onStartCreate: vi.fn(),
        onCancelCreate: vi.fn(),
        onCreate: vi.fn(),
      }),
    );


    expect(html).toContain("/compact");
    expect(html).toContain("/add-to-folder");
    expect(html).toContain("/workflow");
    expect(html).toContain("Choose a workflow");
    expect(html).toContain("&lt;topic&gt; [format]");
    expect(html).toContain("codex");
    expect(html).toContain("list --all");
  });
});
