#!/usr/bin/env node
// Regenerates the fixed Bottts and Bottts Neutral catalog without bundling DiceBear.
// Install the pinned generator packages outside the repository, then run:
//   npm install --prefix /tmp/loci-dicebear @dicebear/core@10.6.0 @dicebear/styles@10.6.0
//   node scripts/generate-agent-avatars.mjs /tmp/loci-dicebear/node_modules
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Window } from "happy-dom";

const VERSION = "10.6.0";
const COLOR_MARKER = "#ff00fe";
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
const original = JSON.parse(readFileSync(require.resolve("@dicebear/styles/bottts.json", resolution), "utf8"));
const neutralOriginal = JSON.parse(readFileSync(require.resolve("@dicebear/styles/bottts-neutral.json", resolution), "utf8"));

// These are the artist's original component variants. Fixed combinations keep
// existing saved avatar names stable and make every face recognizably different.
const presets = [
  { name: "ember", head: "round02", eyes: "happy", mouth: "grill03", top: "lights", sides: "square" },
  { name: "wisp", head: "square01", eyes: "robocop", mouth: "square01", top: "bulb01", sides: "cables01", texture: "dots" },
  { name: "dew", head: "square02", eyes: "frame1", mouth: "square02", top: "radar", sides: "round", texture: "camo01" },
  { name: "moss", head: "square01", eyes: "glow", mouth: "grill02", top: "antennaCrooked", sides: "round", texture: "camo02" },
  { name: "nimbus", head: "square04", eyes: "hearts", mouth: "diagram", top: "radar", sides: "cables02", texture: "circuits" },
  { name: "pebble", head: "square03", eyes: "sensor", mouth: "smile01", top: "pyramid", sides: "squareAssymetric", texture: "dirty01" },
  { name: "luna", head: "round01", eyes: "roundFrame01", mouth: "grill01", top: "radar", sides: "antenna02" },
  { name: "nova", head: "round01", eyes: "eva", mouth: "bite", top: "horns", sides: "cables01" },
  { name: "flint", head: "square02", eyes: "bulging", mouth: "smile02", top: "antenna", sides: "antenna01", texture: "grunge02" },
  { name: "tide", head: "round02", eyes: "roundFrame02", mouth: "grill03", top: "bulb01", sides: "square" },
];

// Only the actual eye lights or eyeballs move. Their visors, frames, and
// reflections stay still; already smiling eyes and camera lenses stay static.
const blinkingElements = {
  frame1: [1, 2],
  glow: [4, 5, 6, 7],
  hearts: [0],
  roundFrame01: [1, 2],
  eva: [1],
  bulging: [2, 3, 4, 5],
  roundFrame02: [1, 2, 3, 4],
};
const definition = structuredClone(original);
const neutralDefinition = structuredClone(neutralOriginal);
for (const avatarDefinition of [definition, neutralDefinition]) {
  for (const [variant, indices] of Object.entries(blinkingElements)) {
    const elements = avatarDefinition.components.eyes.variants[variant].elements;
    const first = indices[0];
    elements.splice(first, indices.length, {
      type: "element",
      name: "g",
      attributes: { class: "agent-avatar-eyes" },
      children: indices.map((index) => elements[index]),
    });
  }
}
const style = new Style(definition);
const neutralStyle = new Style(neutralDefinition);
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
    .replaceAll(COLOR_MARKER, "currentColor");
  const ids = new Set([...markup.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]));
  for (const id of ids) {
    const instanceId = `${ID_PREFIX}-${name}-${id}`;
    markup = markup
      .replaceAll(`id="${id}"`, `id="${instanceId}"`)
      .replaceAll(`url(#${id})`, `url(#${instanceId})`)
      .replaceAll(`href="#${id}"`, `href="#${instanceId}"`);
  }
  markup = `<g fill="none">${markup}</g>`;
  // Inline markup is a checked-in asset, never content supplied by a user.
  // Fail regeneration if upstream starts emitting active or external content.
  if (/<(?:script|foreignObject|filter|image|a|animate|animateTransform)\b|\bon\w+=|\bhref="(?!#)/i.test(markup)) {
    throw new Error(`${name}: unexpected active or external SVG content`);
  }
  if (!markup.includes("currentColor") || markup.includes(COLOR_MARKER)) {
    throw new Error(`${name}: the agent color was not preserved`);
  }
  return markup;
}

const avatars = presets.map((preset) => {
  const options = { seed: `loci-${preset.name}`, baseColor: COLOR_MARKER, idRandomization: false };
  for (const part of ["head", "eyes", "mouth", "top", "sides", "texture"]) {
    if (preset[part]) options[`${part}Variant`] = preset[part];
  }
  options.textureProbability = preset.texture ? 100 : 0;
  return {
    name: preset.name,
    style: "bottts",
    viewBox: `0 0 ${original.canvas.width} ${original.canvas.height}`,
    markup: avatarMarkup(new Avatar(style, options).toString(), preset.name),
    canBlink: Boolean(blinkingElements[preset.eyes]),
  };
});

for (const preset of presets) {
  const name = `neutral-${preset.name}`;
  const options = {
    seed: `loci-${name}`,
    backgroundColor: COLOR_MARKER,
    borderRadius: 12,
    idRandomization: false,
    eyesVariant: preset.eyes,
    mouthVariant: preset.mouth,
    // Neutral keeps the artist's face on a solid square at every avatar size.
    textureProbability: 0,
  };
  avatars.push({
    name,
    style: "bottts-neutral",
    viewBox: `0 0 ${neutralOriginal.canvas.width} ${neutralOriginal.canvas.height}`,
    markup: avatarMarkup(new Avatar(neutralStyle, options).toString(), name),
    canBlink: Boolean(blinkingElements[preset.eyes]),
  });
}

const source = {
  version: VERSION,
  creator: original.meta.creator.name,
  license: original.meta.license.name,
  licenseUrl: original.meta.license.url,
  styles: [
    { name: "Bottts", url: "https://www.dicebear.com/styles/bottts/" },
    { name: "Bottts Neutral", url: "https://www.dicebear.com/styles/bottts-neutral/" },
  ],
};
const totalBytes = avatars.reduce((sum, avatar) => sum + Buffer.byteLength(avatar.markup), 0);
if (totalBytes >= 100_000) throw new Error(`Avatar SVG catalog exceeds 100 KB (${totalBytes} bytes)`);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = `// Generated by scripts/generate-agent-avatars.mjs. Do not edit by hand.
// Bottts and Bottts Neutral by Pablo Stanley, via DiceBear ${VERSION}.
// Artwork: free for personal and commercial use, https://bottts.com/.
// Adapted with a CSS-driven base color, directly painted eye animation groups,
// and instance ID placeholders. See NOTICE for source and license information.

export const BOTTTS_SOURCE = ${JSON.stringify(source, null, 2)} as const;

export const BOTTTS_AVATARS = ${JSON.stringify(avatars, null, 2)} as const;
`;
writeFileSync(join(root, "src/features/agents/model/bottts.generated.ts"), output);
console.log(`Generated ${avatars.length} Bottts avatars, ${totalBytes} SVG bytes, from DiceBear ${VERSION}.`);
