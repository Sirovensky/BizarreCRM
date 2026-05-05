import { ConfirmDialog } from './ConfirmDialog';
import { useConfirmStore } from '@/stores/confirmStore';

export function GlobalConfirmDialog() {
  const { open, generation, title, message, confirmLabel, danger, close } = useConfirmStore();

  return (
    <ConfirmDialog
      // WEB-FI-015 (Fixer-B4 2026-04-25): keying on `generation` forces React
      // to remount the dialog whenever a new confirm() call lands while the
      // previous one was still open. Without the key, React reconciles the
      // existing dialog and the prior title/message can flash for a frame
      // between the resolver-cancel and the next paint.
      key={generation}
      open={open}
      title={title}
      message={message}
      confirmLabel={confirmLabel}
      danger={danger}
      onConfirm={() => close(true)}
      onCancel={() => close(false)}
    />
  );
}
