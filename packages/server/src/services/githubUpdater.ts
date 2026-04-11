/**
 * GitHub Update Checker
 *
 * Periodically checks the GitHub repository for new commits.
 * Compares local HEAD against remote latest commit.
 * Broadcasts update notifications via WebSocket when new commits are found.
 *
 * Security (criticalaudit.md §39):
 *  - UP1: SHA pinning, signed commit verification, and optional tag-gating
 *         are enforced before accepting a remote SHA as "available".
 *  - UP2: The configured remote URL is checked against EXPECTED_REMOTE_URL
 *         on every poll. If `git remote get-url origin` points anywhere
 *         else we refuse to fetch and log a critical error.
 *  - UP3: The new HEAD's commit timestamp must be >= the current HEAD's
 *         timestamp. Force-push downgrades are rejected.
 *
 * The actual `git checkout` / restart still runs inside the Electron
 * Management Dashboard — this service only computes and advertises
 * availability via WebSocket.
 */
import { execFileSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { broadcast } from '../ws/server.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('githubUpdater');

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REPO_ROOT = path.resolve(__dirname, '../../../');
const REPO_OWNER = 'Sirovensky';
const REPO_NAME = 'BizarreCRM';
const CHECK_INTERVAL = 60 * 60 * 1000; // 1 hour

// UP2: The only remote URL we will accept. If `origin` points anywhere else
// the check refuses to fetch. Both canonical forms are allowed because git
// will happily use either.
const EXPECTED_REMOTE_URLS: ReadonlyArray<string> = [
  `https://github.com/${REPO_OWNER}/${REPO_NAME}.git`,
  `https://github.com/${REPO_OWNER}/${REPO_NAME}`,
  `git@github.com:${REPO_OWNER}/${REPO_NAME}.git`,
];

// UP1: Security policy toggles, all off-by-default so an unconfigured
// install still sees the update notification, but anyone hardening their
// deployment can opt in via env.
const PINNED_SHA = (process.env.ALLOWED_UPDATE_SHA || '').trim();            // exact SHA required
const REQUIRE_SIGNED_COMMIT = process.env.UPDATE_REQUIRE_SIGNED === 'true';   // git verify-commit
const REQUIRE_VERSION_TAG = process.env.UPDATE_REQUIRE_TAG === 'true';        // git tag --contains

const SHA_PATTERN = /^[0-9a-f]{7,40}$/;

// ── Types ──────────────────────────────────────────────────────────────

interface UpdateStatus {
  available: boolean;
  currentCommit: string | null;
  latestCommit: string | null;
  commitMessage: string;
  commitDate: string;
  checkedAt: string | null;
  /** Last failure reason, if the most recent check was rejected. */
  lastRejection: string | null;
}

// ── State ──────────────────────────────────────────────────────────────

let updateStatus: UpdateStatus = {
  available: false,
  currentCommit: null,
  latestCommit: null,
  commitMessage: '',
  commitDate: '',
  checkedAt: null,
  lastRejection: null,
};

let checkInterval: ReturnType<typeof setInterval> | null = null;

// ── Git helpers ────────────────────────────────────────────────────────

/**
 * Run git with arguments as an array (never through a shell). `execFileSync`
 * sidesteps shell-metacharacter injection entirely — every arg reaches git
 * as a single argv token regardless of content.
 */
function git(args: string[], timeout = 10_000): string {
  return execFileSync('git', args, {
    cwd: REPO_ROOT,
    encoding: 'utf-8',
    timeout,
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function gitSafe(args: string[], timeout = 10_000): string | null {
  try {
    return git(args, timeout);
  } catch {
    return null;
  }
}

function isValidSha(sha: string): boolean {
  return typeof sha === 'string' && SHA_PATTERN.test(sha);
}

// ── Verification (UP1/UP2/UP3) ─────────────────────────────────────────

/**
 * UP2: refuse to run any fetch/update logic unless `origin` points at the
 * expected GitHub repo. Protects against a poisoned local clone that had its
 * origin swapped to an attacker-controlled mirror.
 */
function verifyOriginRemote(): boolean {
  const url = gitSafe(['remote', 'get-url', 'origin'], 5_000);
  if (!url) {
    log.error('Unable to read origin URL — refusing to update');
    updateStatus.lastRejection = 'origin remote missing';
    return false;
  }
  if (!EXPECTED_REMOTE_URLS.includes(url)) {
    log.error('CRITICAL: origin remote URL mismatch, refusing to update', {
      actual: url,
      expected: EXPECTED_REMOTE_URLS,
    });
    updateStatus.lastRejection = `origin mismatch: ${url}`;
    return false;
  }
  return true;
}

/**
 * UP1: if a signed-commit policy is enabled, require the configured ref to
 * carry a good GPG signature. Returns true when the policy is not enabled
 * or the signature checks out.
 */
function verifyCommitSignature(ref: string): boolean {
  if (!REQUIRE_SIGNED_COMMIT) return true;
  if (!isValidSha(ref)) return false;
  try {
    git(['verify-commit', ref], 10_000);
    return true;
  } catch (err) {
    log.warn('verify-commit failed', {
      ref,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

/**
 * UP1: if the tag policy is enabled, the commit must be reachable from a
 * real version tag. Protects against picking up a random in-flight commit.
 */
function verifyTagContains(ref: string): boolean {
  if (!REQUIRE_VERSION_TAG) return true;
  if (!isValidSha(ref)) return false;
  const tags = gitSafe(['tag', '--contains', ref], 10_000);
  if (!tags) {
    log.warn('no tag contains commit — rejecting update', { ref });
    return false;
  }
  return true;
}

/**
 * UP1: if a pinned SHA is configured, the remote SHA MUST match it exactly.
 */
function verifyPinnedSha(remoteSha: string): boolean {
  if (!PINNED_SHA) return true;
  if (!isValidSha(PINNED_SHA)) {
    log.error('ALLOWED_UPDATE_SHA is set but invalid — rejecting update', { PINNED_SHA });
    return false;
  }
  // accept any prefix match of 7+ hex chars
  const matches =
    PINNED_SHA === remoteSha ||
    remoteSha.startsWith(PINNED_SHA) ||
    PINNED_SHA.startsWith(remoteSha);
  if (!matches) {
    log.warn('remote SHA does not match ALLOWED_UPDATE_SHA — rejecting', {
      pinned: PINNED_SHA,
      remote: remoteSha,
    });
  }
  return matches;
}

/**
 * UP3: Reject the update if the remote commit's author timestamp is strictly
 * older than the local HEAD's author timestamp. `%ct` is the committer date
 * in unix seconds. Equal timestamps are allowed (same commit, rebased refs).
 */
function verifyNotDowngrade(localSha: string, remoteSha: string): boolean {
  if (!isValidSha(localSha) || !isValidSha(remoteSha)) return false;
  const localRaw = gitSafe(['log', '-1', '--format=%ct', localSha], 5_000);
  const remoteRaw = gitSafe(['log', '-1', '--format=%ct', remoteSha], 5_000);
  if (!localRaw || !remoteRaw) {
    log.warn('unable to read commit timestamps — rejecting update', { localSha, remoteSha });
    return false;
  }
  const localTs = Number(localRaw);
  const remoteTs = Number(remoteRaw);
  if (!Number.isFinite(localTs) || !Number.isFinite(remoteTs)) {
    log.warn('non-numeric commit timestamp — rejecting update');
    return false;
  }
  if (remoteTs < localTs) {
    log.error('CRITICAL: remote commit is OLDER than local — downgrade rejected', {
      localTs,
      remoteTs,
      localSha,
      remoteSha,
    });
    return false;
  }
  return true;
}

// ── Git Operations ─────────────────────────────────────────────────────

function getLocalCommitHash(): string | null {
  const sha = gitSafe(['rev-parse', 'HEAD'], 5_000);
  return sha && isValidSha(sha) ? sha : null;
}

async function getRemoteLatestCommit(): Promise<{
  sha: string;
  message: string;
  date: string;
} | null> {
  // UP2 — bail out before we ever touch the network if origin is wrong.
  if (!verifyOriginRemote()) return null;
  try {
    git(['fetch', 'origin', 'main', '--quiet'], 30_000);
    const sha = git(['rev-parse', 'origin/main'], 5_000);
    if (!isValidSha(sha)) {
      log.warn('remote SHA failed format check', { sha });
      return null;
    }
    const message = git(['log', 'origin/main', '-1', '--format=%s'], 5_000);
    const date = git(['log', 'origin/main', '-1', '--format=%aI'], 5_000);
    return { sha, message, date };
  } catch (err) {
    log.warn('failed to check remote', {
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

// ── Public API ─────────────────────────────────────────────────────────

export async function checkForUpdates(): Promise<UpdateStatus> {
  const localHash = getLocalCommitHash();
  const remote = await getRemoteLatestCommit();

  updateStatus = {
    ...updateStatus,
    currentCommit: localHash,
    checkedAt: new Date().toISOString(),
  };

  if (!localHash || !remote) {
    return updateStatus;
  }

  if (localHash === remote.sha) {
    updateStatus = {
      ...updateStatus,
      available: false,
      latestCommit: remote.sha,
      commitMessage: remote.message,
      commitDate: remote.date,
      lastRejection: null,
    };
    return updateStatus;
  }

  // There is a newer remote SHA — run it through the security policy gate
  // before advertising an update. A failure in ANY check means "not
  // available" and the reason is recorded on the status object.
  const reasons: string[] = [];

  if (!verifyPinnedSha(remote.sha)) reasons.push('pinned SHA mismatch');
  if (!verifyCommitSignature(remote.sha)) reasons.push('signature verification failed');
  if (!verifyTagContains(remote.sha)) reasons.push('no version tag');
  if (!verifyNotDowngrade(localHash, remote.sha)) reasons.push('downgrade rejected');

  if (reasons.length > 0) {
    log.warn('update candidate rejected by security policy', {
      remoteSha: remote.sha,
      reasons,
    });
    updateStatus = {
      ...updateStatus,
      available: false,
      latestCommit: remote.sha,
      commitMessage: remote.message,
      commitDate: remote.date,
      lastRejection: reasons.join('; '),
    };
    return updateStatus;
  }

  updateStatus = {
    ...updateStatus,
    available: true,
    latestCommit: remote.sha,
    commitMessage: remote.message,
    commitDate: remote.date,
    lastRejection: null,
  };
  broadcast('management:update_available', updateStatus);
  log.info('update available', {
    currentCommit: localHash,
    latestCommit: remote.sha,
    commitMessage: remote.message,
  });

  return updateStatus;
}

export function getUpdateStatus(): Readonly<UpdateStatus> {
  return updateStatus;
}

/**
 * performUpdate is now handled by the Electron dashboard process
 * (which has the user's PATH, git credentials, and can kill/restart processes).
 * This server-side stub exists only for backward compatibility.
 */
export async function performUpdate(): Promise<{ success: boolean; output: string }> {
  return {
    success: false,
    output: 'Updates are now handled by the Management Dashboard. Use the dashboard Update button.',
  };
}

export function startUpdateChecker(): void {
  if (checkInterval) return;
  checkInterval = setInterval(() => {
    checkForUpdates().catch((err) => {
      log.warn('periodic check failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    });
  }, CHECK_INTERVAL);
  checkInterval.unref(); // Don't keep process alive for update checks
}

export function stopUpdateChecker(): void {
  if (checkInterval) {
    clearInterval(checkInterval);
    checkInterval = null;
  }
}
