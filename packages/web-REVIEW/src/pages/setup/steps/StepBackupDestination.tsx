import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import {
  HardDrive,
  Cloud,
  Network,
  Eye,
  EyeOff,
  Play,
  ArrowLeft,
  ArrowRight,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps, PendingWrites } from '../wizardTypes';

/**
 * Step 23 — Backup destination.
 *
 * Mirrors `#screen-23` in `mockups/web-setup-wizard.html`. Owners pick where
 * encrypted nightly snapshots land:
 *
 *   1. `local`     — folder on the same machine. Cheapest, but useless against
 *                    hardware failure. Default `./data/backups`.
 *   2. `s3`        — any S3-compatible bucket (Backblaze B2, Wasabi, MinIO,
 *                    AWS S3). Reveals endpoint/bucket/key/secret fields.
 *   3. `tailscale` — push across the tailnet to a peer machine you control.
 *                    Reveals a single tailscale://node/share/path field.
 *
 * Persists `backup_destination_type` plus the relevant subset of
 * `backup_destination_path` / `backup_s3_*` keys via `onUpdate`. We clear
 * fields that don't belong to the active mode so the bulk PUT at the end of
 * the wizard doesn't carry stale state.
 *
 * "Run test backup" is a stub for now — wired up when the backup service
 * actually exists. Toast confirms the click works.
 */

type BackupKind = NonNullable<PendingWrites['backup_destination_type']>;

interface BackupOption {
  id: BackupKind;
  label: string;
  description: string;
  Icon: typeof HardDrive;
}

const OPTIONS: ReadonlyArray<BackupOption> = [
  {
    id: 'local',
    label: 'Local folder',
    description:
      'Snapshot to a folder on this machine. Fast, free, no network required.',
    Icon: HardDrive,
  },
  {
    id: 's3',
    label: 'S3-compatible (Backblaze B2, Wasabi, MinIO, AWS S3)',
    description:
      'Bring your own bucket. Daily encrypted upload — works with any S3 API.',
    Icon: Cloud,
  },
  {
    id: 'tailscale',
    label: 'Tailscale share',
    description:
      'Push backups across your tailnet to another machine you own.',
    Icon: Network,
  },
];

const DEFAULT_LOCAL_PATH = './data/backups';

export function StepBackupDestination({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const initialKind: BackupKind = pending.backup_destination_type ?? 'local';

  const [kind, setKind] = useState<BackupKind>(initialKind);
  const [localPath, setLocalPath] = useState<string>(
    initialKind === 'local'
      ? pending.backup_destination_path ?? DEFAULT_LOCAL_PATH
      : DEFAULT_LOCAL_PATH,
  );
  const [tailscalePath, setTailscalePath] = useState<string>(
    initialKind === 'tailscale' ? pending.backup_destination_path ?? '' : '',
  );
  const [s3Endpoint, setS3Endpoint] = useState<string>(pending.backup_s3_endpoint ?? '');
  const [s3Bucket, setS3Bucket] = useState<string>(pending.backup_s3_bucket ?? '');
  const [s3AccessKey, setS3AccessKey] = useState<string>(pending.backup_s3_access_key ?? '');
  const [s3SecretKey, setS3SecretKey] = useState<string>(pending.backup_s3_secret_key ?? '');
  const [showAccessKey, setShowAccessKey] = useState(false);
  const [showSecretKey, setShowSecretKey] = useState(false);

  // Sync the active mode's fields up to the wizard's pending bundle. We clear
  // fields that don't belong to the active mode so stale state doesn't carry
  // across when the owner toggles between options.
  useEffect(() => {
    const patch: Partial<PendingWrites> = {
      backup_destination_type: kind,
      backup_destination_path:
        kind === 'local'
          ? localPath || DEFAULT_LOCAL_PATH
          : kind === 'tailscale'
            ? tailscalePath
            : undefined,
      backup_s3_endpoint: kind === 's3' ? s3Endpoint : undefined,
      backup_s3_bucket: kind === 's3' ? s3Bucket : undefined,
      backup_s3_access_key: kind === 's3' ? s3AccessKey : undefined,
      backup_s3_secret_key: kind === 's3' ? s3SecretKey : undefined,
    };
    onUpdate(patch);
    // onUpdate identity may shift each render — value-driven sync only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, localPath, tailscalePath, s3Endpoint, s3Bucket, s3AccessKey, s3SecretKey]);

  const handleTestBackup = () => {
    toast('Test run will land when the backup service is wired.', { icon: 'i' });
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const helperText: Record<BackupKind, string> = {
    local:
      'Backups land on the same disk as your data — useful only as a defense against accidental deletion. Prefer S3 or Tailscale share for hardware failure protection.',
    s3:
      'Daily encrypted backups upload to your bucket overnight. Restore via the Settings → Backups page.',
    tailscale:
      'Push backups across your tailnet to another machine you control. Requires Tailscale running on both ends — see docs/tailscale-backup.md.',
  };

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Backup destination
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Where should nightly encrypted snapshots land? You can change this later in Settings.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="space-y-3">
          {OPTIONS.map(({ id, label, description, Icon }) => {
            const isSelected = kind === id;
            return (
              <button
                key={id}
                type="button"
                onClick={() => setKind(id)}
                className={
                  isSelected
                    ? 'flex w-full items-start gap-4 border-2 rounded-xl p-5 text-left transition-colors border-primary-500 bg-primary-50 dark:border-primary-400 dark:bg-primary-900/20'
                    : 'flex w-full items-start gap-4 border-2 rounded-xl p-5 text-left transition-colors border-surface-200 dark:border-surface-700 hover:border-surface-300 dark:hover:border-surface-600'
                }
                aria-pressed={isSelected}
              >
                <div
                  className={
                    isSelected
                      ? 'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950'
                      : 'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                  }
                >
                  <Icon className="h-5 w-5" />
                </div>
                <div className="flex-1">
                  <div
                    className={
                      isSelected
                        ? 'text-sm font-semibold text-primary-700 dark:text-primary-200'
                        : 'text-sm font-semibold text-surface-900 dark:text-surface-100'
                    }
                  >
                    {label}
                  </div>
                  <p
                    className={
                      isSelected
                        ? 'mt-0.5 text-xs text-primary-700/80 dark:text-primary-200/80'
                        : 'mt-0.5 text-xs text-surface-500 dark:text-surface-400'
                    }
                  >
                    {description}
                  </p>

                  {isSelected && id === 'local' ? (
                    <div className="mt-4 space-y-3 pt-4 border-t border-surface-200 dark:border-surface-700">
                      <div>
                        <label
                          htmlFor="backup-local-path"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Backup folder path
                        </label>
                        <input
                          id="backup-local-path"
                          type="text"
                          value={localPath}
                          onChange={(e) => setLocalPath(e.target.value)}
                          onClick={(e) => e.stopPropagation()}
                          placeholder={DEFAULT_LOCAL_PATH}
                          className="mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                        />
                      </div>
                      <p className="text-[11px] leading-snug text-surface-500 dark:text-surface-400">
                        {helperText.local}
                      </p>
                    </div>
                  ) : null}

                  {isSelected && id === 's3' ? (
                    <div className="mt-4 space-y-3 pt-4 border-t border-surface-200 dark:border-surface-700">
                      <div>
                        <label
                          htmlFor="backup-s3-endpoint"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Endpoint URL
                        </label>
                        <input
                          id="backup-s3-endpoint"
                          type="text"
                          value={s3Endpoint}
                          onChange={(e) => setS3Endpoint(e.target.value)}
                          onClick={(e) => e.stopPropagation()}
                          placeholder="https://s3.us-west-002.backblazeb2.com"
                          className="mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                        />
                      </div>
                      <div>
                        <label
                          htmlFor="backup-s3-bucket"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Bucket
                        </label>
                        <input
                          id="backup-s3-bucket"
                          type="text"
                          value={s3Bucket}
                          onChange={(e) => setS3Bucket(e.target.value)}
                          onClick={(e) => e.stopPropagation()}
                          placeholder="bizarre-shop-backups"
                          className="mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                        />
                      </div>
                      <div>
                        <label
                          htmlFor="backup-s3-access-key"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Access key
                        </label>
                        <div className="relative mt-1">
                          <input
                            id="backup-s3-access-key"
                            type={showAccessKey ? 'text' : 'password'}
                            value={s3AccessKey}
                            onChange={(e) => setS3AccessKey(e.target.value)}
                            onClick={(e) => e.stopPropagation()}
                            placeholder="0026e3a9f1c4d8200000000001"
                            className="block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 pr-10 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                          />
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              setShowAccessKey((v) => !v);
                            }}
                            className="absolute inset-y-0 right-0 flex items-center px-3 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
                            aria-label={showAccessKey ? 'Hide access key' : 'Show access key'}
                          >
                            {showAccessKey ? (
                              <EyeOff className="h-4 w-4" />
                            ) : (
                              <Eye className="h-4 w-4" />
                            )}
                          </button>
                        </div>
                      </div>
                      <div>
                        <label
                          htmlFor="backup-s3-secret-key"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Secret key
                        </label>
                        <div className="relative mt-1">
                          <input
                            id="backup-s3-secret-key"
                            type={showSecretKey ? 'text' : 'password'}
                            value={s3SecretKey}
                            onChange={(e) => setS3SecretKey(e.target.value)}
                            onClick={(e) => e.stopPropagation()}
                            placeholder="K002••••••••••••••••••••••••••••"
                            className="block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 pr-10 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                          />
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              setShowSecretKey((v) => !v);
                            }}
                            className="absolute inset-y-0 right-0 flex items-center px-3 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
                            aria-label={showSecretKey ? 'Hide secret key' : 'Show secret key'}
                          >
                            {showSecretKey ? (
                              <EyeOff className="h-4 w-4" />
                            ) : (
                              <Eye className="h-4 w-4" />
                            )}
                          </button>
                        </div>
                      </div>
                      <p className="text-[11px] leading-snug text-surface-500 dark:text-surface-400">
                        {helperText.s3}
                      </p>
                    </div>
                  ) : null}

                  {isSelected && id === 'tailscale' ? (
                    <div className="mt-4 space-y-3 pt-4 border-t border-surface-200 dark:border-surface-700">
                      <div>
                        <label
                          htmlFor="backup-tailscale-path"
                          className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                        >
                          Tailscale share path
                        </label>
                        <input
                          id="backup-tailscale-path"
                          type="text"
                          value={tailscalePath}
                          onChange={(e) => setTailscalePath(e.target.value)}
                          onClick={(e) => e.stopPropagation()}
                          placeholder="tailscale://node-name/share/folder"
                          className="mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 font-mono text-xs text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                        />
                      </div>
                      <p className="text-[11px] leading-snug text-surface-500 dark:text-surface-400">
                        {helperText.tailscale}
                      </p>
                    </div>
                  ) : null}
                </div>
              </button>
            );
          })}
        </div>

        <div>
          <button
            type="button"
            onClick={handleTestBackup}
            className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <Play className="h-4 w-4" />
            Run test backup
          </button>
          <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
            Stub for now — fires a real run once the backup service is wired.
          </p>
        </div>

        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={onNext}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400"
            >
              Continue
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepBackupDestination;
