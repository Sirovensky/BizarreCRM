/**
 * UnsavedChangesGuard — protects the user from losing form edits when they
 * click away from a settings tab. Provides a React context that any tab can
 * register dirtiness with, plus a confirm modal that blocks navigation.
 *
 * Usage:
 *
 *   <UnsavedChangesProvider>
 *     <SettingsPage />
 *   </UnsavedChangesProvider>
 *
 *   // inside a tab:
 *   const { setDirty } = useUnsavedChanges();
 *   useEffect(() => setDirty('store', isDirty), [isDirty]);
 *
 *   // before changing tab/route:
 *   const { confirmNavigate } = useUnsavedChanges();
 *   if (await confirmNavigate()) setActiveTab('users');
 *
 * Also installs a `beforeunload` handler so browser reload/close is caught.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { AlertTriangle } from 'lucide-react';

interface UnsavedChangesContextValue {
  /** Flag a specific section (key) as dirty/clean */
  setDirty: (key: string, dirty: boolean) => void;
  /** True when any registered section is currently dirty */
  anyDirty: boolean;
  /** Clear all dirty flags (e.g. after save) */
  clearAll: () => void;
  /**
   * Prompt the user before navigating. Resolves true if they choose to
   * proceed, false if they want to stay. Resolves immediately true when no
   * dirty sections exist.
   */
  confirmNavigate: () => Promise<boolean>;
}

const Context = createContext<UnsavedChangesContextValue | null>(null);

export function UnsavedChangesProvider({ children }: { children: ReactNode }) {
  const [dirtyKeys, setDirtyKeys] = useState<Record<string, boolean>>({});
  const [prompt, setPrompt] = useState<null | ((choice: boolean) => void)>(null);
  // Ref used inside the beforeunload handler so it sees the latest state
  const dirtyKeysRef = useRef(dirtyKeys);
  dirtyKeysRef.current = dirtyKeys;

  const anyDirty = Object.values(dirtyKeys).some(Boolean);

  const setDirty = useCallback((key: string, dirty: boolean) => {
    setDirtyKeys((prev) => {
      if (!!prev[key] === dirty) return prev;
      return { ...prev, [key]: dirty };
    });
  }, []);

  const clearAll = useCallback(() => {
    setDirtyKeys({});
  }, []);

  const confirmNavigate = useCallback((): Promise<boolean> => {
    const hasDirty = Object.values(dirtyKeysRef.current).some(Boolean);
    if (!hasDirty) return Promise.resolve(true);
    return new Promise<boolean>((resolve) => {
      setPrompt(() => (choice: boolean) => {
        setPrompt(null);
        resolve(choice);
      });
    });
  }, []);

  // Block browser tab close / refresh when dirty
  useEffect(() => {
    function handleBeforeUnload(e: BeforeUnloadEvent) {
      const hasDirty = Object.values(dirtyKeysRef.current).some(Boolean);
      if (!hasDirty) return;
      e.preventDefault();
      // Chrome requires returnValue to be set
      e.returnValue = '';
    }
    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, []);

  const value = useMemo<UnsavedChangesContextValue>(
    () => ({ setDirty, anyDirty, clearAll, confirmNavigate }),
    [setDirty, anyDirty, clearAll, confirmNavigate]
  );

  return (
    <Context.Provider value={value}>
      {children}
      {prompt && <UnsavedChangesModal onChoice={prompt} />}
    </Context.Provider>
  );
}

export function useUnsavedChanges(): UnsavedChangesContextValue {
  const ctx = useContext(Context);
  if (!ctx) {
    // Provide a no-op fallback so tabs can be used in isolation during tests
    return {
      setDirty: () => {},
      anyDirty: false,
      clearAll: () => {},
      confirmNavigate: async () => true,
    };
  }
  return ctx;
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal
// ─────────────────────────────────────────────────────────────────────────────

function UnsavedChangesModal({ onChoice }: { onChoice: (proceed: boolean) => void }) {
  // Close on Escape = stay
  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onChoice(false);
      if (e.key === 'Enter') onChoice(true);
    }
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [onChoice]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="unsaved-title"
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4"
      onClick={() => onChoice(false)}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-md rounded-xl bg-white p-6 shadow-2xl dark:bg-surface-900"
      >
        <div className="flex items-start gap-3">
          <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-500/20">
            <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400" />
          </div>
          <div className="flex-1">
            <h2
              id="unsaved-title"
              className="text-lg font-semibold text-surface-900 dark:text-surface-100"
            >
              You have unsaved changes
            </h2>
            <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
              If you leave this tab, your edits will be discarded. Do you want to leave anyway?
            </p>
          </div>
        </div>
        <div className="mt-6 flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={() => onChoice(false)}
            className="rounded-lg border border-surface-200 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Stay on this tab
          </button>
          <button
            type="button"
            onClick={() => onChoice(true)}
            className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700"
          >
            Discard changes
          </button>
        </div>
      </div>
    </div>
  );
}
