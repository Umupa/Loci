#!/usr/bin/env node
// Regenerates the fixed Notionists avatar catalog without bundling DiceBear.
// Install the pinned generator packages outside the repository, then run:
//   npm install --prefix /tmp/loci-dicebear @dicebear/core@10.6.0 @dicebear/styles@10.6.0
//   node scripts/generate-agent-avatars.mjs /tmp/loci-dicebear/node_modules
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Window } from "happy-dom";

const VERSION = "10.6.0";
const ID_PREFIX = "__LOCI_AVATAR_ID__";
const packages = process.argv[2];
if (!packages) {
  throw new Error("usage: node scripts/generate-agent-avatars.mjs <temporary node_modules directory>");
}
const packageRoot = resolve(packages);
for (const name of ["core", "styles"]) {
  const manifest = JSON.parse(readFileSync(join(packageRoot, "@dicebear", name, "package.json"), "utf8"));
  if (manifest.version !== VERSION) throw new Error(`@dicebear/${name}: expected ${VERSION}, got ${manifest.version}`);
}
const require = createRequire(import.meta.url);
const resolution = { paths: [dirname(packageRoot)] };
const { Style, Avatar } = await import(pathToFileURL(require.resolve("@dicebear/core", resolution)).href);
const original = JSON.parse(readFileSync(require.resolve("@dicebear/styles/notionists.json", resolution), "utf8"));

// The artist's own parts, combined by hand: plain tops, no props or gestures,
// so every face reads as a portrait at 16px. The first ten keep the names
// agents saved with the earlier robot faces.
const presets = [
  { name: "ember", hair: "variant20", glasses: "variant11", clothes: "variant08", mouth: "variant23" },
  { name: "wisp", hair: "variant41", clothes: "variant02", mouth: "variant22" },
  { name: "dew", hair: "variant05", beard: "variant02", glasses: "variant03", clothes: "variant04" },
  { name: "moss", hair: "variant48", clothes: "variant17", mouth: "variant21" },
  { name: "nimbus", hair: "variant42", glasses: "variant08", clothes: "variant06", mouth: "variant24" },
  { name: "pebble", hair: "variant60", beard: "variant09", clothes: "variant08", eyebrows: "variant05" },
  { name: "luna", hair: "variant46", glasses: "variant11", clothes: "variant02", mouth: "variant23" },
  { name: "nova", hair: "variant37", clothes: "variant04", mouth: "variant14" },
  { name: "flint", hair: "variant44", beard: "variant12", glasses: "variant01", clothes: "variant06" },
  { name: "tide", hair: "variant28", clothes: "variant17", mouth: "variant22" },
  { name: "juniper", hair: "variant09", glasses: "variant04", clothes: "variant10", mouth: "variant20" },
  { name: "wren", hair: "variant58", clothes: "variant08", mouth: "variant21" },
  { name: "ash", hair: "variant54", beard: "variant07", clothes: "variant02", mouth: "variant22" },
  { name: "quill", hair: "variant23", glasses: "variant09", clothes: "variant04", mouth: "variant20" },
];

const SIZE = original.canvas?.width ?? 1744;
// Head and shoulders for large avatars; the face alone where an avatar is small.
const BUST = "320 190 1110 1110";
const FACE = "470 330 800 800";
// A light card tinted with the agent's color, and the reference's pink cheeks.
const TILE = `<rect width="${SIZE}" height="${SIZE}" fill="#ececec"></rect><rect width="${SIZE}" height="${SIZE}" fill="currentColor" opacity="0.32"></rect>`;
const BLUSH = `<g fill="#f4a3a8" opacity="0.55" style="mix-blend-mode:multiply"><ellipse cx="848" cy="928" rx="50" ry="30"></ellipse><ellipse cx="1046" cy="918" rx="26" ry="24"></ellipse></g>`;

// Every eyes variant is wrapped in one group so CSS can blink it.
const definition = structuredClone(original);
for (const variant of Object.values(definition.components.eyes.variants)) {
  variant.elements = [{ type: "element", name: "g", attributes: { class: "agent-avatar-eyes" }, children: variant.elements }];
}
const style = new Style(definition);
const dom = new Window();
const parser = new dom.DOMParser();

function inlineComponents(svg, name) {
  const document = parser.parseFromString(svg, "image/svg+xml");
  const uses = [...document.querySelectorAll("use")];
  const references = new Set();
  for (const use of uses) {
    const href = use.getAttribute("href");
    if (!href?.startsWith("#") || references.has(href)) {
      throw new Error(`${name}: expected a local component referenced exactly once: ${href}`);
    }
    references.add(href);
  }
  // CSS transforms inside a referenced <use> are not reliably painted. Each
  // component is used once, so move its geometry into the visible tree while
  // keeping the instance transform as a separate enclosing group.
  for (const use of uses) {
    const source = document.getElementById(use.getAttribute("href").slice(1));
    if (source?.localName !== "g" || source.parentElement?.localName !== "defs") {
      throw new Error(`${name}: unexpected component definition`);
    }
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g");
    for (const attribute of use.attributes) {
      if (attribute.name === "href") continue;
      if (attribute.name !== "transform") throw new Error(`${name}: unexpected component attribute ${attribute.name}`);
      group.setAttribute(attribute.name, attribute.value);
    }
    source.removeAttribute("id");
    group.append(source);
    use.replaceWith(group);
  }
  if (document.querySelector("use") || document.querySelector("defs .agent-avatar-eyes")) {
    throw new Error(`${name}: eye animation is still in a referenced definition`);
  }
  return document.documentElement.innerHTML;
}

function avatarMarkup(svg, name) {
  let markup = inlineComponents(svg, name)
    .replace(/<!--[^]*?-->/g, "")
    .replace(/<metadata\b[^]*?<\/metadata>/g, "")
    .replace(/<defs><\/defs>/g, "");
  const ids = new Set([...markup.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]));
  for (const id of ids) {
    const instanceId = `${ID_PREFIX}-${name}-${id}`;
    markup = markup
      .replaceAll(`id="${id}"`, `id="${instanceId}"`)
      .replaceAll(`url(#${id})`, `url(#${instanceId})`)
      .replaceAll(`href="#${id}"`, `href="#${instanceId}"`);
  }
  markup = `<g fill="none">${TILE}${markup}${BLUSH}</g>`;
  // Inline markup is a checked-in asset, never content supplied by a user.
  // Fail regeneration if upstream starts emitting active or external content.
  if (/<(?:script|foreignObject|filter|image|a|animate|animateTransform)\b|\bon\w+=|\bhref="(?!#)/i.test(markup)) {
    throw new Error(`${name}: unexpected active or external SVG content`);
  }
  if (!markup.includes('class="agent-avatar-eyes"')) throw new Error(`${name}: the eyes cannot blink`);
  return markup;
}

const avatars = presets.map((preset) => {
  const options = {
    seed: `loci-${preset.name}`,
    idRandomization: false,
    gestureProbability: 0,
    clothesGraphicProbability: 0,
    beardProbability: preset.beard ? 100 : 0,
    glassesProbability: preset.glasses ? 100 : 0,
    eyesVariant: "variant01",
    eyebrowsVariant: preset.eyebrows ?? "variant01",
    noseVariant: "variant01",
    mouthVariant: preset.mouth ?? "variant20",
  };
  for (const part of ["hair", "clothes", "beard", "glasses"]) {
    if (preset[part]) options[`${part}Variant`] = preset[part];
  }
  return {
    name: preset.name,
    style: "notionists",
    viewBox: BUST,
    faceViewBox: FACE,
    markup: avatarMarkup(new Avatar(style, options).toString(), preset.name),
    canBlink: true,
  };
});

const source = {
  version: VERSION,
  name: original.meta.source.name,
  url: original.meta.source.url,
  creator: original.meta.creator.name,
  license: original.meta.license.name,
  licenseUrl: original.meta.license.url,
  style: "https://www.dicebear.com/styles/notionists/",
};
const totalBytes = avatars.reduce((sum, avatar) => sum + Buffer.byteLength(avatar.markup), 0);
if (totalBytes >= 400_000) throw new Error(`Avatar SVG catalog exceeds 400 KB (${totalBytes} bytes)`);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = `// Generated by scripts/generate-agent-avatars.mjs. Do not edit by hand.
// Notionists by Zoish (CC0 1.0), via DiceBear ${VERSION}.
// Adapted with a card tinted by the agent's color, cheeks, a blinkable eyes
// group, and instance ID placeholders. See NOTICE for source and license information.

export const NOTIONISTS_SOURCE = ${JSON.stringify(source, null, 2)} as const;

export const NOTIONISTS_AVATARS = ${JSON.stringify(avatars, null, 2)} as const;
`;
writeFileSync(join(root, "src/features/agents/model/notionists.generated.ts"), output);
console.log(`Generated ${avatars.length} Notionists avatars, ${totalBytes} SVG bytes, from DiceBear ${VERSION}.`);
