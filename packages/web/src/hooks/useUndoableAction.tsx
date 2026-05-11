import { useCallback, useEffect, useRef } from 'react';
import { Clock } from 'lucide-react';
import toast from 'react-hot-toast';

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
      const countdownSec = Math.round(timeoutMs / 1000);
      const body = resolveMessage(pendingMessageRef.current, args) ?? `Will run in ${countdownSec}s`;

      const tId = toast(
        (tInstance) => (
          <span className="flex items-center gap-2 text-sm">
            <Clock size={14} className="shrink-0 text-zinc-400" aria-hidden="true" />
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

  // WEB-UIUX-844: on unmount, ABORT the pending action instead of firing it.
  // Rationale: SPA navigation (browser back, sidebar click, link follow)
  // during the 5s undo window is best interpreted as "the user moved on" —
  // an implicit cancel rather than a confirm. Previously the hook fired
  // the snapshot through unmount cleanup, which meant a browser-back
  // mid-window could commit a deletion the user thought they had escaped
  // from. The explicit confirmation channels are: (a) the 5s timer
  // expires while the component is still mounted, (b) the operator does
  // nothing and stays on the page. Both still work. Tab close + auth
  // clear already cancelled silently under the prior policy; that
  // behavior is preserved by abort-on-unmount as a strict superset.
  useEffect(() => {
    return () => {
      if (timerRef.current !== null) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
        argsRef.current = null;
        toastIdRef.current = null;
        frozenActionRef.current = null;
      }
    };
  }, []);

  return { trigger, cancel, isPending };
}
