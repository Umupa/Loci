const md5 = (() => {
  const shifts = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
  const constants = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) | 0);
  return (text) => {
    const bytes = new TextEncoder().encode(String(text));
    const words = new Array((((bytes.length + 8) >>> 6) + 1) * 16).fill(0);
    bytes.forEach((byte, i) => { words[i >> 2] |= byte << ((i % 4) * 8); });
    words[bytes.length >> 2] |= 0x80 << ((bytes.length % 4) * 8);
    words[words.length - 2] = (bytes.length * 8) | 0;
    words[words.length - 1] = Math.floor(bytes.length / 0x20000000);
    let h = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476];
    for (let block = 0; block < words.length; block += 16) {
      let [a, b, c, d] = h;
      for (let i = 0; i < 64; i++) {
        const round = i >> 4;
        let f, g;
        if (round === 0) { f = (b & c) | (~b & d); g = i; }
        else if (round === 1) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
        else if (round === 2) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
        else { f = c ^ (b | ~d); g = (7 * i) % 16; }
        const s = shifts[round * 4 + (i % 4)];
        f = (f + a + constants[i] + words[block + g]) | 0;
        a = d; d = c; c = b;
        b = (b + ((f << s) | (f >>> (32 - s)))) | 0;
      }
      h = [(h[0] + a) | 0, (h[1] + b) | 0, (h[2] + c) | 0, (h[3] + d) | 0];
    }
    return h.map((word) => [0, 8, 16, 24].map((shift) => ((word >>> shift) & 255).toString(16).padStart(2, "0")).join("")).join("");
  };
})();

const sha1 = (text) => {
  const bytes = new TextEncoder().encode(String(text));
  const words = new Array((((bytes.length + 8) >>> 6) + 1) * 16).fill(0);
  bytes.forEach((byte, i) => { words[i >> 2] |= byte << (24 - (i % 4) * 8); });
  words[bytes.length >> 2] |= 0x80 << (24 - (bytes.length % 4) * 8);
  words[words.length - 2] = Math.floor(bytes.length / 0x20000000);
  words[words.length - 1] = (bytes.length * 8) | 0;
  let h = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476, 0xc3d2e1f0 | 0];
  const w = new Array(80);
  for (let block = 0; block < words.length; block += 16) {
    for (let i = 0; i < 16; i++) w[i] = words[block + i];
    for (let i = 16; i < 80; i++) { const x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]; w[i] = (x << 1) | (x >>> 31); }
    let [a, b, c, d, e] = h;
    for (let i = 0; i < 80; i++) {
      let f, k;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc | 0; }
      else { f = b ^ c ^ d; k = 0xca62c1d6 | 0; }
      const t = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0;
      e = d; d = c; c = (b << 30) | (b >>> 2); b = a; a = t;
    }
    h = [(h[0] + a) | 0, (h[1] + b) | 0, (h[2] + c) | 0, (h[3] + d) | 0, (h[4] + e) | 0];
  }
  return h.map((word) => (word >>> 0).toString(16).padStart(8, "0")).join("");
};

const now = new Date(input.now);
{
  const RealDate = Date;
  const moment = input.now;
  globalThis.Date = class extends RealDate {
    constructor(...parts) { if (parts.length === 0) super(moment); else super(...parts); }
    static now() { return moment; }
  };
  for (const name of ["fetch", "XMLHttpRequest", "WebSocket", "EventSource", "Worker", "SharedWorker", "indexedDB",
    "localStorage", "sessionStorage", "caches", "importScripts"]) {
    try { Object.defineProperty(globalThis, name, { value: undefined, configurable: false }); } catch (_) {}
  }
}
