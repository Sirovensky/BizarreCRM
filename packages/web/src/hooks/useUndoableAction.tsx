import { useCallback, useEffect, useRef } from 'react';
import toast from 'react-hot-toast';
import { useAuthStore } from '@/stores/authStore';

export interface UseUndoableActionOptions<TArgs> {
  /** Delay before the action fires, in milliseconds. Default 5000. */
  timeoutMs?: number;
  /** Toast body shown while the undo window is open. Can be a string or a function of args. */
  pendingMessage?: string | ((args: TArgs) => string);
  /** Toast shown after the action successfully runs. If omitted, no success toast is fired. */
  successMessage?: string | ((args: TArgs) => string);
  /** Toast shown after the action fails. Default: 'Action failed'. */
  errorMessage?: string | ((args: TArgs, err: unknown) => string);
  /** Optional callback to revert any optimistic UI state when the user clicks Undo. */
  onUndo?: (args: TArgs) => void;
  /** Label for the Undo button. Default 'Undo'. */
  undoLabel?: string;
}

export interface UndoableActionControls<TArgs> {
  /** Schedule the action. Returns the generated toast id so callers can dismiss it externally. */
  trigger: (args: TArgs) => string;
  /** Cancel any pending action without running it or calling onUndo. */
  cancel: () => void;
  /** Whether an action is currently queued. */
  isPending: () => boolean;
}

/**
 * Hook that wraps a destructive action behind a 5-second undo window.
 *
 * Pattern: instead of running the destructive action immediately and later
 * trying to reverse it, we DELAY running it. During the delay a toast with
 * an Undo button is shown. If Undo is clicked we cancel the timer and never
 * call the server. If the timer elapses we call the action for real.
 *
 * For destructive actions the UI should update optimistically on `trigger`
 * (e.g. remove the row from a list) so the user sees the result instantly.
 * If the user clicks Undo, `onUndo` is called so the UI can restore state.
 */
export function useUndoableAction<TArgs = void>(
  action: (args: TArgs) => Promise<unknown>,
  options: UseUndoableActionOptions<TArgs> = {},
): UndoableActionControls<TArgs> {
  const {
    timeoutMs = 5000,
    pendingMessage,
    successMessage,
    errorMessage = 'Action failed',
    onUndo,
    undoLabel = 'Undo',
  } = options;

  // Keep the latest action + callbacks in refs so we do not re-create trigger
  // on every render (and lose the timer) when the caller passes inline fns.
  const actionRef = useRef(action);
  const onUndoRef = useRef(onUndo);
  const successMessageRef = useRef(successMessage);
  const errorMessageRef = useRef(errorMessage);
  const pendingMessageRef = useRef(pendingMessage);

  useEffect(() => {
    actionRef.current = action;
  }, [action]);
  useEffect(() => {
    onUndoRef.current = onUndo;
  }, [onUndo]);
  useEffect(() => {
    successMessageRef.current = successMessage;
  }, [successMessage]);
  useEffect(() => {
    errorMessageRef.current = errorMessage;
  }, [errorMessage]);
  useEffect(() => {
    pendingMessageRef.current = pendingMessage;
  }, [pendingMessage]);

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const toastIdRef = useRef<string | null>(null);
  const argsRef = useRef<TArgs | null>(null);
  // WEB-FI-024 (Fixer-C7 2026-04-25): freeze the action callback at trigger
  // time so a parent re-render that swaps `action` between trigger and the
  // 5s timer fire cannot run a *different* mutation than the user originally
  // confirmed. Without this, `actionRef.current` is updated on every render,
  // and the timer ends up calling whatever `action` happens to be current
  // when it fires — which is rarely what was on screen when the user clicked.
  const frozenActionRef = useRef<((args: TArgs) => Promise<unknown>) | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const cancel = useCallback(() => {
    clearTimer();
    if (toastIdRef.current !== null) {
      toast.dismiss(toastIdRef.current);
      toastIdRef.current = null;
    }
    argsRef.current = null;
    frozenActionRef.current = null;
  }, [clearTimer]);

  const resolveMessage = <R,>(
    msg: string | ((args: TArgs) => R) | undefined,
    args: TArgs,
  ): string | undefined => {
    if (msg === undefined) return undefined;
    return typeof msg === 'function' ? String((msg as (a: TArgs) => R)(args)) : msg;
  };

  const trigger = useCallback(
    (args: TArgs): string => {
      // If a previous undo window is still open, clear it first. The previous
      // action never ran, so this is equivalent to the user pressing Undo on it.
      clearTimer();
      if (toastIdRef.current !== null) {
        toast.dismiss(toastIdRef.current);
        toastIdRef.current = null;
      }

      argsRef.current = args;
      // Snapshot the action at trigger-time. See WEB-FI-024 note above.
      frozenActionRef.current = actionRef.current;
      const body = resolveMessage(pendingMessageRef.current, args) ?? 'Action scheduled';

      const tId = toast(
        (tInstance) => (
          <span className="flex items-center gap-2 text-sm">
            <span>{body}</span>
            <button
              type="button"
              className="ml-2 rounded bg-surface-200 px-3 py-2 min-h-[44px] md:min-h-0 md:px-2 md:py-0.5 text-xs font-medium hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
              onClick={() => {
                clearTimer();
                const undoArgs = argsRef.current;
                argsRef.current = null;
                toastIdRef.current = null;
                frozenActionRef.current = null;
                toast.dismiss(tInstance.id);
                if (undoArgs !== null && onUndoRef.current) {
                  try {
                    onUndoRef.current(undoArgs);
                  } catch (err) {
                    // Do not let a broken onUndo tear down the UI.
                    console.error('useUndoableAction onUndo threw', err);
                  }
                }
              }}
            >
              {undoLabel}
            </button>
          </span>
        ),
        { duration: timeoutMs },
      );

      toastIdRef.current = tId;

      timerRef.current = setTimeout(() => {
        const runArgs = argsRef.current;
        const runAction = frozenActionRef.current;
        timerRef.current = null;
        argsRef.current = null;
        toastIdRef.current = null;
        frozenActionRef.current = null;
        if (runArgs === null || runAction === null) return;
        runAction(runArgs)
          .then(() => {
            const success = resolveMessage(successMessageRef.current, runArgs);
            if (success) toast.success(success);
          })
          .catch((err: unknown) => {
            const errMsg = errorMessageRef.current;
            const msg =
              typeof errMsg === 'function' ? errMsg(runArgs, err) : errMsg;
            toast.error(msg || 'Action failed');
            // Restore UI since the real mutation failed.
            if (onUndoRef.current) {
              try {
                onUndoRef.current(runArgs);
              } catch (cbErr) {
                console.error('useUndoableAction onUndo threw after error', cbErr);
              }
            }
          });
      }, timeoutMs);

      return tId;
    },
    [clearTimer, timeoutMs, undoLabel],
  );

  const isPending = useCallback(() => timerRef.current !== null, []);

  // If the component unmounts with a pending undo window, fire the action
  // immediately so we do not silently drop the user's intent.
  //
  // SCAN-1088: if the user is closing the tab (document becoming hidden /
  // pagehide firing the unmount) we should NOT commit a destructive action
  // they were still considering. Before, a user who typed "delete ticket",
  // saw the 5-second undo toast, changed their mind, and closed the tab
  // would still have the deletion fire through the unmount cleanup. Skip
  // the fire in that case — the timer is discarded silently. If the user
  // navigates to another route inside the SPA (visibility === 'visible'),
  // firing is still the right behavior so pending intent is preserved.
  //
  // WEB-FD-007 (Fixer-B7 2026-04-25): also skip the unmount fire when auth
  // has been cleared (logout / forced logout / switch-user) inside the 5s
  // window. AppShell unmounts the host on logout; firing the snapshot
  // afterward issues a request whose token has already been invalidated —
  // best case 401 + console error, worst case the request was queued before
  // logout-cleanup and runs as the previous user. Drop the pending intent
  // when the session is gone.
  useEffect(() => {
    return () => {
      if (timerRef.current !== null) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
        const runArgs = argsRef.current;
        const runAction = frozenActionRef.current;
        argsRef.current = null;
        toastIdRef.current = null;
        frozenActionRef.current = null;
        const tabHidden =
          typeof document !== 'undefined' && document.visibilityState === 'hidden';
        const authed = useAuthStore.getState().isAuthenticated;
        if (runArgs !== null && runAction !== null && !tabHidden && authed) {
          // Fire and forget — we are unmounting, no UI to update.
          // Log the error so silent data-loss failures are still visible in
          // browser console / error telemetry rather than vanishing entirely.
          // WEB-FI-024: use the trigger-time snapshot, not whatever the latest
          // render set into actionRef.current.
          runAction(runArgs).catch((err) => {
            console.error('[useUndoableAction] unmount-fired action failed', err);
          });
        }
      }
    };
  }, []);

  return { trigger, cancel, isPending };
}
