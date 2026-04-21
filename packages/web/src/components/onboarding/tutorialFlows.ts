/**
 * Tutorial flow definitions for SpotlightCoach.
 *
 * Each flow is a named sequence of DOM-anchored steps. The coach reads
 * `?tutorial=<flowId>&step=<key>` from the URL and looks for
 * `[data-tutorial-target="<flowId>:<key>"]` in the document. When the
 * declared event fires on the target element (or on `window` for custom
 * events), the step auto-advances without a manual Next button.
 *
 * Steps that lack a stable DOM anchor will fall back to the floating card
 * and are noted inline.
 */
import type { NavigateFunction } from 'react-router-dom';
import { onboardingApi } from '@/api/endpoints';

export interface SpotlightStep {
  key: string;
  title: string;
  body: string;
  /** Matches `data-tutorial-target="<flowId>:<key>"` */
  target: string;
  advanceOn: 'click' | 'change' | 'blur' | 'custom-event';
  /** Required when advanceOn === 'custom-event' */
  customEventName?: string;
  hint?: string;
}

export interface SpotlightFlow {
  id: string;
  steps: ReadonlyArray<SpotlightStep>;
}

// ─── settings flow ────────────────────────────────────────────────────────────

const settingsFlow: SpotlightFlow = {
  id: 'settings',
  steps: [
    {
      key: 'tax-class-editor',
      title: 'Set your tax rate',
      body: 'This is your Tax Classes table. Click the edit icon on a row, update the rate to match your region, then click Save.',
      target: 'settings:tax-class-editor',
      advanceOn: 'blur',
      hint: 'Most US shops use 6–10%. Changes take effect on the next ticket.',
    },
    {
      key: 'receipt-header-input',
      title: 'Personalise your receipt',
      body: 'Type a short tagline or shop address line in the Receipt Header field — it prints just below your logo on every receipt.',
      target: 'settings:receipt-header-input',
      advanceOn: 'blur',
      hint: 'e.g. "Thank you for your business!" or your shop\'s phone number.',
    },
    {
      key: 'business-hours-toggle',
      title: 'Set your opening hours',
      body: 'Toggle the days your shop is open and set the from/to times. Customers see these hours on status-update emails.',
      target: 'settings:business-hours-toggle',
      advanceOn: 'change',
      hint: 'Saturday and Sunday are off by default — toggle them on if you trade weekends.',
    },
    {
      key: 'add-user-cta',
      title: 'Add your first teammate',
      body: 'Click "Add User" to create a technician or cashier account. Your team can log in from any device on your network.',
      target: 'settings:add-user-cta',
      advanceOn: 'click',
      hint: 'Admins can do everything. Technicians can\'t change settings. Cashiers can only run the POS.',
    },
  ],
};

// ─── ticket flow ──────────────────────────────────────────────────────────────

const ticketFlow: SpotlightFlow = {
  id: 'ticket',
  steps: [
    {
      key: 'customer-picker',
      title: 'Pick a customer',
      body: 'Search by name, phone, or email — or leave it as Walk-in. The customer is tied to this ticket for notifications and history.',
      target: 'ticket:customer-picker',
      advanceOn: 'custom-event',
      customEventName: 'pos:customer-selected',
      hint: 'Type at least 2 characters to search. New customer? Just leave Walk-in and edit later.',
    },
    {
      key: 'device-template-button',
      title: 'Pick a device type',
      body: 'Tap a category tile — Mobile, Tablet, Laptop, etc. — to start describing the repair.',
      target: 'ticket:device-template-button',
      advanceOn: 'click',
      hint: 'If you have Device Templates set up in Settings, you can one-click a pre-priced job.',
    },
    {
      key: 'device-picker-option',
      title: 'Choose or describe the device',
      body: 'Search the device catalog or type the model name manually. Select a fault and enter the quoted price.',
      target: 'ticket:device-picker-option',
      // NOTE: this step targets the device-model search result row inside the drill-down.
      // If the catalog is empty or the drill step is skipped the target may not be in the
      // DOM — SpotlightCoach will fall back to the floating card automatically.
      advanceOn: 'custom-event',
      customEventName: 'pos:template-applied',
      hint: 'Not sure on the price yet? Use $0 — you can edit it before checkout.',
    },
    {
      key: 'repair-price-input',
      title: 'Confirm the repair price',
      body: 'Enter the quoted labor price in the price field. This is what you\'ll charge the customer unless you change it at checkout.',
      target: 'ticket:repair-price-input',
      advanceOn: 'blur',
      hint: 'Parts can be added at checkout. This is the labor quote only.',
    },
    {
      key: 'save-ticket-button',
      title: 'Save the ticket',
      body: 'Hit "Create Ticket" to save this job. The ticket appears on the Tickets page and in Kanban — no payment is taken yet.',
      target: 'ticket:save-ticket-button',
      advanceOn: 'custom-event',
      customEventName: 'pos:ticket-saved',
      hint: 'The customer gets a confirmation SMS if you have SMS set up.',
    },
  ],
};

// ─── checkout flow ────────────────────────────────────────────────────────────

const checkoutFlow: SpotlightFlow = {
  id: 'checkout',
  steps: [
    {
      key: 'load-ticket-in-pos',
      title: 'Pull the ticket back up',
      body: 'Go to the Tickets page or use Held Carts and load the ticket you just created into POS. The repair line will reappear in the cart.',
      target: 'checkout:load-ticket-in-pos',
      // NOTE: this target wraps a "Load in POS" button on the TicketDetailPage or HeldCarts panel.
      // If the user navigates via a different path the element may be absent — falls back gracefully.
      advanceOn: 'custom-event',
      customEventName: 'pos:cart-loaded',
      hint: 'You can also use the Held Carts button at the bottom of POS to reload a saved cart directly.',
    },
    {
      key: 'price-cell',
      title: 'Adjust the price if needed',
      body: 'Click the price on the repair line to edit it. Tap the field, change the value, then click away.',
      target: 'checkout:price-cell',
      advanceOn: 'blur',
      hint: 'If the job took more time or fewer parts than quoted, update it now.',
    },
    {
      key: 'add-part-button',
      title: 'Add a replacement part',
      body: 'Expand the repair line and click "Add part". Search inventory — try the sample "Screen assembly" part if you loaded sample data.',
      target: 'checkout:add-part-button',
      advanceOn: 'custom-event',
      customEventName: 'pos:part-added',
      hint: 'Parts reduce stock automatically when the invoice is paid.',
    },
    {
      key: 'internal-note-textarea',
      title: 'Leave an internal note',
      body: 'Drop a quick tech note in the internal notes field — e.g. "Replaced digitizer, tested touch, full charge cycle done". Only staff see this.',
      target: 'checkout:internal-note-textarea',
      advanceOn: 'blur',
      hint: 'Internal notes stay attached to the ticket forever, even after payment.',
    },
    {
      key: 'checkout-button',
      title: 'Open the checkout screen',
      body: 'Click "Checkout" at the bottom right to open the payment screen.',
      target: 'checkout:checkout-button',
      advanceOn: 'click',
    },
    {
      key: 'complete-payment-button',
      title: 'Take payment',
      body: 'Select a payment method, confirm the total, and click "Complete Sale". The invoice is created and the receipt is ready to print.',
      target: 'checkout:complete-payment-button',
      advanceOn: 'custom-event',
      customEventName: 'pos:payment-completed',
      hint: 'That\'s the full lifecycle: ticket → edit → parts → payment. You\'re ready for real jobs.',
    },
  ],
};

// ─── Registry ────────────────────────────────────────────────────────────────

export const SPOTLIGHT_FLOWS: Readonly<Record<string, SpotlightFlow>> = {
  settings: settingsFlow,
  ticket: ticketFlow,
  checkout: checkoutFlow,
};

export type TutorialFlowId = keyof typeof SPOTLIGHT_FLOWS;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Returns the key of the first step in the given flow. Use this to build
 * tutorial deep-links so the SpotlightCoach can look up the step by string key
 * instead of a numeric `step=0` index which it doesn't understand.
 */
export function firstStepKey(flowId: TutorialFlowId): string {
  return SPOTLIGHT_FLOWS[flowId].steps[0].key;
}

/**
 * Dismisses every tutorial permanently. Called by the "Skip all tutorials"
 * button in SpotlightCoach and can be reused by any other surface.
 *
 * 1. Sets `localStorage['tutorial.all.dismissed'] = '1'`.
 * 2. Calls `onboardingApi.patchState({ checklist_dismissed: true })`.
 * 3. Clears tutorial URL params and navigates to `/`.
 */
export async function dismissAllTutorials(navigate: NavigateFunction): Promise<void> {
  try {
    localStorage.setItem('tutorial.all.dismissed', '1');
  } catch { /* storage unavailable — still proceed */ }

  try {
    await onboardingApi.patchState({ checklist_dismissed: true });
  } catch { /* non-fatal */ }

  navigate('/', { replace: true });
}

/**
 * Handle flow completion (done or skip). Chains settings → ticket → checkout,
 * then returns to the dashboard. On skip, always goes straight to `/`.
 */
export async function handleTutorialComplete(
  flowId: TutorialFlowId,
  reason: 'done' | 'skip',
  navigate: NavigateFunction,
): Promise<void> {
  if (flowId === 'settings' && reason === 'done') {
    try {
      await onboardingApi.patchState({ advanced_settings_unlocked: true });
    } catch { /* non-fatal */ }
  }

  const next: Partial<Record<TutorialFlowId, string>> = {
    settings: '/pos?tutorial=ticket&step=customer-picker',
    ticket: '/pos?tutorial=checkout&step=load-ticket-in-pos',
  };

  if (reason === 'done' && next[flowId]) {
    navigate(next[flowId]!);
    return;
  }

  // Skip or final flow — drop params and land on the dashboard.
  navigate('/');
}
