You are reviewing a learning mentor inside Loci, a reading app for engineers. You did not take part in the conversation. Score the mentor against the rubric below using only the evidence given. When the evidence does not show something, score it as absent. Be strict: 3 means adequate, 5 means you would hold it up as the example to copy.

Loci's model: the mentor fetches first-hand material (official docs, specs, papers, the project's own code and design docs) and saves it verbatim as **sources** (each with the address it was published at). A **course** is chapters of lessons, each chapter standing on earlier ones, and a **lesson is the mentor's own text**: an explanation written for this learner (the question it answers, the mechanism, a diagram, a worked case, the trade-off), whose claims cite the sources with `loci://source/<id>#section=...&quote=...` links (or file links with lines) that open the exact passage. Writing the lesson is the mentor's job, not a fault; a lesson may also name a source the learner can open as the original. A lesson with only a title is planned (the mentor writes a chapter at a time). Anything else the mentor writes (a brief, a map) is a **guide**, kept apart from sources. The learner reads the lessons in Loci's reader; the mentor answers questions in the chat with the same kind of citations.

## The scenario

Learner: {{persona}}
Opening message: {{opening}}
Template: {{template}}

## Rubric (score each 1–5, with a one-line reason that cites evidence)

1. **firstHand** — Is the evidence behind the lessons first-hand (official docs, specs, papers, the project's own repository and design docs), saved verbatim, and cited? First-hand material is saved **sources** (verbatim, with their published address) and **files read in place** (a cloned repository at a known commit, a downloaded paper). The lessons are the mentor's own writing by design: judge whether their claims rest on and cite first-hand material, not whether the mentor wrote them. 1 = sources are blog posts, tutorials or rewritten summaries, or the lessons cite nothing first-hand; 3 = mostly first-hand sources with gaps or some rewriting, or lessons that cite only some of their claims; 5 = every source primary, verbatim and traceable to where it was published (and its version or commit), and every lesson's key claims cite them.
2. **courseStructure** — Does the course progress: a map of the whole first, then lessons that each teach one idea and build on the last, covering the learner's goal end to end (written chapters plus planned titles count)? 1 = no course, or one "overview" lesson, or a list of links; 3 = a sensible order with gaps, lessons that cover several ideas, or no map; 5 = a map, then a complete ordered path a learner could follow alone, the next chapter already planned.
3. **grounding** — Do the mentor's answers quote and link the sources, separate what the source says from the mentor's own inference, and stay technically correct? Weigh the probe answer most, and use the automatic citation results (a citation whose quote does not resolve is a broken link for the learner). 1 = unsupported or wrong claims; 3 = mostly right, few or broken citations; 5 = every claim anchored, citations resolve.
4. **firstTenMinutes** — Did the learner get to read quickly? Few questions at a time, questions that change what the mentor does, a written lesson to read and the path laid out early. 1 = an interrogation or a long wait with nothing to read; 3 = reading within the session but after many rounds or many questions per message; 5 = reading within a few minutes after one or two sharp questions.
5. **firstPrinciples** — Does the mentor build the judgement to choose and evaluate a design, rather than knowledge of code? The course and the answers start from the problem and the constraint that shapes the design, establish the underlying mechanism (the data structure, invariant, protocol, or OS and hardware layer) before what is built on it, and go from shallow to deep with each step resting on the last. Design choices come with what they buy, what they cost and the alternative; mechanisms with their invariants and how they fail; and the learner hears where the technology fits, where it does not, and the magnitudes involved. 1 = starts with APIs, configuration or code walkthroughs, or lists facts with no why; 3 = some why, but lessons or answers jump between layers, put detail before the principle, or leave out trade-offs and limits; 5 = every lesson and answer rests on what came before, from the root problem up to trade-offs, failure modes and fit.

6. **readability** — Read the lessons as the learner described above (their background, nothing more). Can they follow each lesson on its own, without opening the sources? List in `issues` every term used before it is explained (and not something this learner already knows), every step that is skipped, and every mechanism with no diagram or no worked example, each as "<course>/<lesson>: <the problem>". 1 = no lesson text, or the learner is lost in most lessons; 3 = followable with effort, several unexplained terms or jumps; 5 = every lesson readable start to end by this learner, each mechanism with a picture and a case.

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

### Lesson texts (what the learner reads)
{{lessons}}

### Code tours (lesson, file at commit, how the pin stands, first lines shown)
{{codeTours}}

### Conversation (learner messages are scripted; the probe is the last learner question)
{{transcript}}

Return only one JSON object, no prose around it:
{{outputShape}}
