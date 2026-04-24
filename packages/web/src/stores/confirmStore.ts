import { create } from 'zustand';

interface ConfirmState {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  danger: boolean;
  resolve: ((value: boolean) => void) | null;
}

interface ConfirmStore extends ConfirmState {
  confirm: (opts: { title?: string; message: string; confirmLabel?: string; danger?: boolean }) => Promise<boolean>;
  close: (result: boolean) => void;
}

export const useConfirmStore = create<ConfirmStore>((set, get) => ({
  open: false,
  title: 'Confirm',
  message: '',
  confirmLabel: 'Confirm',
  danger: false,
  resolve: null,

  confirm: (opts) => {
    return new Promise<boolean>((resolve) => {
      // SCAN-1169: if a prior confirm is still pending (modal is still open
      // and its resolver hasn't been called), settle it with `false` before
      // overwriting the slot. Otherwise the previous promise hangs forever
      // and any code awaiting it leaks its closure over the session. The
      // "cancel previous" semantics match what users perceive — the second
      // call visually replaces the first dialog.
      const prev = get().resolve;
      if (prev) {
        try { prev(false); } catch { /* best-effort */ }
      }
      set({
        open: true,
        title: opts.title || 'Confirm',
        message: opts.message,
        confirmLabel: opts.confirmLabel || 'Confirm',
        danger: opts.danger ?? false,
        resolve,
      });
    });
  },

  close: (result) => {
    const { resolve } = get();
    resolve?.(result);
    set({ open: false, resolve: null });
  },
}));

/** Shorthand: await confirm('Delete this item?') */
export function confirm(message: string, opts?: { title?: string; confirmLabel?: string; danger?: boolean }): Promise<boolean> {
  return useConfirmStore.getState().confirm({ message, ...opts });
}
