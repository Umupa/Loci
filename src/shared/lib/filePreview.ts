
/**
 * Identify image bytes by their magic number rather than trusting the name.
 *
 * The viewer builds a blob URL, and a blob's MIME decides how the webview
 * treats it. Sniffing means an HTML file named `logo.png` fails to match and
 * lands on the unsupported card instead of becoming a same-origin document.
 */
export function sniffImageMime(bytes: Uint8Array): string | null {
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return "image/png";
  }
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (startsWith(bytes, [0x47, 0x49, 0x46, 0x38])) return "image/gif";
  if (startsWith(bytes, [0x42, 0x4d])) return "image/bmp";
  if (startsWith(bytes, [0x00, 0x00, 0x01, 0x00])) return "image/x-icon";
  // RIFF....WEBP — the four size bytes at offset 4 are skipped.
  if (
    startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
    startsWith(bytes.subarray(8), [0x57, 0x45, 0x42, 0x50])
  ) {
    return "image/webp";
  }
  // ....ftyp{avif,avis} — an ISO base media box, shared with HEIF and MP4.
  if (startsWith(bytes.subarray(4), [0x66, 0x74, 0x79, 0x70])) {
    const brand = String.fromCharCode(...bytes.subarray(8, 12));
    if (brand === "avif" || brand === "avis") return "image/avif";
  }
  return null;
}

/** The largest picture shown inline in a document. */
const MAX_INLINE_IMAGE_BYTES = 8 * 1024 * 1024;

function looksLikeSvg(bytes: Uint8Array): boolean {
  const head = new TextDecoder().decode(bytes.subarray(0, 2048)).replace(/^\uFEFF/, "");
  return /^\s*(?:<\?xml[^>]*\?>\s*)?(?:<!--[\s\S]*?-->\s*)*(?:<!DOCTYPE[^>]*>\s*)?<svg[\s>]/i.test(head);
}

/**
 * A `data:` URL for picture bytes, to show inline in a document. An SVG is
 * recognised by its opening markup: as the source of an `<img>` it draws but
 * cannot run scripts, the same as a `data:` picture written in the document.
 */
export function imageDataUrl(bytes: Uint8Array): string | null {
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_INLINE_IMAGE_BYTES) return null;
  const mime = sniffImageMime(bytes) ?? (looksLikeSvg(bytes) ? "image/svg+xml" : null);
  if (!mime) return null;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  return `data:${mime};base64,${btoa(binary)}`;
}

/** Byte count for the viewer footer, in the units a file manager would show. */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let size = bytes / 1024;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size < 10 ? size.toFixed(1) : Math.round(size)} ${units[unit]}`;
}

function startsWith(bytes: Uint8Array, magic: number[]): boolean {
  if (bytes.length < magic.length) return false;
  return magic.every((byte, index) => bytes[index] === byte);
}