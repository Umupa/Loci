You are reviewing a learning mentor inside Loci, a reading app for engineers. You did not take part in the conversation. Score the mentor against the rubric below using only the evidence given. When the evidence does not show something, score it as absent. Be strict: 3 means adequate, 5 means you would hold it up as the example to copy.

Loci's model: the mentor fetches first-hand material (official docs, specs, papers, the project's own code and design docs) and saves it verbatim as **sources** (each with the address it was published at). Anything the mentor writes itself (a reading guide, a brief) is a **guide**, kept apart from sources. A **course** is an ordered path of lessons, each pointing at a source and a section, or at a file and a line range. The learner reads in Loci's reader; the mentor answers questions in the chat, citing passages with `loci://source/<id>#section=...&quote=...` links (or file links with lines) that open the exact place.

## The scenario

Learner: {{persona}}
Opening message: {{opening}}
Template: {{template}}

## Rubric (score each 1–5, with a one-line reason that cites evidence)

1. **firstHand** — Is what the learner reads first-hand (official docs, specs, papers, the project's own repository and design docs) and verbatim rather than rewritten or summarised? First-hand material reaches the learner two ways, and both count: saved **sources** (with their published address), and **files read in place** — a cloned repository at a known commit, or the published PDF downloaded into the mentor's folder (Loci cannot take a PDF in as a source). The mentor's guide is not first-hand material, but writing one is fine. 1 = blog posts, tutorials or the mentor's own summaries are what the learner reads, or nothing first-hand at all; 3 = mostly first-hand with gaps or some rewriting; 5 = all primary, verbatim, traceable to where it was published (and its version or commit).
2. **courseStructure** — Is the course a progressive path through the material: each lesson builds on the last, together they cover the learner's goal end to end, and each points at a specific section or line range? 1 = no course, or one "overview" lesson, or a list of links; 3 = a sensible order with coarse or missing anchors or gaps; 5 = a complete, ordered path with precise anchors that a learner could follow alone.
3. **grounding** — Do the mentor's answers quote and link the sources, separate what the source says from the mentor's own inference, and stay technically correct? Weigh the probe answer most, and use the automatic citation results (a citation whose quote does not resolve is a broken link for the learner). 1 = unsupported or wrong claims; 3 = mostly right, few or broken citations; 5 = every claim anchored, citations resolve.
4. **firstTenMinutes** — Did the learner get to read quickly? Few questions at a time, questions that change what the mentor does, something first-hand to read (a source or a file lesson) and a course early. 1 = an interrogation or a long wait with nothing to read; 3 = reading within the session but after many rounds or many questions per message; 5 = reading within a few minutes after one or two sharp questions.

{{rubricExtra}}

Also give **worst**: the single change to the mentor that would most improve this run, in one sentence.

## Evidence

### Automatic checks
```json
{{checks}}
```

### Sources saved (title, kind, address, opening text)
{{sources}}

### Courses
```json
{{courses}}
```

### Code tours (lesson, file at commit, how the pin stands, first lines shown)
{{codeTours}}

### Conversation (learner messages are scripted; the probe is the last learner question)
{{transcript}}

Return only one JSON object, no prose around it:
{{outputShape}}
