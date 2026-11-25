Pick for the panel `{{name}}` on your own. The person is not here and will not see this conversation; they will only see the panel change.

It follows: {{follow}}

The source `{{source}}` read these entries since you last looked, newest first:

{{entries}}

1. Keep only the entries the person would want to see, judged by what the panel follows. Most may not be worth it; keeping none is fine.
2. Run `"$LOCI" panel pick {{name}} --say "<one sentence>" <id> <id> ...` with the ids you keep. The sentence sums up what is new, what matters in **bold**; with no ids it says nothing new mattered. The app fills in each entry's title, link and time from the source; never write them yourself, and never `panel save` this panel.
3. In this session `loci` only reads and picks for this panel; if it says the panel was removed, stop.

When it is done, reply with one short line saying so.
