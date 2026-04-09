/**
 * GitHub Update Checker
 *
 * Periodically checks the GitHub repository for new commits.
 * Compares local HEAD against remote latest commit.
 * Broadcasts update notifications via WebSocket when new commits are found.
 */
import { execSync, exec } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { broadcast } from '../ws/server.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REPO_ROOT = path.resolve(__dirname, '../../../');
const REPO_OWNER = 'Sirovensky';
const REPO_NAME = 'BizarreCRM';
const CHECK_INTERVAL = 60 * 60 * 1000; // 1 hour

// ── Types ──────────────────────────────────────────────────────────────

interface UpdateStatus {
  available: boolean;
  currentCommit: string | null;
  latestCommit: string | null;
  commitMessage: string;
  commitDate: string;
  checkedAt: string | null;
}

// ── State ──────────────────────────────────────────────────────────────

let updateStatus: UpdateStatus = {
  available: false,
  currentCommit: null,
  latestCommit: null,
  commitMessage: '',
  commitDate: '',
  checkedAt: null,
};

let checkInterval: ReturnType<typeof setInterval> | null = null;

// ── Git Operations ─────────────────────────────────────────────────────

function getLocalCommitHash(): string | null {
  try {
    return execSync('git rev-parse HEAD', { cwd: REPO_ROOT, encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

async function getRemoteLatestCommit(): Promise<{ sha: string; message: string; date: string } | null> {
  try {
    const url = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits?per_page=1`;
    const response = await fetch(url, {
      headers: { 'User-Agent': 'BizarreCRM-Updater/1.0' },
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      console.warn(`[GitHubUpdater] API returned ${response.status}`);
      return null;
    }

    const commits = await response.json() as Array<{
      sha: string;
      commit: { message: string; author: { date: string } };
    }>;

    if (!Array.isArray(commits) || commits.length === 0) return null;

    const latest = commits[0];
    return {
      sha: latest.sha,
      message: latest.commit.message.split('\n')[0], // First line only
      date: latest.commit.author.date,
    };
  } catch (err) {
    console.warn('[GitHubUpdater] Failed to check remote:', err instanceof Error ? err.message : err);
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

  if (localHash && remote && localHash !== remote.sha) {
    updateStatus = {
      ...updateStatus,
      available: true,
      latestCommit: remote.sha,
      commitMessage: remote.message,
      commitDate: remote.date,
    };
    broadcast('management:update_available', updateStatus);
    console.log(`[GitHubUpdater] Update available: ${remote.message}`);
  } else if (localHash && remote && localHash === remote.sha) {
    updateStatus = {
      ...updateStatus,
      available: false,
      latestCommit: remote.sha,
      commitMessage: remote.message,
      commitDate: remote.date,
    };
  }

  return updateStatus;
}

export function getUpdateStatus(): Readonly<UpdateStatus> {
  return updateStatus;
}

export function performUpdate(): Promise<{ success: boolean; output: string }> {
  return new Promise((resolve) => {
    const commands = [
      'git pull origin main',
      'npm run build --workspace=packages/web',
    ].join(' && ');

    exec(commands, { cwd: REPO_ROOT, timeout: 120000 }, (error, stdout, stderr) => {
      const output = [stdout, stderr].filter(Boolean).join('\n');

      if (error) {
        console.error('[GitHubUpdater] Update failed:', error.message);
        resolve({ success: false, output: output || error.message });
        return;
      }

      console.log('[GitHubUpdater] Update completed successfully');
      // Reset update status
      updateStatus = { ...updateStatus, available: false };

      // Restart via PM2 if available
      exec('pm2 restart bizarre-crm', { cwd: REPO_ROOT }, (restartErr) => {
        if (restartErr) {
          resolve({ success: true, output: output + '\nNote: PM2 restart failed. Manual restart may be needed.' });
        } else {
          resolve({ success: true, output: output + '\nServer restarting via PM2...' });
        }
      });
    });
  });
}

export function startUpdateChecker(): void {
  if (checkInterval) return;
  checkInterval = setInterval(() => {
    checkForUpdates().catch((err) => {
      console.warn('[GitHubUpdater] Periodic check failed:', err);
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
