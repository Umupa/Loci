import { transport } from "../transport";
import { slash } from "../../shared/lib/paths";


export function claudeShellCommands(
  providerSessionId: string,
  providerAccountId: string | undefined,
  toolIds: string[],
): Promise<Record<string, string>> {
  return transport.call<Record<string, string>>("claude_shell_commands", {
    providerSessionId,
    providerAccountId,
    toolIds,
  });
}


export type ProjectLocation = {
  path: string;
  identity: string;
};


export function resolveProjectLocation(
  path: string,
  identity?: string,
): Promise<ProjectLocation | null> {
  return transport.call<ProjectLocation | null>("resolve_project_location", {
    path,
    identity: identity ?? null,
  });
}


export type ProjectFile = {
  name: string;
  path: string;
  relative: string;
  isDir?: boolean;
};


export function createPath(
  parent: string,
  name: string,
  isDir: boolean,
): Promise<string> {
  return transport.call<string>("create_path", { parent, name, isDir }).then(slash);
}


export function deletePath(path: string): Promise<void> {
  return transport.call<void>("delete_path", { path });
}

export type FsEntry = {
  name: string;
  path: string;
  isDir: boolean;
  /** A dotfile, kept out of the Files tree unless hidden files are shown. */
  hidden: boolean;
};

/** Immediate children of a folder: folders first, then files, in natural order. */
export function listDir(path: string): Promise<FsEntry[]> {
  return transport.call<FsEntry[]>("list_dir", { path });
}

/** Every file and folder under a project, for finding by name or path. */
export function listProjectFiles(cwd: string): Promise<ProjectFile[]> {
  return transport.call<ProjectFile[]>("list_project_files", { cwd });
}

export type FileMtime = { path: string; mtimeMs: number | null };

export function statFiles(paths: string[]): Promise<FileMtime[]> {
  if (paths.length === 0) return Promise.resolve([]);
  return transport.call<FileMtime[]>("stat_files", { paths });
}

export function renamePath(path: string, name: string): Promise<string> {
  return transport.call<string>("rename_path", { path, name }).then(slash);
}

/** Move a file or folder to the system trash. */
export function trashPath(path: string): Promise<void> {
  return transport.call<void>("trash_path", { path });
}

export function copyPath(from: string, destParent: string): Promise<string> {
  return transport.call<string>("copy_path", { from, destParent }).then(slash);
}

export function movePath(from: string, destParent: string): Promise<string> {
  return transport.call<string>("move_path", { from, destParent }).then(slash);
}


/**
 * Paths for files copied in a file manager, on macOS, Linux and Windows.
 * Rejects when the clipboard cannot be read; an empty list means it holds no
 * files.
 */
export function clipboardFilePaths(): Promise<string[]> {
  return transport.call<string[]>("clipboard_file_paths").then((paths) =>
    paths.map(slash),
  );
}


/** Put the original file on the macOS clipboard, preserving its name and type. */
export function copyFileToClipboard(path: string): Promise<void> {
  return transport.call<void>("copy_file_to_clipboard", { path });
}


export function revealPath(path: string): Promise<void> {
  return transport.call<void>("reveal_path", { path });
}


export function openPathWithDefaultApp(path: string): Promise<void> {
  return transport.call<void>("open_path_with_default_app", { path });
}


export function homeDir(): Promise<string> {
  return transport.call<string>("home_dir");
}


export function readTextFile(path: string): Promise<string> {
  return transport.call<string>("read_text_file", { path });
}


/** Raw bytes for the image viewer. Arrives as an ArrayBuffer, not base64. */
/** Bytes of a document shown in a file pane; allows far larger files than a preview. */
export async function readDocumentFile(path: string): Promise<Uint8Array> {
  return new Uint8Array(await transport.call<ArrayBuffer>("read_document_file", { path }));
}

export async function readBinaryFile(path: string): Promise<Uint8Array> {
  const buffer = await transport.call<ArrayBuffer | string>("read_binary_file", {
    path,
  });
  // A connected machine sends the bytes as base64 inside its JSON reply.
  return typeof buffer === "string"
    ? Uint8Array.from(atob(buffer), (char) => char.charCodeAt(0))
    : new Uint8Array(buffer);
}


export type GeneratedImageAsset = {
  path: string;
  mimeType: string;
  size: number;
};


export function saveGeneratedImage(input: {
  data: string;
  name: string;
}): Promise<GeneratedImageAsset> {
  return transport.call<GeneratedImageAsset>("save_generated_image", input);
}


export function deleteGeneratedImages(paths: string[]): Promise<void> {
  return transport.call<void>("delete_generated_images", { paths });
}


export function writeTextFile(path: string, content: string): Promise<void> {
  return transport.call<void>("write_text_file", { path, content });
}


/** Last path segment, or `/` for the filesystem root. */
export function basename(path: string): string {
  const trimmed = slash(path).replace(/\/+$/, "") || "/";
  if (/^[A-Za-z]:$/.test(trimmed)) return trimmed;
  const parts = trimmed.split("/").filter(Boolean);
  return parts[parts.length - 1] ?? trimmed;
}
