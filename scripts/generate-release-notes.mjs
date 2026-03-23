import fs from "node:fs";
import { execFileSync } from "node:child_process";

const githubToken = process.env.GITHUB_TOKEN;
const currentTag = process.env.CURRENT_TAG;
const repository = process.env.GITHUB_REPOSITORY;

if (!githubToken) {
  throw new Error("GITHUB_TOKEN is required");
}

if (!currentTag) {
  throw new Error("CURRENT_TAG is required");
}

if (!repository || !repository.includes("/")) {
  throw new Error("GITHUB_REPOSITORY must be in owner/repo format");
}

const [owner, repo] = repository.split("/");

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

function readJsonAtRef(ref, path) {
  const content = git(["show", `${ref}:${path}`]);
  return JSON.parse(content);
}

function readTextAtRef(ref, path) {
  return git(["show", `${ref}:${path}`]);
}

function bulletList(items, emptyMessage) {
  if (items.length === 0) {
    return [`- ${emptyMessage}`];
  }

  return items.map((item) => `- ${item}`);
}

async function githubRequest(path) {
  const response = await fetch(`https://api.github.com${path}`, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${githubToken}`,
      "User-Agent": "nix-zerobrew-release-workflow",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`GitHub API ${path} failed: ${response.status} ${body}`);
  }

  return response.json();
}

function collectRepoCommitNotes(previousTag, currentTagName) {
  if (!previousTag) {
    return {
      compareUrl: null,
      commits: [],
    };
  }

  const rawLog = tryGit([
    "log",
    "--no-decorate",
    "--format=%h%x09%s",
    `${previousTag}..${currentTagName}`,
  ]);

  const commits = rawLog
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [sha, subject] = line.split("\t");
      return `\`${sha}\` ${subject}`;
    });

  return {
    compareUrl: `https://github.com/${owner}/${repo}/compare/${previousTag}...${currentTagName}`,
    commits,
  };
}

async function collectUpstreamNotes(previousZerobrewRev, currentZerobrewRev) {
  if (!previousZerobrewRev || previousZerobrewRev === currentZerobrewRev) {
    return {
      compareUrl: null,
      commits: [],
    };
  }

  const compare = await githubRequest(
    `/repos/lucasgelfond/zerobrew/compare/${previousZerobrewRev}...${currentZerobrewRev}`,
  );

  const commits = (compare.commits ?? []).map((commit) => {
    const sha = commit.sha.slice(0, 7);
    const subject = commit.commit.message.split("\n")[0];
    return `\`${sha}\` ${subject}`;
  });

  return {
    compareUrl: compare.html_url,
    commits,
  };
}

const localTags = tryGit(["tag", "--sort=-v:refname"])
  .split("\n")
  .map((tag) => tag.trim())
  .filter((tag) => tag.startsWith("v"));

const previousTag = localTags.find((tag) => tag !== currentTag) ?? null;
const currentCommit = git(["rev-list", "-n", "1", currentTag]);
const currentFlakeLock = JSON.parse(fs.readFileSync("flake.lock", "utf8"));
const currentFlakeNix = fs.readFileSync("flake.nix", "utf8");
const currentZerobrewRev =
  currentFlakeLock.nodes["zerobrew-src"]?.locked?.rev ?? null;
const currentZerobrewTag = extractZerobrewTag(currentFlakeNix);

let previousZerobrewRev = null;
let previousZerobrewTag = null;

if (previousTag) {
  const previousFlakeLock = readJsonAtRef(previousTag, "flake.lock");
  const previousFlakeNix = readTextAtRef(previousTag, "flake.nix");
  previousZerobrewRev =
    previousFlakeLock.nodes["zerobrew-src"]?.locked?.rev ?? null;
  previousZerobrewTag = extractZerobrewTag(previousFlakeNix);
}

const repoNotes = collectRepoCommitNotes(previousTag, currentTag);
const upstreamNotes = await collectUpstreamNotes(
  previousZerobrewRev,
  currentZerobrewRev,
);

const currentReleaseUrl = `https://github.com/${owner}/${repo}/releases/tag/${currentTag}`;
const lines = [
  `# ${currentTag}`,
  "",
  `Released from \`${currentCommit.slice(0, 7)}\`.`,
  "",
  "## nix-zerobrew",
  previousTag
    ? `- Previous release: [${previousTag}](https://github.com/${owner}/${repo}/releases/tag/${previousTag})`
    : "- Previous release: none",
  repoNotes.compareUrl
    ? `- Compare: ${repoNotes.compareUrl}`
    : `- Compare: first release on this repository`,
  "",
  ...bulletList(repoNotes.commits, "No repository commits since the previous release."),
  "",
  "## zerobrew",
  previousZerobrewTag && currentZerobrewTag
    ? `- Pinned release: \`${previousZerobrewTag}\` -> \`${currentZerobrewTag}\``
    : currentZerobrewTag
      ? `- Pinned release: \`${currentZerobrewTag}\``
      : "- Pinned release: unavailable",
  previousZerobrewRev && currentZerobrewRev
    ? `- Pinned revision: \`${previousZerobrewRev.slice(0, 7)}\` -> \`${currentZerobrewRev.slice(0, 7)}\``
    : currentZerobrewRev
      ? `- Pinned revision: \`${currentZerobrewRev.slice(0, 7)}\``
      : "- Pinned revision: unavailable",
  upstreamNotes.compareUrl
    ? `- Compare: ${upstreamNotes.compareUrl}`
    : previousZerobrewRev
      ? "- Compare: no upstream changes in the pinned zerobrew revision"
      : "- Compare: first release with zerobrew notes",
  currentZerobrewTag
    ? `- Upstream release: https://github.com/lucasgelfond/zerobrew/releases/tag/${encodeURIComponent(currentZerobrewTag)}`
    : "- Upstream release: unavailable",
  "",
  ...bulletList(upstreamNotes.commits, "No upstream zerobrew commits between pinned revisions."),
  "",
  "## Links",
  `- This release: ${currentReleaseUrl}`,
];

process.stdout.write(`${lines.join("\n")}\n`);
