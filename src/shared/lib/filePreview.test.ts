import { describe, expect, it } from "vitest";
import { formatFileSize, imageDataUrl, sniffImageMime } from "./filePreview";
function bytes(...values: number[]): Uint8Array {
    return new Uint8Array(values);
}
describe("sniffImageMime", () => {
    it("identifies each supported format by magic number", () => {
        expect(sniffImageMime(bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))).toBe("image/png");
        expect(sniffImageMime(bytes(0xff, 0xd8, 0xff, 0xe0))).toBe("image/jpeg");
        expect(sniffImageMime(bytes(0x47, 0x49, 0x46, 0x38, 0x39, 0x61))).toBe("image/gif");
        expect(sniffImageMime(bytes(0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50))).toBe("image/webp");
        expect(sniffImageMime(bytes(0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66))).toBe("image/avif");
    });
    it("refuses content that is not a supported image", () => {
        const html = new TextEncoder().encode("<html><script>x()</script>");
        expect(sniffImageMime(html)).toBeNull();
        expect(sniffImageMime(new TextEncoder().encode("%PDF-1.7"))).toBeNull();
        expect(sniffImageMime(bytes(0x89, 0x50))).toBeNull();
        expect(sniffImageMime(bytes())).toBeNull();
        // An MP4 shares the ftyp box with AVIF but is not an image.
        expect(sniffImageMime(bytes(0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d))).toBeNull();
    });
});
describe("formatFileSize", () => {
    it("scales to the largest unit that keeps a leading digit", () => {
        expect(formatFileSize(0)).toBe("0 B");
        expect(formatFileSize(900)).toBe("900 B");
        expect(formatFileSize(2048)).toBe("2.0 KB");
        expect(formatFileSize(48 * 1024)).toBe("48 KB");
        expect(formatFileSize(3 * 1024 * 1024)).toBe("3.0 MB");
        expect(formatFileSize(2 * 1024 * 1024 * 1024)).toBe("2.0 GB");
    });
});
describe("imageDataUrl", () => {
    it("gives pictures an inline address named for what the bytes are", () => {
        expect(imageDataUrl(bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3))).toBe("data:image/png;base64,iVBORw0KGgoBAgM=");
        // Diagrams in documentation are usually SVG, with or without an XML prolog.
        for (const svg of ['<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>', '\uFEFF<?xml version="1.0"?>\n<!-- drawn by hand -->\n<!DOCTYPE svg>\n<svg viewBox="0 0 1 1"/>']) {
            const url = imageDataUrl(new TextEncoder().encode(svg))!;
            expect(url.startsWith("data:image/svg+xml;base64,")).toBe(true);
            expect(new TextDecoder("utf-8", { ignoreBOM: true }).decode(Uint8Array.from(atob(url.split(",")[1]), (char) => char.charCodeAt(0)))).toBe(svg);
        }
    });
    it("gives nothing for a file that is not a picture, is empty, or is too large to inline", () => {
        expect(imageDataUrl(new TextEncoder().encode("<html><svg/><script>x()</script>"))).toBeNull();
        expect(imageDataUrl(new TextEncoder().encode("ssh-ed25519 AAAA"))).toBeNull();
        expect(imageDataUrl(bytes())).toBeNull();
        const huge = new Uint8Array(8 * 1024 * 1024 + 1);
        huge.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
        expect(imageDataUrl(huge)).toBeNull();
        // A large picture under the limit is encoded in pieces without overflowing the call stack.
        const large = new Uint8Array(300_000);
        large.set([0xff, 0xd8, 0xff]);
        expect(imageDataUrl(large)!.length).toBeGreaterThan(400_000);
    });
});
