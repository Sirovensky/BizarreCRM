/**
 * GitHub Update Checker
 *
 * Periodically checks the GitHub repository for new commits.
 * Compares local HEAD against remote latest commit.
 * Broadcasts update notifications via WebSocket when new commits are found.
 */
import { execSync } from 'child_process';
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

export async function performUpdate(): Promise<{ success: boolean; output: string }> {
  const logs: string[] = [];
  const log = (msg: string) => { console.log(`[GitHubUpdater] ${msg}`); logs.push(msg); };

  try {
    // Step 1: Git pull
    log('Pulling latest code...');
    const pullOutput = execSync('git pull origin main', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 60000 });
    log(pullOutput.trim());

    // Step 2: Install deps
    log('Installing dependencies...');
    execSync('npm install', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 300000 });
    log('Dependencies installed');

    // Step 3: Build everything (shared + web + server)
    log('Building...');
    execSync('npm run build', { cwd: REPO_ROOT, encoding: 'utf-8', timeout: 300000 });
    log('Build complete');

    // Step 4: Rebuild dashboard
    log('Rebuilding dashboard...');
    try {
      execSync('npm run build && npm run package', {
        cwd: path.join(REPO_ROOT, 'packages', 'management'),
        encoding: 'utf-8',
        timeout: 300000,
      });
      // Copy to root dashboard/ folder
      const releaseSrc = path.join(REPO_ROOT, 'packages', 'management', 'release', 'win-unpacked');
      const dashDest = path.join(REPO_ROOT, 'dashboard');
      try {
        execSync(`xcopy /E /I /Q /Y "${releaseSrc}" "${dashDest}"`, { encoding: 'utf-8', stdio: 'pipe' });
      } catch { /* ok if xcopy fails */ }
      log('Dashboard rebuilt');
    } catch {
      log('Dashboard rebuild failed (non-critical)');
    }

    updateStatus = { ...updateStatus, available: false };
    log('Update complete — restarting server in 3 seconds...');

    // Step 5: Kill server. The dashboard will detect offline and user relaunches.
    setTimeout(() => {
      console.log('[GitHubUpdater] Exiting for restart...');
      process.exit(0);
    }, 3000);

    return { success: true, output: logs.join('\n') };
  } catch (err: any) {
    log('Update failed: ' + (err.message || String(err)));
    return { success: false, output: logs.join('\n') };
  }
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
