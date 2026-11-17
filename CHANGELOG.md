# Changelog

User-visible changes to the native app. The Tauri app's history is on `main`.

## Unreleased

- The native app opens to a start page: type a sentence to make a mentor, or drop a text file to add it to the library; browse mentors, lessons and items, with each lesson's sources and each item's citing lessons beside them. Warm-night look in light and dark, English and Chinese.
- Lessons and items open in a real reader: headings, lists, quotes, code blocks and tables, set in one column. It reopens where you stopped, keeps your place when the window is resized or the text is revised, and marks a lesson read once you reach its end.
- A mentor's page is a catalog tree that marks each lesson read, revised or not yet written, and shows what the mentor is doing while it works. Lessons the mentor revised highlight what changed since you last saw them; glossary terms are underlined where first used, with their definition on hover; at a lesson's end you can go on to the next one or ask the mentor to write it.
- Select a passage to highlight it, write a thought on it, or ask the lesson's mentor about it. Notes are kept in `notes/` files and survive restarts; the text keeps only the underline and a small mark, and the panel beside it lists the contents and every note in reading order, with answers streaming in. Notes whose passage is gone are listed as lost instead of pointing elsewhere.
- Talk with a mentor on its page: replies stream in, tool calls show what they ran and how it went, permission requests wait for your answer, and a running turn can be stopped.
