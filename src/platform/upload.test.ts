import { beforeEach, describe, expect, it, vi } from "vitest";

// A window connected to a host: commands go to the host, except the window's own.
const bridge = vi.hoisted(() => ({
  call: vi.fn(),
  uploaded: [] as string[],
}));
vi.mock("./transport", () => ({ REMOTE_CLIENT: true, transport: { call: bridge.call } }));

import { attachmentsFromFiles, attachmentsFromLocalPaths } from "../features/sessions/model/attachments";
import { nativeClipboardAttachments } from "./tauri/clipboard";
import { toHostPaths } from "./upload";

const HOST_DIR = "/host/tmp/loci-attachments/1-2";

beforeEach(() => {
  bridge.uploaded = [];
  bridge.call.mockReset().mockImplementation(async (command: string, args: Record<string, unknown>) => {
    switch (command) {
      case "remote_client_upload": {
        const path = args.path as string;
        if (path.includes("missing")) throw "No such file";
        bridge.uploaded.push(path);
        return `${HOST_DIR}/${path.slice(path.lastIndexOf("/") + 1)}`;
      }
      case "inspect_paths":
        return (args.paths as string[]).map((path) => ({ path, name: path.slice(path.lastIndexOf("/") + 1), size: 3, isDir: false }));
      case "read_file_base64":
        return "AAAA";
      case "clipboard_file_paths":
        return ["/Users/me/Desktop/diagram.png", "/Users/me/missing.pdf"];
      default:
        throw new Error(`unexpected ${command}`);
    }
  });
});

describe("files from this device in a window connected to a host", () => {
  it("attaches a dropped file by its path on the host, after sending it", async () => {
    const [file] = await attachmentsFromLocalPaths(["/Users/me/Desktop/paper.pdf"]);
    expect(bridge.uploaded).toEqual(["/Users/me/Desktop/paper.pdf"]);
    expect(file).toMatchObject({ name: "paper.pdf", path: `${HOST_DIR}/paper.pdf`, mimeType: "application/pdf" });
    expect(bridge.call).toHaveBeenCalledWith("inspect_paths", { paths: [`${HOST_DIR}/paper.pdf`] });
  });

  it("sends files copied in a file manager, leaving out one that is gone", async () => {
    const { files } = await nativeClipboardAttachments("");
    expect(bridge.uploaded).toEqual(["/Users/me/Desktop/diagram.png"]);
    expect(files.map((file) => file.path)).toEqual([`${HOST_DIR}/diagram.png`]);
    // An image is read on the host for the model, as a local one is here.
    expect(files[0].data).toBe("AAAA");
  });

  it("sends a dropped file that carries its path", async () => {
    const dropped = Object.assign(new File(["abc"], "notes.md"), { path: "/Users/me/notes.md" });
    const [file] = await attachmentsFromFiles([dropped]);
    expect(file.path).toBe(`${HOST_DIR}/notes.md`);
  });

  it("says why when nothing could be sent", async () => {
    await expect(toHostPaths(["/Users/me/missing.mov"])).rejects.toThrow("No such file");
    await expect(toHostPaths([])).resolves.toEqual([]);
  });
});
