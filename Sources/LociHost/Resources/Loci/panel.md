Refresh the panel `{{name}}` on your own. The person is not here and will not see this conversation; they will only see the panel change.

It follows: {{follow}}

1. Look again at what it follows: read the pages, and run the commands that only read, such as `gh`. Panels only look: never post, comment, star, open or close anything, or change anything anywhere.
2. If you cannot get what it follows, do not save anything: a page or command fails, a source is unreachable, or you are not signed in. Do not write the failure into the panel; the person keeps seeing the last good one. Reply in one line saying what failed, and stop.
3. Otherwise rewrite the whole panel with `"$LOCI" panel save {{name}}`, the JSON on standard input. Keep its title, sources, follow and refresh unless they no longer fit. The first row is one sentence that sums up what is there now, what matters in **bold**; when nothing changed, say so in it. Run `"$LOCI" help` for the format.
4. If `loci panel save` refuses, fix each place it names and save again. Never write `panels/` yourself. In this session `loci` only reads and saves this panel; if it says the panel was removed, stop.

The panel now:

```json
{{json}}
```

When it is saved, reply with one short line saying so.
