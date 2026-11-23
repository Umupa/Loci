/// How Loci uses the `loci` command: what `loci help` prints, and the skill written for agent programs
/// that read skills. There is one text, so the two never disagree.
public enum ToolGuide {
  public static let text = """
    loci: read sources, search and add to the person's library, keep panels, and write courses, from inside Loci.

    Read items as files (../library/<folder>/). Search and add with loci.
    Run it as "$LOCI"; a plain `loci` on PATH may be another program.

      loci read <url>                  print all the text from a page, PDF, video with site subtitles or GitHub file
      loci repo <url> [--commit <sha>]  print the path to a read-only shallow checkout, a tab, and the full commit
                                       omit --commit for the latest commit on the default branch
      loci search <words>              full-text search; prints id, title and the matching sentence
      loci show <id>                   kind, title, authors, source, job, and the item's folder
      loci save <url>                  add a web page, paper, video or podcast episode; prints its id at once
      loci import <file> [--title T]   .md: an article you wrote, with you as its author
                                       video or audio file: copied into the library and transcribed
      loci wait <id>                   wait until the item is ready, or say why it is not
      loci panel save <name>           write a panel from the JSON on standard input; says what to fix if it cannot
      loci panel list                  every panel, and which files have problems
      loci panel show <name>           a panel's JSON as it is now
      loci course ask                  publish one question from JSON on standard input
      loci course goal                 update the goal from JSON on standard input
      loci course ready                mark the goal ready after the person confirms
      loci course source add <url> [--title T] [--kind paper|video|repository|page] [--commit SHA]
      loci course source read <id>     mark a source read
      loci course source list          print IDs, source links and pinned commits
      loci course plan                 save the lesson titles from JSON on standard input
      loci lesson write <id> <file.md> save or revise a lesson from UTF-8 Markdown
      loci course atlas <file.json>    save the whole course atlas from a JSON file
      loci mood here <word> <valence> <why>
                                       how this conversation makes you feel; valence 0 to 10
      loci mood base <word> <valence> <energy> <why>
                                       your mood overall; valence and energy 0 to 10
      loci sleep                       go to sleep
      loci wake                        wake up
      loci help                        this text

    Add --json to print the app's reply as it is.

    - Read fetches public sources anonymously. It uses site subtitles when a video provides them.
    - Read and repo keep sources in the app's cache for 14 days after their last use.
      For a repository citation, keep the full commit and link to that commit.
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

    The course and lesson commands work only during a turn in that course conversation. The session
    supplies the course ID. Course sources are links, with a full commit SHA for a repository.

    - ask: {"question":"…","options":[{"title":"…","detail":"…"},{"title":"…","detail":"…"}],"multiple":false}
      Put the recommended answer first. Give 2 to 4 options. "field" can name the goal line this fills.
      For a confirmation, use "confirmation":true with exactly two single choices: confirm, then revise.
    - goal: any of "title", "subtitle", "purpose", "focus", "known", "depth", "length". Omitted fields keep
      their values. Set the subtitle and length after confirmation, then run course ready.
    - plan: [{"id":"first-claim","title":"The claim this lesson teaches"}]. Use stable IDs of 1 to 64
      lowercase ASCII letters, digits or hyphens, starting and ending with a letter or digit. Keep the
      IDs, titles and relative order of lessons already written.
    - lesson write: give the ID from the plan and the path to the Markdown file. Writing again with
      the same ID updates that lesson. Use ordinary Markdown links to cite the exact place in a source.
    - atlas: {"gist":"…","blocks":[…]}, the whole atlas each time. Every text is one line; **bold** and
      `code` are the only marks. "lessons" lists lesson IDs from the plan; it and any field marked * may be
      left out. Blocks, by "kind":
      figures: {"figures":[{"title","value","note"*}]}, 2 to 5
      flow: {"title","lede"*,"lessons"*,"steps":[step],"aside"*}, 2 to 6 steps
        step: {"label"*,"title","points"*:[text, up to 4],"key"*:true for the step it turns on,"lessons"*}
      layers: {"title","lede"*,"lessons"*,"columns":[{"title","note"*,"layers":[{"text","marked"*}],"verdict"*}]}
        2 to 4 columns of 2 to 6 layers, top of the stack first; mark the layer each column is about
      cards: {"title","lede"*,"lessons"*,"cards":[{"label"*,"title","points":[1 to 5],"breaks"*,"lessons"*}]}, 1 to 4
      dive: {"lesson","title","lede"*,"steps":[step, 2 to 6],"keep"*:[up to 3]}, one per lesson
      table: {"title","lede"*,"lessons"*,"columns":[2 to 5],"rows":[{"label","cells":[text or null],"key"*,"lessons"*}]}
    """

  /// `SKILL.md` for agent programs that look for skills in their working folder.
  public static let skill = """
    ---
    name: loci
    description: Read sources, search the person's library and add links, articles you wrote, or media files to it, keep panels beside the main conversation, and write courses with the loci command.
    ---

    \(text)
    """
}
