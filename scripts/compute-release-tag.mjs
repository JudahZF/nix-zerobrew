import { execFileSync } from "node:child_process";
import fs from "node:fs";

const beforeRef = process.env.BEFORE_REF;
const currentSha = process.env.GITHUB_SHA;
const outputPath = process.env.GITHUB_OUTPUT;

if (!currentSha) {
  throw new Error("GITHUB_SHA is required");
}

function git(args, options = {}) {
  return execFileSync("git", args, {
    encoding: "utf8",
    ...options,
  }).trim();
}

function tryGit(args, options = {}) {
  try {
    return git(args, options);
  } catch {
    return "";
  }
}

function extractZerobrewTag(flakeNix) {
  const match = flakeNix.match(
    /zerobrew-src\s*=\s*\{[\s\S]*?ref\s*=\s*"([^"]+)";/m,
  );
  return match?.[1] ?? null;
}

function readFlakeNixAtRef(ref) {
  if (!ref || /^0+$/.test(ref)) {
    return null;
  }

  const content = tryGit(["show", `${ref}:flake.nix`]);
  return content || null;
}

function nextPatchFor(versionTag) {
  const rawTags = tryGit(["tag", "--list", `${versionTag}-*`, "--sort=-v:refname"]);
  const tags = rawTags
    .split("\n")
    .map((tag) => tag.trim())
    .filter(Boolean);

  const maxPatch = tags.reduce((max, tag) => {
    const match = tag.match(new RegExp(`^${versionTag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}-(\\d+)$`));
    if (!match) {
      return max;
    }

    return Math.max(max, Number.parseInt(match[1], 10));
  }, 0);

  return maxPatch + 1;
}

function writeOutput(name, value) {
  if (!outputPath) {
    return;
  }

  fs.appendFileSync(outputPath, `${name}=${value}\n`);
}

const currentFlakeNix = fs.readFileSync("flake.nix", "utf8");
const currentZerobrewTag = extractZerobrewTag(currentFlakeNix);

if (!currentZerobrewTag) {
  throw new Error("Failed to find zerobrew-src ref in flake.nix");
}

const previousFlakeNix = readFlakeNixAtRef(beforeRef);
const previousZerobrewTag = previousFlakeNix
  ? extractZerobrewTag(previousFlakeNix)
  : null;

const shouldTag = currentZerobrewTag !== previousZerobrewTag;
const patch = nextPatchFor(currentZerobrewTag);
const releaseTag = `${currentZerobrewTag}-${patch}`;

writeOutput("previous_zerobrew_tag", previousZerobrewTag ?? "");
writeOutput("current_zerobrew_tag", currentZerobrewTag);
writeOutput("should_tag", shouldTag ? "true" : "false");
writeOutput("release_tag", releaseTag);

process.stdout.write(
  JSON.stringify(
    {
      previousZerobrewTag,
      currentZerobrewTag,
      shouldTag,
      releaseTag,
    },
    null,
    2,
  ) + "\n",
);
