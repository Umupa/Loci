# Mentor evaluation

How good a mentor is sets how fast someone learns in Loci. `npm run eval` measures it the same way every time, so a template change is judged against the last run instead of by feel. It drives real mentors through the [`loci` command line](cli.md) of a QA build, plays a scripted learner, collects what the mentor made and scores it in two layers: automatic checks and a rubric judged by a model.

Mentors run on **Antigravity (`agy`)** through Loci's own adapter, so runs stay comparable and Claude quota stays free. The judge is meant to be agy too, with a pinned model (`claude-opus-4-6-thinking`). For now `agy -p` (print mode, which the judge needs) fails Antigravity's region check on this machine, although Loci's Antigravity adapter answers. So the **recommended official run is mentors on agy, judge on grok** (`--provider agy --judge grok`) until `agy -p` works. Compare rubric scores only between runs that used the same judge.

## The official run (one command)

```sh
scripts/eval/baseline.sh
```

It builds the evaluation's QA bundle when missing (`Loci Eval QA`, identifier `com.loci.desktop.qa-eval`, never the installed app or another QA app), starts it, runs every scenario with the mentors on agy and the judge on grok (`LOCI_EVAL_JUDGE=agy scripts/eval/baseline.sh` once `agy -p` works), writes `eval/results/<timestamp>/summary.md`, then quits the app and deletes its data. Paste the summary into [Baseline](#baseline) below when it is meant to be the new reference.

Before it creates a mentor, the runner checks that the provider is available in that Loci (`models list`) and that the judge's CLI can answer in print mode. The mentors' own CLI is not probed directly: Loci's adapter can work where print mode does not, and a mentor that cannot answer shows up as a failed turn. When the judge's CLI refuses (Antigravity's `not currently available in your location`, not signed in, missing), the runner stops and says why: sign in (run the CLI once, interactively), use a proxy exit in a supported region system-wide, or pick another `--judge`.

## Running it by hand

```sh
scripts/eval/qa-app.sh build      # once: release bundle "Loci Eval QA"
scripts/eval/qa-app.sh up         # start it and wait for its command line
npm run eval -- --app com.loci.desktop.qa-eval --bin "$(scripts/eval/qa-app.sh bin)"
scripts/eval/qa-app.sh down       # quit it, delete its data dirs and the empty ~/Loci-Dev folders it made
```

| Option | Default | |
| --- | --- | --- |
| `--scenario ID` (repeatable) | all | one or more of `scripts/eval/scenarios/*.json` |
| `--app ID` / `LOCI_APP_ID` | — | the Loci to drive; `com.loci.desktop` is refused, another worker's QA app only when named with `--app` |
| `--bin PATH` / `LOCI_BIN` | `loci` | that build's `loci` executable |
| `--provider ID` | `agy` | the mentors' agent CLI |
| `--model ID` | the provider's default | the mentors' model (`grok:deepseek-flash`, ...) |
| `--judge ID` | same as `--provider` | `agy`, `grok`, `claude`, `codex` or `none`; `grok` uses grok's configured default model |
| `--judge-model ID` | `claude-opus-4-6-thinking` on agy | |
| `--judge-timeout MIN` | 11 | per judge call |
| `--max-turns N`, `--max-minutes N` | per scenario (8, 18) | caps on the scripted conversation |
| `--out DIR` | `eval/results/<timestamp>` | git-ignored |
| `--keep` | off | keep the mentors instead of deleting them |

**Mentors on grok.** A fresh QA app lists only grok's built-in models until a grok conversation is on screen, so `--model grok:deepseek-flash` fails with "Unknown model". Warm it up once after `up`: `"$BIN" mentors create --name warm --provider grok --workdir "$(mktemp -d)" --switch`, wait until `models list` shows `grok:deepseek-flash`, then `mentors delete warm --yes`.

**Antigravity's region check.** Later on 2026-11-01, Antigravity also started refusing this location inside Loci's adapter ("User location is not supported for the API use"). The runner records that reply as a finished turn, so check the conversation before trusting an agy run.

A run whose mentors are not on agy is labelled **Provisional, non-agy** in its summary; a run with agy mentors and another judge says which judge. It checks the harness and gives early findings; it is not the baseline. Node 22.18 or later is needed: the scorer imports the reader's TypeScript directly.

## What one scenario does

1. Creates a mentor from the scenario's template (`learning-guide` is Mentor, `repo-lens` is Lens) with `--provider agy --mode full-access` and a temporary working folder.
2. Sends the opening message and plays the **scripted learner** (`scripts/eval/learner.mjs`): each scenario has the learner's background and one- or two-sentence answers to what a mentor typically asks (goal, level, background, time, scope, depth, language, confirming a plan). The learner matches the mentor's questions by keyword (English and Chinese) and answers at most three topics per message; anything not covered gets "Your call — go ahead." When the mentor asks nothing and no course exists yet, it nudges once ("Go ahead and prepare the reading."). It stops when the mentor asks nothing and a course exists, or at the turn or time cap.
3. Asks one **probe**: a concrete question about the material, to test grounding and citations.
4. Collects through the CLI: the conversation (`mentors read`, and every full reply), sources and guides with their text and `sourceUrl` (`sources list/read`), courses (`courses list/read`), notes, the working folder's file list, and timings (first reply, first first-hand source, first course).
5. Scores it, asks the judge, deletes the mentor.

Everything lands in `eval/results/<timestamp>/<scenario>/` (`conversation.md`, `turns.json`, `learner.json` with why each answer was chosen, `sources/`, `courses/`, `score.json`, `judge.json` with the exact prompt, ...) and `summary.md` at the top.

## Scenarios

| ID | Template | The learner wants | First-party |
| --- | --- | --- | --- |
| `k8s-scheduling` | Mentor | how the Kubernetes scheduler picks a node | kubernetes.io, github.com/kubernetes* |
| `sqlite-wal` | Mentor | SQLite's WAL mode, format and locking | sqlite.org |
| `firecracker-paper` | Mentor | to read the Firecracker NSDI'20 paper | usenix.org, arxiv.org, the Firecracker repo and site, amazon.science |
| `tokio-scheduler` | Lens | Tokio's multi-thread scheduler | github.com/tokio-rs, docs.rs/tokio, tokio.rs |
| `cubesandbox-snapshot` | Lens | CubeSandbox's snapshot/restore path | github.com/TencentCloud |

Each file holds `opening`, `learner.background`, `learner.answers`, `firstPartyDomains` (a host suffix, or host and path prefix), `probe`, `expect.minLessons/maxLessons`, `maxTurns`, `maxMinutes` and `turnTimeoutSeconds`.

## Scoring

**Automatic checks** (`scripts/eval/score.mjs`). Sections and quotes are resolved with the reader's own code (`learning/model/textAnchor.ts`, `shared/lib/markdown/markdownSection.ts`, `shared/lib/appResourceLinks.ts`), so a citation that passes here is one the reader finds.

| Check | |
| --- | --- |
| First-party sources | share of first-hand sources whose `sourceUrl` is on the scenario's first-party domains; off-domain ones listed |
| Files read in place | first-hand files the course reads where they are: a cloned repository (`/repos/`), a downloaded paper (PDF). Lens reads code this way by design, and a PDF cannot be taken in as a source |
| Not verbatim | first-hand sources that read like a summary (phrases such as "in this guide we will", "key takeaways", 总结/本文将; very short); listed for the judge |
| Guides | how many guides the mentor wrote (kept apart from sources) |
| Lessons resolve | every lesson's document exists and its `section` matches a heading, or its file exists and `lines` are inside it |
| Course shape | courses, chapters, lessons (within the scenario's expected range), lessons on files and on guides, lessons reading one document backwards |
| Citations | `loci://source/…#section/quote`, `loci://file/…#L` and absolute-path links in replies: the target exists, the section is a heading, the quote is found, the lines are inside; whether the probe answer cites anything |
| First ten minutes | seconds to first reply, first first-hand source and first course; mentor turns before the first source; question marks per reply; nudges |
| Failures | timeouts, failed turns, a mentor asking for permission in full access |

**Rubric** (`scripts/eval/judge-prompt.md`, filled with the checks, sources, courses and transcript, run in print mode from an empty folder). 1–5 each with a one-line reason, plus the single change that would help most:

- **firstHand**: first-hand and verbatim, with addresses and versions.
- **courseStructure**: a progressive, complete path with precise anchors, not an overview.
- **grounding**: answers quote and link the sources, separate source from inference, are correct (probe weighted most).
- **firstTenMinutes**: reading quickly, few questions at a time.

## Baseline

No full official run yet. The full run below has mentors on grok, so it is **provisional**: it checks the harness and records findings for the template rewrite. One scenario, `k8s-scheduling`, was run the recommended official way (mentors on agy inside Loci, judge on grok) to show that route works. Run `scripts/eval/baseline.sh` for the full official baseline and replace this section with its summary.

Read the rubric scores with care. Grok's default model on this machine (`deepseek-flash`) is the only judge that ran, and it is lenient: it gave firecracker 5/5 for grounding although no reply has a clickable citation. Trust the automatic columns more than the rubric until the pinned agy judge runs.

### Template rewrite, before and after (2026-11-01)

The Mentor and Lens templates were rewritten from the findings below (English templates; at most one scoping question, then reading; verbatim sources pinned to a commit or version, own writing via `guides.write`; clickable anchors copied from the text; 6–12 lessons; Lens sends the course first and saves the project's own prose as sources; no quizzing unless asked). Templates after: `learning-guide` dc365f9635, `repo-lens` c2b43b3c5a.

**Provisional, non-agy.** The run was meant to have mentors on agy, but Antigravity now refuses this location in Loci's adapter too ("User location is not supported for the API use"), so both turns failed. The after run therefore has mentors on `grok:deepseek-flash` and grok as judge, the same setup as the provisional run below, which is the like-for-like "before". The k8s agy run is listed for reference only. The old tokio template was not re-run on agy.

| Scenario | Run | Questions before reading | First source | Course | Lessons | Citations ok (quoted ok) | Reply language | Sources (first-hand) | First-hand | Course | Grounding | First 10 min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| k8s-scheduling | before, agy (ref.) | 5 over 3 turns + nudge | 10.7m | 10.7m | 9 | 12/13 (2/3) | English | 1 | 4 | 4 | 4 | 2 |
| k8s-scheduling | before, grok | 2 | 5.8m | 5.8m | 21 | 2/2 (1/1) | English | 7 | 5 | 5 | 4 | 5 |
| k8s-scheduling | **after, grok** | **0** | **3.6m** | **3.6m** | **12** | **15/15 (3/3)** | English | 5, pinned to commits | 5 | 4 | **5** | 5 |
| tokio-scheduler | before, grok | 1 | — (no source) | 5.2m | 9 | 58/58 (—) | **Chinese** | 0 | 4 | 4 | 4 | 5 |
| tokio-scheduler | **after, grok** | **0** | **4.7m** | **4.7m** | **12** | 24/24 (—) | **English** | **3 (README, runtime and worker docs) at b499257** | 4 | **5** | 4 | 5 |

What changed, read from the artifacts:

- **Reading first.** k8s asked nothing (the opening was clear enough) and the first reply carried 5 sources, the course and four opened file lessons. Lens answered in one turn with sources and course.
- **Language.** All four replies are English (0 CJK characters); before, tokio and cubesandbox replied in Chinese.
- **Citations.** k8s: 15 links in both replies, 3 quoted, all resolve (before: 2 links). The probe answer quotes the KEP's Filter and PreFilter definitions and marks its tie-break claim as inference. Lens still cites code by line only (no `quote=`), all resolving.
- **Pinned.** Every source has a commit-pinned `sourceUrl` and a `version` (`b499257`, `docs dev-1.37, commit aebe074`, `k/enhancements commit a904b50, fetched 2026-11-01`); the Lens course is titled `tokio @ b499257`.
- **Course length.** 12 and 12 (before: 21 and 9). One order note in k8s (the extension-points lesson after PostFilter).
- **Lens course first.** The course and the brief arrive in the same turn, so "first reply" still includes the brief; the judge now asks to replace the brief lesson with a first-hand one.
- No summaries flagged as sources, no quiz before reading, no failures.

### Mentors on agy, judge on grok, one scenario (2026-11-01)

> Mentors on Antigravity inside Loci; rubric judged by `grok` because `agy -p` (print mode) fails Antigravity's region check here. Compare rubric scores only with runs judged the same way.

- App: `com.loci.desktop.qa-eval` 0.2.0 · commit `54a6b9a`
- Mentors: `agy` / `antigravity:gemini-3.8-flash-high`, mode `full-access`
- Judge: `grok`
- Templates: `learning-guide` cb9b3fe5b1, `repo-lens` b104bc3f78
- Limits: turns and minutes as each scenario sets

| Scenario | Sources (first-party) | Files in place | Guides | Lessons ok | Citations ok (quotes) | First source | Course | Max ?/reply | First-hand | Course | Grounding | First 10 min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| k8s-scheduling | 1 (100%) | 4 | 0 | 8/9 | 12/13 (2/3) | 10.7m | 10.7m | 2 | 4 | 4 | 4 | 2 |
| **mean** | | | | | | | | | **4** | **4** | **4** | **2** |

#### k8s-scheduling (learning-guide)

- Turns: 6 mentor replies; nudges 1; questions per reply 1, 2, 2, 0, 0; first reply 98s; stopped by learner done
- Sources: 1 first-hand, 1 first-party, 0 guides; files read in place 4 (4 in a cloned repo, 0 downloaded documents)
- Course: 1 course(s), 4 chapters, 9 lessons; 6 on files, 0 on guides
  - k8s-scheduler-internals/lab-custom-plugin: lines 1-24 outside 1-20
- Citations: 13 in 2/6 replies; probe cited (6 resolve)
  - loci://source/kep-624#section=Kep-624&quote=These%20plugins%20have%20two%20phases: section "Kep-624" not found
- First-hand 4/5 — KEP-624 is stored verbatim with its GitHub address and six lessons point into the kubernetes repo, but the KEP link is an unpinned master tree, the repo files carry no commit, and one lesson reads a lab README outside the upstream repo.
- Course 4/5 — Four chapters progress from the KEP architecture through scheduleOnePod, the assume cache, and the Filter/Score runtime to a reference plugin, with section and line anchors, but the lab lesson's 1-24 range overruns a 20-line file and no lesson covers selectHost, the queue, or preemption that the syllabus promised.
- Grounding 4/5 — Twelve of 13 citations resolve and the probe's PreFilter and Filter passages land, but the probe's Score column points at section=Kep-624 so its quote fails, and rows such as percentageOfNodesToScore and the 0-100 score range have no citation.
- First 10 min 2/5 — Reading started at 642 seconds after five mentor turns and five questions, two of which repeated the opening profile, and the learner had to say 'your call' and 'go ahead' before the course appeared.
- **Biggest fix:** Replace the three-round intake with one scoping question and ship the KEP-624 source and first code lesson in the opening reply, so the learner is reading within two minutes.

### Provisional, non-agy, all scenarios (2026-11-01)

Mentors on grok (`grok:deepseek-flash`, the only grok model this account can use), judge on grok. Run before two learner fixes. sqlite-wal's goal question went unanswered because the goal pattern did not match "What do you need to be able to do when we're done?". The rubric was re-judged after the first-hand rule was changed to count files read in place.

> **Provisional, non-agy.** Mentors ran on `grok`, judged by `grok`. Not the baseline: the baseline runs the mentors on Antigravity.

- App: `com.loci.desktop.qa-eval` 0.2.0 · commit `54a6b9a`
- Mentors: `grok` / `grok:deepseek-flash`, mode `full-access`
- Judge: `grok`
- Templates: `learning-guide` cb9b3fe5b1, `repo-lens` b104bc3f78
- Limits: turns and minutes as each scenario sets

| Scenario | Sources (first-party) | Files in place | Guides | Lessons ok | Citations ok (quotes) | First source | Course | Max ?/reply | First-hand | Course | Grounding | First 10 min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cubesandbox-snapshot | 0 (—) | 7 | 1 | 9/9 | 48/48 (—) | — | 9m | 0 | 4 | 5 | 4 | 3 |
| firecracker-paper | 0 (—) | 1 | 0 | 12/12 | — (—) | — | 110s | 1 | 5 | 5 | 5 | 5 |
| k8s-scheduling | 7 (100%) | 9 | 1 | 21/21 | 2/2 (1/1) | 5.8m | 5.8m | 1 | 5 | 5 | 4 | 5 |
| sqlite-wal | 5 (100%) | 9 | 0 | 37/37 | 5/6 (1/2) | 8.9m | 8.9m | 1 | 5 | 5 | 4 | 4 |
| tokio-scheduler | 0 (—) | 4 | 1 | 9/9 | 58/58 (—) | — | 5.2m | 1 | 4 | 4 | 4 | 5 |
| **mean** | | | | | | | | | **4.6** | **4.8** | **4.2** | **4.4** |

#### cubesandbox-snapshot (repo-lens)

- Turns: 2 mentor replies; nudges 0; questions per reply 0; first reply 9m; stopped by learner done
- Sources: 0 first-hand, 0 first-party, 1 guides; files read in place 7 (7 in a cloned repo, 0 downloaded documents)
- Course: 1 course(s), 2 chapters, 9 lessons; 8 on files, 1 on guides
- Citations: 48 in 2/2 replies; probe cited (34 resolve)
- First-hand 4/5 — Eight of nine lessons point at exact line ranges in files from TencentCloud/CubeSandbox at commit 6c2cd134 (seven repo files read in place), but the course opens with and saves one mentor-written guide and has no saved verbatim source.
- Course 5/5 — The nine lessons follow an ordered call chain from REST entry through Master, Cubelet, shim, VMM, reflink and restore, with all nine file anchors resolved and no order or lesson problems.
- Grounding 4/5 — Both replies cite heavily: 48 of 48 citations resolve and the probe has 34, but none includes a quoted passage and the probe answer does not explicitly separate inference from what the code shows.
- First 10 min 3/5 — The learner asked one question and faced no follow-up questions, but the first reply, guide and course arrived 542 seconds later, so reading began after a nine-minute wait rather than within a few minutes.
- **Biggest fix:** Send the course and first file lesson as soon as the repository is located, then write the long brief afterward, so the learner does not wait 542 seconds before reading.

#### firecracker-paper (learning-guide)

- Turns: 4 mentor replies; nudges 0; questions per reply 1, 1, 0; first reply 41s; stopped by learner done
- Sources: 0 first-hand, 0 first-party, 0 guides; files read in place 1 (0 in a cloned repo, 1 downloaded documents)
- Course: 1 course(s), 4 chapters, 12 lessons; 12 on files, 0 on guides
- Citations: 0 in 0/4 replies; probe **not cited**
- First-hand 5/5 — The learner reads the published USENIX PDF verbatim: the mentor's first message reports downloading `papers/firecracker-nsdi20.pdf` (14 pages, NSDI '20 pp. 419–434), and all 12 lessons are page ranges in that file, e.g. `abstract` pages [2,2] and `tail-network-scorecard` pages [13,13], traceable to where the paper was published.
- Course 5/5 — The course contains 12 lessons in four chapters that form a progressive path, from problem (abstract, Lambda's first isolation model, six criteria) through design (VMM decision, devices/API, side channels/jailer) to production (one process per VM, slots/economics) and measurements (boot method, boot results, memory/block IO, tail latency/scorecard), and each lesson anchors to a specific PDF page, e.g. `devices-api` p. 6 and `boot-method` p. 10; the mentor also maps it to a four-session daily plan covering pp. 419–431.
- Grounding 5/5 — The probe answer anchors each claim to a page (QEMU 1.4M lines/270 syscalls p. 422, crosvm fork p. 423, 3 MB vs 131 MB p. 428, jailer 24 syscalls/30 ioctls p. 424), separates its own inference into an explicit 'A correction to the premise' section, and the automatic checks show no citation problems; the gap is that no `loci://` links were emitted, so the learner cannot click through, but quotes and pages align with the paper's content.
- First 10 min 5/5 — The learner had the PDF and a 12-lesson course by 110 seconds (first reply at 41 s), the mentor asked exactly one question per message (max 1), and by the third mentor turn it had given a concrete reading assignment ('读前七页，最多四十五分钟', pp. 420–422) with a session-by-session plan.
- **Biggest fix:** Replace the Chinese responses with the English the learner uses, and add `loci://source/<id>#page=...` links to the page references so the learner can open the cited pages directly instead of hunting for them.

#### k8s-scheduling (learning-guide)

- Turns: 4 mentor replies; nudges 0; questions per reply 1, 1, 0; first reply 27s; stopped by learner done
- Sources: 7 first-hand, 7 first-party, 1 guides; files read in place 9 (9 in a cloned repo, 0 downloaded documents)
- Course: 1 course(s), 5 chapters, 21 lessons (outside the expected range); 13 on files, 0 on guides
- Citations: 2 in 2/4 replies; probe cited (1 resolve)
- First-hand 5/5 — Six official Kubernetes docs plus KEP-624 saved as sources with their published URLs, nine lessons read from cloned kubernetes and scheduler-plugins files at a dated master snapshot, and the one guide is explicitly labeled as the mentor's own reading map.
- Course 5/5 — Five chapters and 21 lessons run contract → one cycle → feasibility → ranking → plugin writing → failure diagnosis, every lesson anchored to a named doc section or an exact line range (e.g. schedule_one.go:66-143, fit.go:596-657), with no unresolved lessons or order problems.
- Grounding 4/5 — The probe's core Filter/Score distinction rests on a KEP quote that resolves and the mentor flags its tie-break claim as 'a code-level observation to confirm rather than doctrine', but only one citation per dense reply means most code claims (fit.go:280, algorithm.go:167) appear as bare text rather than links a learner can open.
- First 10 min 5/5 — First reply in 27s, one question per message, and the learner had sources plus the saved course at ~350s after two sharp questions (goal, plugin packaging), so reading began within minutes.
- **Biggest fix:** Have the mentor attach a resolvable `loci://` file-and-line link to every code claim in its answers, as it does for the one KEP quote, instead of citing bare `fit.go:280`-style text.

#### sqlite-wal (learning-guide)

- Turns: 4 mentor replies; nudges 0; questions per reply 1, 1, 0; first reply 45s; stopped by learner done
- Sources: 5 first-hand, 5 first-party, 0 guides; files read in place 9 (1 in a cloned repo, 0 downloaded documents)
- Course: 1 course(s), 7 chapters, 37 lessons (outside the expected range); 14 on files, 0 on guides
  - checkpoint-algorithm ("4.3. Checkpoint Algorithm") comes before reader-algorithm in sqlite-file-format
  - pragma-size-limit ("PRAGMA journal_size_limit") comes before pragma-autocheckpoint in sqlite-pragma
  - performance ("2.3. Performance Considerations") comes before large-wals in sqlite-wal
  - concurrency ("2.2. Concurrency") comes before performance in sqlite-wal
  - shm-impl ("7. Implementation Of Shared-Memory For The WAL-Index") comes before busy in sqlite-wal
  - readonly ("5. Read-Only Databases") comes before no-shm in sqlite-wal
- Citations: 6 in 2/4 replies; probe cited (4 resolve)
  - loci://source/sqlite-wal-format#section=2.1.2.%20The%20nBackfill%20field&quote=it%20is%20ok%20to%20reset%20the%20WAL%20i: quote not found: "it is ok to reset the WAL if there are no locks held on any of WAL_READ_LOCK(N"
- First-hand 5/5 — Five official sqlite.org specs saved verbatim at their published URLs plus nine files read in place from a cloned sqlite tree (wal.c at eight exact line ranges, four lab scripts); no guides, no summaries, no off-domain material — everything the learner reads is primary text.
- Course 5/5 — Seven chapters run three-files/contract → WAL bytes and checksums → reader snapshots → checkpointing → durability → recovery → operating, all 37 lessons resolve to named sections or tight line ranges (e.g. wal.c 160–248, 2312–2335), and the six order flags compare document section numbers rather than the course's deliberate teaching order.
- Grounding 4/5 — The probe anchors each claim to an exact wal.c range and separates spec from inference ("The spec is compact about it", "I built the violation"), but its load-bearing nBackfill quote fails to resolve in §2.1.2, and the first two replies assert mechanisms and lab numbers with no loci links.
- First 10 min 4/5 — One sharp end-state question with a recommended default, a 45-second first reply, and reading at turn two, but the first source and course only arrived at 535 seconds (~9 minutes), past the a-few-minutes bar.
- **Biggest fix:** Make every quote= an exact substring of the saved source before sending — the nBackfill quote carrying the probe's "both conditions" rule currently resolves to nothing.

#### tokio-scheduler (repo-lens)

- Turns: 2 mentor replies; nudges 0; questions per reply 1; first reply 5.2m; stopped by learner done
- Sources: 0 first-hand, 0 first-party, 1 guides; files read in place 4 (4 in a cloned repo, 0 downloaded documents)
- Course: 1 course(s), 2 chapters, 9 lessons; 8 on files, 1 on guides
- Citations: 58 in 2/2 replies; probe cited (18 resolve)
- First-hand 4/5 — Eight of nine lessons open verbatim repository files pinned to commit `b499257` (tokio 1.54.1) with exact line ranges, e.g. `worker.rs:571-646` and `queue.rs:470-525`; the only non-primary item is the mentor's own brief, and no official Tokio documentation was saved as a source.
- Course 4/5 — Two chapters and nine lessons run from the behavior contract (`runtime/mod.rs:346-390`) through the worker loop (`worker.rs:571-646`), task selection (`1084-1190`), local queue, overflow, stealing, and the LIFO slot (`704-762`) to parking, all 9/9 anchors resolved in order, but no lesson covers the spawn/wake path or the `block_in_place` core handoff the brief calls the easiest thing to get wrong.
- Grounding 4/5 — All 58 citations resolve (18 in the probe), and the probe traces stealing in four hops with file:line links and inline code from `worker.rs:605` and `1162` and `queue.rs:432` and `487`; no citation carries a quote payload (quoted: 0), so quote resolution was never exercised, and a few framing claims such as "nothing else moves tasks between workers" rest on the mentor's inference.
- First 10 min 5/5 — The session asked one question in total (max 1 per reply, 0 nudges) and the first reply, at 312 seconds, delivered the full course with all eight file lessons and the brief, so reading was possible about five minutes in.
- **Biggest fix:** Save the official Tokio documentation (runtime and `new_multi_thread` pages) as sources with their published URLs and open the course with one of them, so the learner starts on first-hand prose instead of a mentor-written brief.
