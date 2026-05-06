import { useEffect } from 'react';

type ShortcutKind = 'save' | 'save-continue';

const SAVE_LABELS = [
  'save',
  'save changes',
  'update',
  'create',
  'record payment',
];

const SAVE_CONTINUE_LABELS = [
  'save and continue',
  'save & continue',
  'continue',
  'next',
];

function isDisabled(el: Element): boolean {
  return el instanceof HTMLButtonElement || el instanceof HTMLInputElement
    ? el.disabled
    : el.getAttribute('aria-disabled') === 'true';
}

function isVisible(el: Element): boolean {
  if (!(el instanceof HTMLElement)) return false;
  if (el.hidden || isDisabled(el)) return false;
  const style = window.getComputedStyle(el);
  if (style.display === 'none' || style.visibility === 'hidden') return false;
  return el.getClientRects().length > 0;
}

function labelFor(el: Element): string {
  if (el instanceof HTMLInputElement) return (el.value || el.getAttribute('aria-label') || '').trim().toLowerCase();
  return (el.getAttribute('aria-label') || el.textContent || '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function rootForActiveElement(): ParentNode {
  const active = document.activeElement as HTMLElement | null;
  const modal = active?.closest('[role="dialog"][aria-modal="true"]');
  return modal ?? document;
}

function closestForm(root: ParentNode): HTMLFormElement | null {
  const active = document.activeElement as HTMLElement | null;
  const activeForm = active?.closest('form');
  if (activeForm && (root === document || (root as Element).contains(activeForm))) return activeForm;

  const forms = Array.from(root.querySelectorAll('form')).filter(isVisible) as HTMLFormElement[];
  return forms.length === 1 ? forms[0] : null;
}

function clickElement(el: Element | null): boolean {
  if (!el || !isVisible(el)) return false;
  if (el instanceof HTMLElement) {
    el.click();
    return true;
  }
  return false;
}

function findExplicitTarget(root: ParentNode, form: HTMLFormElement | null, kind: ShortcutKind): Element | null {
  const attr = kind === 'save' ? '[data-shortcut-save], [data-shortcut="save"]' : '[data-shortcut-save-continue], [data-shortcut="save-continue"]';
  const scoped = form?.querySelector(attr);
  if (scoped && isVisible(scoped)) return scoped;
  const global = root.querySelector(attr);
  return global && isVisible(global) ? global : null;
}

function findLabeledButton(root: ParentNode, form: HTMLFormElement | null, labels: string[]): Element | null {
  const selector = 'button, input[type="submit"], input[type="button"]';
  const candidates = Array.from((form ?? root).querySelectorAll(selector)).filter(isVisible);
  return candidates.find((candidate) => labels.includes(labelFor(candidate))) ?? null;
}

function submitForm(form: HTMLFormElement | null): boolean {
  if (!form || !isVisible(form)) return false;
  if (typeof form.requestSubmit === 'function') form.requestSubmit();
  else form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
  return true;
}

function triggerShortcut(kind: ShortcutKind): boolean {
  const root = rootForActiveElement();
  const form = closestForm(root);
  const explicit = findExplicitTarget(root, form, kind);
  if (clickElement(explicit)) return true;

  if (kind === 'save-continue') {
    const continueButton = findLabeledButton(root, form, SAVE_CONTINUE_LABELS);
    if (clickElement(continueButton)) return true;
  }

  const saveButton = findLabeledButton(root, form, SAVE_LABELS);
  if (clickElement(saveButton)) return true;

  return submitForm(form);
}

export function useFormKeyboardShortcuts(enabled = true): void {
  useEffect(() => {
    if (!enabled) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.repeat) return;
      const hasPrimaryModifier = event.ctrlKey || event.metaKey;
      if (!hasPrimaryModifier || event.altKey || event.shiftKey) return;

      const key = event.key.toLowerCase();
      if (key !== 's' && key !== 'enter') return;

      const handled = triggerShortcut(key === 's' ? 'save' : 'save-continue');
      if (!handled) return;
      event.preventDefault();
      event.stopPropagation();
    };

    window.addEventListener('keydown', onKeyDown, { capture: true });
    return () => window.removeEventListener('keydown', onKeyDown, { capture: true });
  }, [enabled]);
}
