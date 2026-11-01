/** The Shiki language a file name names, by extension or bare file name. */
export function languageFromFile(file: string): string {
  const name = file.split(/[/\\]/).pop()!.toLowerCase();
  if (name === "dockerfile") return "dockerfile";
  if (name === "makefile") return "makefile";
  const extension = name.includes(".") ? name.slice(name.lastIndexOf(".") + 1) : name;
  const aliases: Record<string, string> = {
    py: "python",
    js: "javascript",
    mjs: "javascript",
    cjs: "javascript",
    jsx: "jsx",
    ts: "typescript",
    mts: "typescript",
    cts: "typescript",
    tsx: "tsx",
    rs: "rust",
    rb: "ruby",
    sh: "bash",
    zsh: "bash",
    yml: "yaml",
    md: "markdown",
    h: "c",
    cpp: "cpp",
    cc: "cpp",
    hpp: "cpp",
    cs: "csharp",
    kt: "kotlin",
    toml: "toml",
    json: "json",
    jsonc: "jsonc",
  };
  return aliases[extension] ?? extension;
}
