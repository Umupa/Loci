import { CARD_FENCE } from "../model/cards";
import { CanvasCard, DocumentCard, MindmapCard, TodoCard } from "./cards/Cards";
import { CourseCard } from "../../learning/ui/CourseCard";
import { DiffCardFromSource } from "../../learning/ui/DiffCard";
import { convertFileSrc,invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
createContext,
isValidElement,
memo,
useCallback,
useContext,
useEffect,
useMemo,
useRef,
useState,
type ComponentProps,
type MouseEvent as ReactMouseEvent,
type ReactNode,
} from "react";
import { harden } from "rehype-harden";
import { createMathPlugin } from "@streamdown/math";
import "katex/dist/katex.min.css";
import {
Block,
CodeBlock,
Streamdown,
defaultRehypePlugins,
defaultRemarkPlugins,
useIsCodeFenceIncomplete,
type BlockProps,
type Components,
} from "streamdown";
import type { PluggableList } from "unified";
import type { Plugin } from "unified";
import type { Schema } from "hast-util-sanitize";
import type { Root, RootContent } from "hast";
import { useCodePlugin } from "../../../shared/hooks/useCodePlugin";
import { createLazyMermaidPlugin } from "../../../shared/lib/markdown/mermaidPlugin";
import {
displayPath,
isExtensionlessFileName,
resolveWorkspaceFileReference,
} from "../../../shared/lib/paths";
import { ContextMenu,type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { FileActionError } from "../../../shared/ui/FileActionError";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { ImageLightbox } from "../../../shared/ui/ImageLightbox";
import { ExcalidrawIcon } from "../../../shared/ui/ExcalidrawIcon";
import { File, MessageSquare } from "../../../shared/ui/icons";
import { parseAppResourceUrl, requestOpenAppResource } from "../../../shared/lib/appResourceLinks";

import { copyText } from "../../../platform/tauri/clipboard";
import type { OpenFileFn } from "../../files/model/filePlace";
import { openPathWithDefaultApp,readBinaryFile,revealPath } from "../../../platform/tauri/fs";
import { useColorScheme } from "../../../shared/hooks/useColorScheme";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { imageDataUrl } from "../../../shared/lib/filePreview";
import { remarkWorkspaceFileLinks } from "../../../shared/lib/markdown/markdownFileLinks";
import { localImagePath,remarkLocalImages } from "../../../shared/lib/markdown/markdownLocalImages";
import { isAtxHeadingLine } from "../../../shared/lib/markdown/markdownSource";
import { remarkDocumentSection } from "../../../shared/lib/markdown/markdownSection";

import { IS_MAC,IS_WIN } from "../../../platform/tauri/platform";
import { isNoteImagePath } from "../../notes";

import { rehypeHardBreaks } from "./hardBreaks";
import { MarkdownBlockquote, rehypeGithubAlerts } from "./MarkdownAlert";
import { rehypeWordFade,usePacedText,useWordFading } from "./wordFade";

const MERMAID_BASE_CONFIG = {
  startOnLoad: false,
  securityLevel: "strict",
  suppressErrorRendering: true,
} as const;

const mermaid = createLazyMermaidPlugin({
  config: {
    ...MERMAID_BASE_CONFIG,
    theme: "dark",
  },
});

const math = createMathPlugin({ singleDollarTextMath: true });

const [sanitizeMarkdown, sanitizeSchema] = defaultRehypePlugins.sanitize as [Plugin, Schema];

// Validate before harden normalizes URLs (e.g. a path containing ../).
function rehypeAppResourceLinks() {
  function validate(node: Root | RootContent) {
    if (node.type === "element" && node.tagName === "a") {
      const href = node.properties.href;
      if (typeof href === "string" && /^loci:/i.test(href) && !parseAppResourceUrl(href)) delete node.properties.href;
    }
    if ("children" in node) node.children.forEach(validate);
  }
  return validate;
}

const MARKDOWN_REHYPE_PLUGINS: PluggableList = [
  defaultRehypePlugins.raw,
  [sanitizeMarkdown, {
    ...sanitizeSchema,
    protocols: { ...sanitizeSchema.protocols, href: [...(sanitizeSchema.protocols?.href ?? []), "loci"] },
  }],
  rehypeAppResourceLinks,
  [
    harden,
    {
      // MarkdownImage remains the final allowlist. The wildcard lets app-owned
      // relative note URLs reach that component without changing link parsing.
      allowedImagePrefixes: ["*"],
      allowedLinkPrefixes: ["*"],
      allowedProtocols: ["loci:"],
      allowDataImages: true,
      imageBlockPolicy: "remove" as const,
    },
  ],
  rehypeGithubAlerts,
];



// A reply that streams renders its words as spans that fade in as they land.
const FADING_MARKDOWN_REHYPE_PLUGINS: PluggableList = [
  ...MARKDOWN_REHYPE_PLUGINS,
  rehypeWordFade,
];



type FileLinkMenu = {
  x: number;
  y: number;
  path: string;

};

const FileOpenContext = createContext<{
  cwd?: string;
  onOpenFile?: OpenFileFn;
  onFileContextMenu?: (
    event: ReactMouseEvent,
    path: string,
  ) => void;
  sourceUrl?: string;
}>({});

type SourceNode = { type: string; url?: string; children?: SourceNode[] };

/**
 * Make a source's relative addresses absolute against the page it was
 * published at. This runs before URL sanitizing, which would otherwise
 * resolve `../` away and lose where the path started.
 */
function remarkSourceAddresses({ sourceUrl }: { sourceUrl?: string }) {
  const visit = (node: SourceNode) => {
    if ((node.type === "link" || node.type === "image" || node.type === "definition") && node.url)
      node.url = sourceAddress(node.url, sourceUrl) ?? node.url;
    for (const child of node.children ?? []) visit(child);
  };
  return (root: SourceNode) => { if (sourceUrl) visit(root); };
}

/** An address in a source, made absolute against where the source was published. Only the web counts. */
function sourceAddress(address: string, sourceUrl: string | undefined): string | undefined {
  if (!sourceUrl || !address || address.startsWith("#")) return undefined;
  try {
    const url = new URL(address, sourceUrl);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : undefined;
  } catch {
    return undefined;
  }
}



const REVEAL_LABEL = IS_MAC
  ? "Reveal in Finder"
  : IS_WIN
    ? "Reveal in File Explorer"
    : "Open Containing Folder";

function fileLinkMenuItems(

  canCopyRelativePath: boolean,
): ContextMenuItem[] {
  return [
    { kind: "item", id: "open-default", label: "Open in Default App" },
    { kind: "item", id: "reveal", label: REVEAL_LABEL },
    { kind: "sep" },
    { kind: "item", id: "copy-path", label: "Copy Path" },
    ...(canCopyRelativePath
      ? [
          {
            kind: "item" as const,
            id: "copy-relative-path",
            label: "Copy Relative Path",
          },
        ]
      : []),
  ];
}

const LANGUAGE_FROM_EXT: Record<string, string> = {
  sh: "bash",
  zsh: "bash",
  py: "python",
  rb: "ruby",
  rs: "rust",
  ts: "typescript",
  js: "javascript",
  md: "markdown",
  yml: "yaml",
  cs: "csharp",
  cpp: "cpp",
  cc: "cpp",
  cxx: "cpp",
};

const LANGUAGE_FILE_NAMES: Record<string, string> = {
  bash: "code.sh",
  c: "code.c",
  cpp: "code.cpp",
  "c++": "code.cpp",
  csharp: "code.cs",
  css: "code.css",
  go: "code.go",
  html: "code.html",
  java: "code.java",
  javascript: "code.js",
  js: "code.js",
  jsx: "code.jsx",
  json: "code.json",
  markdown: "code.md",
  md: "code.md",
  php: "code.php",
  python: "code.py",
  py: "code.py",
  ruby: "code.rb",
  rust: "code.rs",
  rs: "code.rs",
  shell: "code.sh",
  sh: "code.sh",
  sql: "code.sql",
  swift: "code.swift",
  toml: "code.toml",
  ts: "code.ts",
  tsx: "code.tsx",
  typescript: "code.ts",
  xml: "code.xml",
  yaml: "code.yaml",
  yml: "code.yaml",
  zsh: "code.sh",
};

// Shiki (via Streamdown's CodeBlock) treats these as plaintext and renders no
// syntax colors at all, which is common in agent output (pseudocode, file
// trees, command output) fenced as `text` or left untagged. Falling back to
// the JS grammar for these still colors strings, numbers, and punctuation,
// matching what most agent-output fences actually look like.
const PLAINTEXT_FENCE_LANGUAGES = new Set(["text", "plaintext", "txt", ""]);

function highlightLanguageFor(language: string): string {
  return PLAINTEXT_FENCE_LANGUAGES.has(language.toLowerCase()) ? "js" : language;
}

type MarkdownLinkProps = ComponentProps<"a"> & { node?: unknown };

/** Keep source positions through ordinary links, inline paths and code citations. */
function openFileReference(file: NonNullable<ReturnType<typeof resolveWorkspaceFileReference>>, open: OpenFileFn) {
  const navigation = file.navigation;
  if (navigation && "page" in navigation) {
    open(file.path, { page: navigation.page });
    return;
  }
  const { line, endLine } = navigation ?? {};
  if (line !== undefined && Number.isSafeInteger(line) && line > 0) {
    open(file.path, { lines: [line, endLine !== undefined && Number.isSafeInteger(endLine) && endLine >= line ? endLine : line] });
  } else open(file.path);
}

function MarkdownLink({
  href,
  children,
  className,
  node: _node,
  onClick,
  onContextMenu,
  dir,
  ...props
}: MarkdownLinkProps) {

  const { cwd, onOpenFile, onFileContextMenu, sourceUrl } = useContext(FileOpenContext);
  const resource = href ? parseAppResourceUrl(href) : undefined;
  // A source's own links go where its page's links went, never to a local file.
  const file = href && !sourceUrl ? resolveWorkspaceFileReference(href, cwd) : undefined;
  if (href?.startsWith("loci:") && !resource) return <span dir={dir ?? "auto"}>{children}</span>;
  const ResourceIcon = resource?.kind === "canvas" ? ExcalidrawIcon : resource?.kind === "session" ? MessageSquare : File;
  return (
    <a
      href={href}
      className={`${resource ? "inline-flex max-w-full items-baseline gap-1 rounded bg-content/8 px-1.5 text-content hover:bg-content/12 hover:underline" : "markdown-link text-content underline decoration-accent/55 decoration-1 underline-offset-[3px] hover:decoration-accent"} ${className ?? ""}`}
      {...props}
      dir={dir ?? "auto"}
      onClick={(event) => {
        onClick?.(event);
        if (event.defaultPrevented) return;
        if (resource) {
          event.preventDefault();
          requestOpenAppResource(resource);
          return;
        }
        if (file && onOpenFile) {
          event.preventDefault();
          openFileReference(file, onOpenFile);
          return;
        }
        event.preventDefault();
        if (href && /^https?:\/\//i.test(href)) {
          void openUrl(href).catch((error) => {
            console.error("Failed to open web link:", error);
          });
        }
      }}
      onContextMenu={(event) => {
        onContextMenu?.(event);
        if (event.defaultPrevented || !file || !onFileContextMenu) return;
        onFileContextMenu(event, file.path);
      }}
    >
      {resource ? <ResourceIcon className="size-3.5 shrink-0 self-center" aria-hidden="true" /> : null}
      {children}
    </a>
  );
}

type MarkdownCodeProps = ComponentProps<"code"> & { node?: unknown };

function MarkdownCode({
  children,
  className,
  node,
  onContextMenu,
  ...props
}: MarkdownCodeProps) {
  const incomplete = useIsCodeFenceIncomplete();
  const block = Object.prototype.hasOwnProperty.call(props, "data-block");
  if (!block) {
    const text = textContent(children);
    const fileName = inlineFileName(text);
    const { cwd, onOpenFile, onFileContextMenu } = useContext(FileOpenContext);
    const file = fileName
      ? resolveWorkspaceFileReference(text, cwd)
      : undefined;
    const open =
      file && onOpenFile
        ? () => openFileReference(file, onOpenFile)
        : undefined;
    return (
      <code
        {...props}
        dir="ltr"
        className={`inline-flex items-center gap-1 rounded-md bg-content/8 px-1.5 min-h-6 max-w-full [overflow-wrap:anywhere] align-baseline font-mono text-[0.8em] text-content ${
          open ? "cursor-pointer hover:text-content hover:underline hover:decoration-accent" : ""
        } ${className ?? ""}`}
        role={open ? "link" : undefined}
        tabIndex={open ? 0 : undefined}
        onClick={open}
        onContextMenu={(event) => {
          onContextMenu?.(event);
          if (event.defaultPrevented || !file || !onFileContextMenu) return;
          onFileContextMenu(event, file.path);
        }}
        onKeyDown={
          open
            ? (event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  open();
                }
              }
            : undefined
        }
      >
        {fileName ? (
          <span aria-hidden="true">
            <FileTypeIcon name={fileName} isDir={false} size={14} />
          </span>
        ) : null}
        {children}
      </code>
    );
  }

  const meta = codeMeta(node);
  const fence = parseCodeFence(className, meta);
  if (fence.language.toLowerCase() === "mermaid") {
    return (
      <MermaidBlock code={textContent(children)} incomplete={incomplete} />
    );
  }
  // A fence Loci knows is drawn as its card rather than as code.
  const card = fence.language.toLowerCase();
  if (card === CARD_FENCE.document)
    return <DocumentCard source={textContent(children)} incomplete={!!incomplete} />;
  if (card === CARD_FENCE.course)
    return <CourseCard source={textContent(children)} incomplete={!!incomplete} />;
  if (card === CARD_FENCE.diff)
    return incomplete ? null : <DiffCardFromSource source={textContent(children)} />;
  // A half-written list or tree would only flicker as code, so it waits.
  if (card === CARD_FENCE.todo)
    return incomplete ? null : <TodoCard source={textContent(children)} />;
  if (card === CARD_FENCE.mindmap)
    return incomplete ? null : <MindmapCard source={textContent(children)} />;
  // The form is drawn where the conversation continues, not here.
  if (card === CARD_FENCE.canvas)
    return incomplete ? null : <CanvasCard source={textContent(children)} />;
  if (card === CARD_FENCE.question) return null;
  const iconName =
    fence.fileName ??
    (fence.language ? fileNameForLanguage(fence.language) : "");
  const lineNumbers = !/\bnoLineNumbers\b/.test(meta);
  const code = textContent(children);
  // highlightLanguageFor swaps the fence language for "js" so Shiki still
  // colors plaintext fences, but Streamdown's CodeBlock reuses that same
  // value for the header label. Without this, a `text` fence would show a
  // "js" header, and an untagged fence would gain a header it never had.
  // Render our own label with the original language instead, and hide
  // Streamdown's via CSS (see .markdown-code-fallback-label in index.css).
  const isPlaintextFallback = PLAINTEXT_FENCE_LANGUAGES.has(
    fence.language.toLowerCase(),
  );

  return (
    <div className="markdown-code-shell" dir="ltr">
      {iconName ? (
        <span className="markdown-code-icon" aria-hidden="true">
          <FileTypeIcon name={iconName} isDir={false} />
        </span>
      ) : null}
      {fence.filePath ? (
        <MarkdownCodePath path={fence.filePath} startLine={fence.startLine} endLine={fence.endLine} />
      ) : isPlaintextFallback ? (
        <span className="markdown-code-fallback-label">{fence.language}</span>
      ) : null}
      <CodeCopyButton code={code} />
      <CodeBlock
        className={className}
        code={code}
        isIncomplete={incomplete}
        language={highlightLanguageFor(fence.language)}
        lineNumbers={lineNumbers}
        startLine={fence.startLine}
      />
    </div>
  );
}

function CodeCopyButton({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    setCopied(false);
    return () => {
      if (timer.current != null) window.clearTimeout(timer.current);
    };
  }, [code]);

  return (
    <button
      type="button"
      title={copied ? "Copied" : "Copy code"}
      aria-label={copied ? "Copied" : "Copy code"}
      className={`markdown-code-copy ${copied ? "is-copied" : ""}`}
      onClick={() => {
        void copyText(code.replace(/\r?\n$/, "")).then(
          () => {
            setCopied(true);
            if (timer.current != null) window.clearTimeout(timer.current);
            timer.current = window.setTimeout(() => setCopied(false), 1500);
          },
          () => {},
        );
      }}
    >
      <svg viewBox="0 0 20 20" aria-hidden="true">
        <g className="markdown-code-copy-pages">
          <path d="M12 4H6a2 2 0 0 0-2 2v6" />
          <rect x="7" y="7" width="9" height="9" rx="1.5" />
        </g>
        <path
          className="markdown-code-copy-check"
          d="M4.5 10.5 8.2 14 15.5 6.5"
        />
      </svg>
    </button>
  );
}

type MarkdownImageProps = ComponentProps<"img"> & { node?: unknown };

/** The source is already approved and resolved; preview only after the browser decodes it. */
function PreviewableImage({ src, alt = "", onLoad, onError, onClick, onKeyDown, ...props }: Omit<MarkdownImageProps, "node">) {
  const imageRef = useRef<HTMLImageElement>(null);
  const [loadedSrc, setLoadedSrc] = useState<string>();
  const [linked, setLinked] = useState(false);
  const [preview, setPreview] = useState<string>();
  useEffect(() => {
    const image = imageRef.current;
    setLinked(!!image?.closest("a"));
    setLoadedSrc(typeof src === "string" && image?.complete && image.naturalWidth > 0 ? src : undefined);
    setPreview(undefined);
  }, [src]);
  const enabled = typeof src === "string" && loadedSrc === src && !linked;
  const open = (image: HTMLImageElement) => {
    if (!enabled || image.closest("a") || !image.complete || image.naturalWidth === 0) return;
    setPreview(image.currentSrc || src);
  };
  return <>
    <img
      {...props}
      ref={imageRef}
      src={src}
      alt={alt}
      role={enabled ? "button" : props.role}
      tabIndex={enabled ? 0 : props.tabIndex}
      aria-label={enabled ? `Preview image${alt ? `: ${alt}` : ""}` : props["aria-label"]}
      aria-haspopup={enabled ? "dialog" : undefined}
      className={`${props.className ?? ""}${enabled ? " cursor-zoom-in focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-ring" : ""}`}
      onLoad={(event) => { setLoadedSrc(event.currentTarget.naturalWidth > 0 && typeof src === "string" ? src : undefined); onLoad?.(event); }}
      onError={(event) => { setLoadedSrc(undefined); setPreview(undefined); onError?.(event); }}
      onClick={(event) => { onClick?.(event); if (!event.defaultPrevented) open(event.currentTarget); }}
      onKeyDown={(event) => {
        onKeyDown?.(event);
        if (event.defaultPrevented || !enabled || event.currentTarget.closest("a") || (event.key !== "Enter" && event.key !== " ")) return;
        event.preventDefault();
        open(event.currentTarget);
      }}
    />
    {preview ? <ImageLightbox src={preview} alt={alt} onClose={() => setPreview(undefined)} /> : null}
  </>;
}

const noteImageSrcCache = new Map<string, string>();

function NoteAssetImage({
  asset,
  alt,
  ...props
}: Omit<MarkdownImageProps, "src" | "node"> & { asset: string }) {
  const [src, setSrc] = useState(() => noteImageSrcCache.get(asset));

  useEffect(() => {
    if (src) return;
    let cancelled = false;
    void invoke<string>("notes_image_path", { asset })
      .then((path) => {
        const next = convertFileSrc(path);
        noteImageSrcCache.set(asset, next);
        if (!cancelled) setSrc(next);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [asset, src]);

  return (
    <PreviewableImage
      {...props}
      src={src}
      alt={alt ?? ""}
      data-note-image={asset}
      draggable={false}
      loading="lazy"
    />
  );
}

/** A picture stored beside the document, such as a figure saved with a reading. Anything that is not a picture stays blank. */
function LocalImage({
  path,
  alt,
  ...props
}: Omit<MarkdownImageProps, "src" | "node"> & { path: string }) {
  const [src, setSrc] = useState<string>();

  useEffect(() => {
    let cancelled = false;
    setSrc(undefined);
    void readBinaryFile(path)
      .then((bytes) => {
        const next = imageDataUrl(bytes);
        if (!cancelled && next) setSrc(next);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [path]);

  return (
    <PreviewableImage
      {...props}
      src={src}
      alt={alt ?? ""}
      data-local-image={path}
      draggable={false}
      loading="lazy"
    />
  );
}

function MarkdownImage({
  src,
  alt,
  node: _node,
  ...props
}: MarkdownImageProps) {
  const { sourceUrl } = useContext(FileOpenContext);
  const url = typeof src === "string" ? src.trim() : "";
  if (url.startsWith("data:image/")) {
    return <PreviewableImage {...props} src={url} alt={alt ?? ""} />;
  }
  // Only a source shows pictures from the web, from where it was published.
  // A reply never does: an address written into one could carry data out.
  const remote = sourceAddress(url, sourceUrl);
  if (remote?.startsWith("https:")) {
    return <PreviewableImage {...props} src={remote} alt={alt ?? ""} draggable={false} loading="lazy" referrerPolicy="no-referrer" />;
  }
  if (isNoteImagePath(url)) {
    return <NoteAssetImage key={url} {...props} asset={url} alt={alt} />;
  }
  const local = localImagePath(url);
  if (local) {
    return <LocalImage key={local} {...props} path={local} alt={alt} />;
  }

  return null;
}

const MARKDOWN_COMPONENTS = {
  a: MarkdownLink,
  blockquote: MarkdownBlockquote,
  code: MarkdownCode,
  img: MarkdownImage,
} satisfies Components;

/**
 * With dir="auto" Streamdown wraps each block in
 * `<div dir="..." style="display: contents">`. WebKit's triple-click then runs
 * past the block to the end of the reply, because a contents box gives the
 * selection no block boundary to stop at (#496). Keep the per-block direction
 * but put it on a real block box; index.css zeroes its margins so spacing still
 * comes from the block inside it.
 */
function DirectionalBlock({ dir, ...props }: BlockProps) {
  const block = <Block {...props} />;
  return dir ? (
    <div dir={dir} className="agent-markdown-block">
      {block}
    </div>
  ) : (
    block
  );
}

export const AgentMarkdown = memo(function AgentMarkdown({
  text,
  streaming,
  revealOnMount,
  className,
  cwd,
  imageCwd,
  onOpenFile,
  hardBreaks,
  wholeDocument = false,
  sourceUrl,
  section,
}: {
  text: string;
  streaming?: boolean;
  /** Pace newly arrived output even if it finished before its first paint. */
  revealOnMount?: boolean;
  className?: string;
  cwd?: string;
  /** Where pictures written as relative paths live, when that is not `cwd` (a note's own folder). */
  imageCwd?: string;
  onOpenFile?: OpenFileFn;

  /** Show a newline inside a block as a line break, as a document does (#591). */
  hardBreaks?: boolean;
  /** Keep reference definitions available across paragraphs in saved documents. */
  wholeDocument?: boolean;
  /** Where this text was published, when it is a source: its pictures and relative links resolve there. */
  sourceUrl?: string;
  /** Render this heading and its descendants from a saved document. */
  section?: string;
}) {
  const code = useCodePlugin();
  const plugins = useMemo(() => ({ code, mermaid, math }), [code]);
  const [fileMenu, setFileMenu] = useState<FileLinkMenu | null>(null);
  const [fileActionError, setFileActionError] = useState<string | null>(null);
  const onFileContextMenu = useCallback(
    (event: ReactMouseEvent, path: string,) => {
      event.preventDefault();
      event.stopPropagation();
      setFileMenu({ x: event.clientX, y: event.clientY, path });
    },
    [],
  );
  const fileOpen = useMemo(
    () => ({ cwd, onOpenFile, onFileContextMenu, sourceUrl }),
    [cwd, onOpenFile, onFileContextMenu, sourceUrl],
  );
  const remarkPlugins = useMemo<PluggableList>(
    () => [
      ...Object.values(defaultRemarkPlugins),
      [remarkSourceAddresses, { sourceUrl }],
      [remarkLocalImages, { cwd: imageCwd ?? cwd }],
      [remarkWorkspaceFileLinks, { cwd }],
      [remarkDocumentSection, { section }],
    ],
    [cwd, imageCwd, sourceUrl, section],
  );

  const paced = usePacedText(text, !!streaming, revealOnMount);
  const fading = useWordFading(!!streaming || paced.revealing);
  // Spans stay while words are fading so a word already on screen keeps its
  // element. Dropping one mid-fade would remount it and fade it again. Once
  // the fade is over they come off, or a finished reply would keep a span per
  // word for as long as this transcript stays mounted.
  const baseRehypePlugins = fading ? FADING_MARKDOWN_REHYPE_PLUGINS : MARKDOWN_REHYPE_PLUGINS;
  // Hard breaks go last, so nothing after them undoes them, and after the word
  // fade, whose word spans would otherwise hide the newlines from them.
  const rehypePlugins = useMemo(
    () =>
      hardBreaks ? [...baseRehypePlugins, rehypeHardBreaks] : baseRehypePlugins,
    [baseRehypePlugins, hardBreaks],
  );

  const onFileMenuPick = (id: string) => {
    if (!fileMenu) return;
    const path = fileMenu.path;
    setFileMenu(null);
    setFileActionError(null);



    let action: Promise<void>;
    switch (id) {
      case "open-default":
        action = openPathWithDefaultApp(path);
        break;
      case "reveal":
        action = revealPath(path);
        break;
      case "copy-path":
        action = copyText(path);
        break;
      case "copy-relative-path":
        action = copyText(displayPath(path, cwd));
        break;
      default:
        return;
    }
    void action.catch((error) => {
      console.error(`Failed to run file-link action ${id}:`, error);
      setFileActionError(
        `Could not ${id === "open-default" ? "open the file in its default app" : "complete the file action"}: ${String(error)}`,
      );
    });
  };

  return (
    <>
      <FileOpenContext.Provider value={fileOpen}>
        <>
          <Streamdown
            mode={wholeDocument ? "static" : "streaming"}
            // Streamdown keeps a parsed tree while the text is unchanged, so
            // the plugin swap has to remount it once the fade is over.
            key={JSON.stringify([fading, section])}
            BlockComponent={DirectionalBlock}
            className={`agent-markdown min-w-0 font-sans text-sm leading-6 ${fading ? "word-fading" : ""} ${className ?? ""}`}
            components={MARKDOWN_COMPONENTS}
            controls={false}
            dir="auto"
            isAnimating={!!streaming || paced.revealing}
            plugins={plugins}
            remarkPlugins={remarkPlugins}
            rehypePlugins={rehypePlugins}
          >
            {paced.text}
          </Streamdown>
          {fileMenu ? (
            <ContextMenu
              x={fileMenu.x}
              y={fileMenu.y}
              items={fileLinkMenuItems(!!cwd)}
              ariaLabel="File link actions"
              onPick={onFileMenuPick}
              onClose={() => setFileMenu(null)}
            />
          ) : null}
          {fileActionError ? (
            <FileActionError
              message={fileActionError}
              onDismiss={() => setFileActionError(null)}
            />
          ) : null}
        </>
      </FileOpenContext.Provider>
    </>
  );
});

export const MarkdownPreview = memo(function MarkdownPreview({
  text,
  streaming,
  cwd,
  onOpenFile,
  header,
  hardBreaks,
}: {
  text: string;
  streaming?: boolean;
  cwd?: string;
  onOpenFile?: OpenFileFn;
  header?: ReactNode;
  hardBreaks?: boolean;
}) {
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();

  return (
    <div
      ref={lockOverscroll}
      tabIndex={0}
      role="region"
      aria-label="Markdown preview"
      className="markdown-preview h-full overflow-y-auto overscroll-none [overflow-anchor:none]"
    >
      <div className="px-6 py-8">
        {header}
        <AgentMarkdown
          text={text}
          wholeDocument={!streaming}
          streaming={streaming}
          cwd={cwd}
          onOpenFile={onOpenFile}
          hardBreaks={hardBreaks}
        />
      </div>
    </div>
  );
});

export const MarkdownSource = memo(function MarkdownSource({
  text,
}: {
  text: string;
}) {
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();

  return (
    <div
      ref={lockOverscroll}
      tabIndex={0}
      role="region"
      aria-label="Markdown source"
      className="markdown-preview h-full overflow-y-auto overscroll-none [overflow-anchor:none]"
    >
      <pre className="min-h-full min-w-0 whitespace-pre-wrap wrap-break-word px-4 py-3 font-mono text-[13px] leading-5 text-content/85">
        <MarkdownSourceHighlight text={text} />
      </pre>
    </div>
  );
});

export function MarkdownSourceHighlight({ text }: { text: string }) {
  if (!text) return null;
  return (
    <>
      {text.split(/(\n)/).map((part, index) =>
        part === "\n" ? (
          "\n"
        ) : isAtxHeadingLine(part) ? (
          <span key={index} className="markdown-source-heading">
            {part}
          </span>
        ) : (
          <span key={index}>{part}</span>
        ),
      )}
    </>
  );
}

function MermaidBlock({
  code,
  incomplete,
}: {
  code: string;
  incomplete: boolean;
}) {
  const [svg, setSvg] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const [preview, setPreview] = useState<string | null>(null);
  const diagramRef = useRef<HTMLDivElement>(null);
  const colorScheme = useColorScheme();

  useEffect(() => {
    setPreview(null);
    if (incomplete) {
      setSvg(null);
      setFailed(false);
      return;
    }
    let cancelled = false;
    setSvg(null);
    setFailed(false);
    const id = `mermaid-${Math.abs(hashCode(code)).toString(36)}-${Date.now().toString(36)}`;
    void mermaid
      .getMermaid({
        ...MERMAID_BASE_CONFIG,
        theme: colorScheme === "light" ? "default" : "dark",
      })
      .render(id, code)
      .then((result) => {
        if (cancelled) return;
        setSvg(result.svg);
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [code, incomplete, colorScheme]);

  if (incomplete || failed) {
    return (
      <div className="markdown-code-shell" dir="ltr">
        <span className="markdown-code-icon" aria-hidden="true">
          <FileTypeIcon name="diagram.mmd" isDir={false} />
        </span>
        <CodeCopyButton code={code} />
        <CodeBlock
          code={code}
          isIncomplete={incomplete}
          language="mermaid"
          lineNumbers={false}
        />
      </div>
    );
  }

  if (!svg) {
    return (
      <div className="h-32 animate-pulse rounded-[10px] border border-content/10 bg-content/6" />
    );
  }

  const openPreview = () => {
    const rendered = diagramRef.current?.querySelector("svg");
    if (!rendered) return;
    const image = rendered.cloneNode(true) as SVGSVGElement;
    const { width, height } = rendered.viewBox.baseVal;
    // Mermaid's responsive width has no intrinsic image size. Preserve the
    // viewBox dimensions so the shared image viewer can fit the full diagram.
    if (width > 0 && height > 0) {
      image.setAttribute("width", String(width));
      image.setAttribute("height", String(height));
      image.style.removeProperty("width");
      image.style.removeProperty("height");
      image.style.removeProperty("max-width");
    }
    image.style.backgroundColor = getComputedStyle(document.documentElement).getPropertyValue("--color-background-base").trim();
    setPreview(`data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(image))}`);
  };

  return <>
    <div
      ref={diagramRef}
      role="button"
      tabIndex={0}
      aria-label="Open Mermaid diagram full screen"
      title="Open Mermaid diagram full screen"
      className="mermaid-block cursor-zoom-in overflow-x-auto rounded-[10px] border border-content/10 bg-content/6 p-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent-ring"
      data-streamdown="mermaid-block"
      dir="ltr"
      onClick={(event) => {
        if (event.target instanceof Element && event.target.closest("a")) return;
        event.stopPropagation();
        openPreview();
      }}
      onKeyDown={(event) => {
        if (event.target !== event.currentTarget || (event.key !== "Enter" && event.key !== " ")) return;
        event.preventDefault();
        event.stopPropagation();
        openPreview();
      }}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
    {preview ? <ImageLightbox src={preview} alt="Mermaid diagram" onClose={() => setPreview(null)} /> : null}
  </>;
}

function hashCode(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash << 5) - hash + value.charCodeAt(i);
    hash |= 0;
  }
  return hash;
}

function codeMeta(node: unknown): string {
  if (!node || typeof node !== "object" || !("properties" in node)) return "";
  const properties = node.properties;
  if (
    !properties ||
    typeof properties !== "object" ||
    !("metastring" in properties)
  ) {
    return "";
  }
  return typeof properties.metastring === "string" ? properties.metastring : "";
}

function textContent(value: ReactNode): string {
  if (typeof value === "string" || typeof value === "number")
    return String(value);
  if (Array.isArray(value)) return value.map(textContent).join("");
  if (isValidElement<{ children?: ReactNode }>(value)) {
    return textContent(value.props.children);
  }
  return "";
}

function parseCodeFence(
  className: string | undefined,
  meta: string,
): {
  language: string;
  startLine?: number;
  endLine?: number;
  fileName?: string;
  filePath?: string;
} {
  const raw = className?.match(/\blanguage-([^\s]+)/)?.[1] ?? "";
  const metaStart = meta.match(/\bstartLine=(\d+)/);
  const metaStartLine = metaStart ? Number(metaStart[1]) : undefined;

  const citation = raw.match(/^(\d+):(\d+):(.+)$/);
  if (citation) {
    const filePath = citation[3];
    const fileName = filePath.split(/[/\\]/).filter(Boolean).pop() ?? filePath;
    return {
      language: languageFromFileName(fileName),
      startLine: Number(citation[1]),
      endLine: Number(citation[2]),
      fileName,
      filePath,
    };
  }

  if (/[/\\]/.test(raw)) {
    const fileName = raw.split(/[/\\]/).filter(Boolean).pop() ?? raw;
    return {
      language: languageFromFileName(fileName),
      startLine: metaStartLine,
      fileName,
      filePath: raw,
    };
  }

  return { language: raw, startLine: metaStartLine };
}

function MarkdownCodePath({
  path,
  startLine,
  endLine,
}: {
  path: string;
  startLine?: number;
  endLine?: number;
}) {
  const { cwd, onOpenFile, onFileContextMenu } = useContext(FileOpenContext);
  const file = resolveWorkspaceFileReference(path, cwd);
  if (!file || !onOpenFile) {
    return <span className="markdown-code-path">{path}</span>;
  }

  return (
    <button
      type="button"
      className="markdown-code-path markdown-code-path-link"
      title={file.path}
      onClick={() => openFileReference({ ...file, navigation: startLine === undefined ? file.navigation : { line: startLine, endLine } }, onOpenFile)}
      onContextMenu={(event) =>
        onFileContextMenu?.(event, file.path)
      }
    >
      {path}
    </button>
  );
}

function languageFromFileName(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower === "dockerfile") return "dockerfile";
  if (lower === "makefile") return "makefile";
  const ext = lower.includes(".")
    ? lower.slice(lower.lastIndexOf(".") + 1)
    : lower;
  return LANGUAGE_FROM_EXT[ext] ?? ext;
}

function fileNameForLanguage(language: string): string {
  const key = language.toLowerCase();
  return LANGUAGE_FILE_NAMES[key] ?? `code.${key}`;
}

function inlineFileName(value: string): string | undefined {
  const text = value.trim();
  if (!text || text.length > 240 || /\s/.test(text)) return undefined;

  const withoutLocation = text.replace(
    /(?::\d+(?::\d+)?|#L\d+(?:-L?\d+)?|#p[1-9]\d{0,5})$/,
    "",
  );
  const fileName = withoutLocation.split(/[/\\]/).filter(Boolean).pop();
  if (!fileName || !/^[\w%@+().-]+$/.test(fileName)) return undefined;

  if (isExtensionlessFileName(fileName)) {
    return fileName;
  }

  const extension = fileName.includes(".")
    ? fileName.split(".").pop()
    : undefined;
  return extension && /^[a-z][a-z0-9+-]{0,11}$/i.test(extension)
    ? fileName
    : undefined;
}
