import { REMOTE_CLIENT, transport } from "./transport";

/**
 * Files named by their path on this device (dropped, or copied in a file
 * manager), as paths the device holding the data can read: the same paths
 * here, or copies uploaded to the host in a window connected to one. One at
 * a time, so a large file is the only one in memory.
 *
 * A file that cannot be sent (gone, a folder, too large) is left out, as a
 * missing path is when attaching; when none could be sent, the first reason
 * is the error.
 */
export async function toHostPaths(localPaths: readonly string[]): Promise<string[]> {
  if (!REMOTE_CLIENT) return [...localPaths];
  const uploaded: string[] = [];
  let failure: unknown;
  for (const path of localPaths) {
    try {
      uploaded.push(await transport.call<string>("remote_client_upload", { path }));
    } catch (error) {
      failure ??= error;
    }
  }
  if (!uploaded.length && failure !== undefined) throw failure instanceof Error ? failure : new Error(String(failure));
  return uploaded;
}
