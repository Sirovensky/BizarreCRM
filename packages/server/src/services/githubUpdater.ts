/**
 * GitHub Update Checker
 *
 * Periodically checks the GitHub repository for new commits.
 * Compares local HEAD against remote latest commit.
 * Broadcasts update notifications via WebSocket when new commits are found.
 */
import { execSync, exec, spawn } from 'child_process';
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
    // Use git fetch + git log to check remote — uses the system's git credentials
    // (works with credential manager, SSH keys, etc.)
    execSync('git fetch origin main --quiet', { cwd: REPO_ROOT, timeout: 30000, stdio: 'pipe' });
    const sha = execSync('git rev-parse origin/main', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 5000 }).trim();
    const message = execSync('git log origin/main -1 --format=%s', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 5000 }).trim();
    const date = execSync('git log origin/main -1 --format=%aI', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 5000 }).trim();
    return { sha, message, date };
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
    const updateScript = path.join(REPO_ROOT, 'scripts', 'update.bat');

    // Write a temporary VBS launcher — most reliable way to start a visible,
    // fully detached process on Windows that survives the parent being killed.
    const vbsPath = path.join(REPO_ROOT, 'scripts', '_update_launcher.vbs');
    const vbs = `Set ws = CreateObject("WScript.Shell")\nws.Run "cmd.exe /c ""${updateScript.replace(/\\/g, '\\\\')}""", 1, False\n`;

    try {
      const fs = require('fs');
      fs.writeFileSync(vbsPath, vbs);

      const child = spawn('wscript.exe', [vbsPath], {
        detached: true,
        stdio: 'ignore',
        cwd: REPO_ROOT,
      });
      child.unref();

      console.log('[GitHubUpdater] Update script launched via VBS (PID:', child.pid, ')');
      resolve({ success: true, output: 'Update started. Server and dashboard will restart automatically.' });
    } catch (err: any) {
      console.error('[GitHubUpdater] Failed to launch update:', err.message);
      resolve({ success: false, output: 'Failed to launch update: ' + err.message });
    }
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
