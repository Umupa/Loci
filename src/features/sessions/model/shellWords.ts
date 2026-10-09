/** Conservatively parse one shell invocation; compound commands use the shell row. */
export function shellWords(command: string): string[] | undefined {
  const words: string[] = [];
  let word = "";
  let started = false;
  let quote: "'" | '"' | null = null;
  for (let index = 0; index < command.length; index += 1) {
    const char = command[index];
    if (quote === "'") {
      if (char === "'") quote = null;
      else word += char;
      continue;
    }
    if (char === "'" && !quote) {
      quote = "'";
      started = true;
      continue;
    }
    if (char === '"') {
      quote = quote === '"' ? null : '"';
      started = true;
      continue;
    }
    if (char === "\\") {
      const next = command[index + 1];
      if (!next) return undefined;
      // Preserve ordinary path separators, including quoted Windows paths.
      if (
        (quote === '"' && !/[\\"$`]/.test(next)) ||
        (!quote && !/[\s'"\\;&|<>()[\]{}$`#]/.test(next))
      ) {
        word += char;
      } else {
        word += next;
        index += 1;
      }
      started = true;
      continue;
    }
    if (char === "$" || char === "`") return undefined;
    if (!quote && /[\r\n;&|<>()[\]{}#]/.test(char)) return undefined;
    if (!quote && /\s/.test(char)) {
      if (started) words.push(word);
      word = "";
      started = false;
      continue;
    }
    word += char;
    started = true;
  }
  if (quote) return undefined;
  if (started) words.push(word);
  return words;
}
