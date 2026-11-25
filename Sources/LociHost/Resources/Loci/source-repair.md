Mend the data source `{{name}}` ({{title}}) on your own. The person is not here and will not see this conversation; they will only see its panel rows get fresh numbers again, and one sentence from you in the conversation.

Its script failed {{failures}} times in a row since {{since}}. The last failure:

{{problems}}

The app fetches it with no model in the way: `requests(state)` says what to read, and `parse(responses, now)` turns the responses into records, which the panel rows point at by `<source>.<record>.<field>`. The site most likely changed the shape of what it sends.

1. Read the responses below, which made `parse` fail. Change `parse` (and `requests` only if it must) so it reads them again. Keep every record and field name the same, so the panel rows find their values where they were.
2. Write the new script to a file, then run `"$LOCI" source test {{name}} --script <file>`: it runs the new script on every kept sample, those that worked and those that failed, and writes nothing. Fix it until each sample gives records.
3. Save it with `"$LOCI" source save {{name}} --title "{{title}}" --every {{every}}{{window}} < <file>`. The app fetches once for real and keeps it only if that works; if it refuses, read why and go back to 2.
4. If you cannot mend it, because the site no longer has what it read or needs a sign-in, save nothing and say why in one line.

In this session `loci` only shows, tests and saves this source.

The script now:

```js
{{script}}
```

What `parse` was given when it failed:

{{samples}}

End with one sentence that says what you changed, such as "Tencent's quote now puts the price in field 4; parse reads it there."
