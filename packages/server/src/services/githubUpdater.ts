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
    // Full update: pull → install deps → rebuild everything → kill dashboard → restart server
    // Uses cmd /c so Windows batch chaining works correctly
    const commands = [
      'git pull origin main',
      'npm install',
      'npm run build',
      'cd packages\\management && npm run build && npm run package && cd ..\\..',
      // Copy dashboard to root dashboard/ folder
      'if exist packages\\management\\release\\win-unpacked xcopy /E /I /Q /Y packages\\management\\release\\win-unpacked dashboard >nul 2>nul',
      // Kill the dashboard EXE so it picks up the new version when relaunched
      'taskkill /F /IM "BizarreCRM Management.exe" >nul 2>nul',
    ].join(' && ');

    exec(`cmd /c "${commands}"`, { cwd: REPO_ROOT, timeout: 600000 }, (error, stdout, stderr) => {
      const output = [stdout, stderr].filter(Boolean).join('\n');

      if (error) {
        console.error('[GitHubUpdater] Update failed:', error.message);
        resolve({ success: false, output: output || error.message });
        return;
      }

      console.log('[GitHubUpdater] Update completed successfully — restarting server');
      updateStatus = { ...updateStatus, available: false };

      // Restart server: try PM2 first, then exit process (will auto-restart if run as service)
      exec('pm2 restart bizarre-crm', { cwd: REPO_ROOT }, (restartErr) => {
        if (restartErr) {
          // No PM2 — just exit. If running as a Windows Service or via setup.bat, it will restart.
          resolve({ success: true, output: output + '\nUpdate complete. Server restarting...' });
          setTimeout(() => process.exit(0), 2000);
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
