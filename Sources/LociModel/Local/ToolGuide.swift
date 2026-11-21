/// How Loci uses the `loci` command: what `loci help` prints, and the skill written for agent programs
/// that read skills. There is one text, so the two never disagree.
public enum ToolGuide {
  public static let text = """
    loci: search and add to the person's library, and keep panels, from inside Loci.

    Read items as files (../library/<folder>/). Search and add with loci.
    Run it as "$LOCI"; a plain `loci` on PATH may be another program.

      loci search <words>              full-text search; prints id, title and the matching sentence
      loci show <id>                   kind, title, authors, source, job, and the item's folder
      loci save <url>                  add a web page, paper, video or podcast episode; prints its id at once
      loci import <file> [--title T]   .md: an article you wrote, with you as its author
                                       video or audio file: copied into the library and transcribed
      loci wait <id>                   wait until the item is ready, or say why it is not
      loci panel save <name>           write a panel from the JSON on standard input; says what to fix if it cannot
      loci panel list                  every panel, and which files have problems
      loci panel show <name>           a panel's JSON as it is now
      loci help                        this text

    Add --json to print the app's reply as it is.

    - Save or import only what the person asked for, or what you said you would add.
    - After save or import, the item is in the library at once; its text comes when its job is done.
      Run `loci wait <id>` before you read it.
    - Write an article in workspace/ first, then import it. The library keeps its own copy.
    - Exit status 0 means it worked; 1 means it did not, and the message says why; 2 means the
      command was written wrong.

    A panel, as `loci panel save <name>` takes it. The name is short lowercase English: sandbox-radar.

      {
        "title": "沙箱雷达",
        "sources": ["github.com"],
        "follow": "盯着 CubeSandbox 的新版本和 PR",
        "refresh": { "every": "day", "at": "10:00" },
        "rows": [
          { "row": "sentence", "text": "**v0.8.0** 正式版发布，修了快照恢复。" },
          { "row": "cells", "cells": [{ "label": "最新版本", "value": "v0.8.0", "note": "8 天前" }] },
          { "row": "label", "text": "可以认领" },
          { "row": "list", "items": [{ "title": "#244 集成指南", "subtitle": "good first issue", "at": "昨天",
            "link": "https://github.com/x/y/issues/244", "ask": "帮我分析 #244" }] },
          { "row": "prominent", "title": "混元沙盒平台工程师", "subtitle": "深圳" },
          { "row": "bars", "bars": [{ "name": "e2b-dev/E2B", "fraction": 1, "value": "+1.2k" }] },
          { "row": "picture", "url": "https://example.com/a.png", "link": "https://example.com/a" }
        ]
      }

    - The first row is always a sentence that sums the panel up, what matters in **bold**.
    - cells: one to three, side by side. list items may also have "number" (a rank), "cover" (a picture
      link) and "progress" (0 to 1). bars: "fraction" is the bar's length, 0 to 1.
    - link, url and cover are http(s) links, or loci:// places in the library.
    - In place of "rows", "pages" turns pages: [{ "name": "CubeSandbox", "rows": [...] }, ...], each page
      named differently and starting with its own sentence.
    - refresh: { "every": "hour" }, { "every": "day", "at": "HH:mm" }, or { "every": "week", "weekday": 1,
      "at": "HH:mm" } where 1 is Sunday. Leave it out when nothing would change.
    - "sources" are the sites it reads, by domain; "follow" says what to look for each time it is refreshed.
    """

  /// `SKILL.md` for agent programs that look for skills in their working folder.
  public static let skill = """
    ---
    name: loci
    description: Search the person's library and add links, articles you wrote, or media files to it, and keep panels beside the main conversation, with the loci command.
    ---

    \(text)
    """
}
