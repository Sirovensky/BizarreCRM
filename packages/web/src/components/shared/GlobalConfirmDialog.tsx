import { ConfirmDialog } from './ConfirmDialog';
import { useConfirmStore } from '@/stores/confirmStore';

export function GlobalConfirmDialog() {
  const { open, title, message, confirmLabel, danger, close } = useConfirmStore();

  return (
    <ConfirmDialog
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
