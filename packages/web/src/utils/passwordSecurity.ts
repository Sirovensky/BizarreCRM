export type PasswordStrengthScore = 0 | 1 | 2 | 3 | 4;

export interface PasswordStrengthAssessment {
  score: PasswordStrengthScore;
  label: string;
  percent: number;
  isAcceptable: boolean;
  suggestions: string[];
}

export interface PasswordBreachResult {
  compromised: boolean;
  count: number;
}

interface PasswordContext {
  email?: string;
  shopName?: string;
  slug?: string;
}

const COMMON_PASSWORDS = new Set([
  '12345678',
  '11111111',
  'password',
  'password1',
  'password12',
  'password123',
  'qwerty123',
  'qwerty1234',
  'letmein123',
  'admin123',
  'welcome1',
  'welcome123',
  'iloveyou',
  'changeme',
  'bizarrecrm',
]);

const COMMON_FRAGMENTS = [
  'password',
  'qwerty',
  'letmein',
  'welcome',
  'admin',
  'login',
  'repairshop',
  'bizarrecrm',
];

const KEYBOARD_SEQUENCES = [
  'abcdefghijklmnopqrstuvwxyz',
  'zyxwvutsrqponmlkjihgfedcba',
  '0123456789',
  '9876543210',
  'qwertyuiop',
  'poiuytrewq',
  'asdfghjkl',
  'lkjhgfdsa',
  'zxcvbnm',
  'mnbvcxz',
];

export function assessSignupPassword(password: string, context: PasswordContext = {}): PasswordStrengthAssessment {
  const suggestions: string[] = [];
  const lower = password.toLowerCase();
  const classes = [
    /[a-z]/.test(password),
    /[A-Z]/.test(password),
    /\d/.test(password),
    /[^A-Za-z0-9]/.test(password),
  ].filter(Boolean).length;

  let score = 0;
  if (password.length >= 8) score = 1;
  if (password.length >= 10) score = 2;
  if (password.length >= 12) score = 3;
  if (password.length >= 16) score = 4;
  if (password.length >= 10 && classes >= 3) score += 1;

  const hasCommonPassword = COMMON_PASSWORDS.has(lower);
  const hasCommonFragment = COMMON_FRAGMENTS.some(fragment => lower.includes(fragment));
  const hasRepeatedRun = /(.)\1{2,}/.test(lower);
  const hasSequence = KEYBOARD_SEQUENCES.some(sequence => hasSequentialSlice(lower, sequence, 4));
  const contextMatch = findContextMatch(lower, context);

  if (password.length < 8) {
    suggestions.push('Use at least 8 characters.');
  }
  if (password.length < 12) {
    suggestions.push('Use 12 or more characters for an admin account.');
  }
  if (classes < 3 && password.length < 16) {
    suggestions.push('Mix upper/lowercase letters, numbers, or symbols.');
  }
  if (hasCommonPassword || hasCommonFragment) {
    suggestions.push('Avoid common passwords and obvious words.');
    score -= hasCommonPassword ? 3 : 2;
  }
  if (hasRepeatedRun) {
    suggestions.push('Avoid repeated characters.');
    score -= 1;
  }
  if (hasSequence) {
    suggestions.push('Avoid keyboard or number sequences.');
    score -= 1;
  }
  if (contextMatch) {
    suggestions.push(`Avoid using ${contextMatch} in the password.`);
    score -= 2;
  }

  const normalizedScore = clampScore(score);
  const label = ['Very weak', 'Weak', 'Fair', 'Good', 'Strong'][normalizedScore];
  const uniqueSuggestions = [...new Set(suggestions)].slice(0, 3);

  return {
    score: normalizedScore,
    label,
    percent: Math.max(8, (normalizedScore + 1) * 20),
    isAcceptable: password.length >= 8 && normalizedScore >= 3 && !hasCommonPassword && !contextMatch,
    suggestions: uniqueSuggestions,
  };
}

export async function checkPwnedPassword(password: string, signal?: AbortSignal): Promise<PasswordBreachResult> {
  if (!globalThis.crypto?.subtle) {
    throw new Error('Secure password hashing is unavailable in this browser.');
  }

  const sha1 = await sha1Hex(password);
  const prefix = sha1.slice(0, 5);
  const suffix = sha1.slice(5);
  const response = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
    cache: 'no-store',
    headers: { 'Add-Padding': 'true' },
    signal,
  });

  if (!response.ok) {
    throw new Error('Password breach check is unavailable.');
  }

  const lines = (await response.text()).split(/\r?\n/);
  for (const line of lines) {
    const [candidateSuffix, count] = line.trim().split(':');
    if (candidateSuffix?.toUpperCase() === suffix) {
      const parsedCount = Number.parseInt(count ?? '0', 10);
      return {
        compromised: Number.isFinite(parsedCount) && parsedCount > 0,
        count: Number.isFinite(parsedCount) ? parsedCount : 0,
      };
    }
  }

  return { compromised: false, count: 0 };
}

function clampScore(score: number): PasswordStrengthScore {
  return Math.max(0, Math.min(4, Math.round(score))) as PasswordStrengthScore;
}

function hasSequentialSlice(value: string, sequence: string, minLength: number): boolean {
  if (value.length < minLength) return false;
  for (let index = 0; index <= sequence.length - minLength; index += 1) {
    if (value.includes(sequence.slice(index, index + minLength))) return true;
  }
  return false;
}

function findContextMatch(password: string, context: PasswordContext): string | null {
  const tokens = new Set<string>();
  for (const value of [context.email, context.shopName, context.slug]) {
    for (const token of extractTokens(value ?? '')) {
      tokens.add(token);
    }
  }

  for (const token of tokens) {
    if (password.includes(token)) return token;
  }
  return null;
}

function extractTokens(value: string): string[] {
  const normalized = value.toLowerCase();
  const rawParts = normalized.split(/[^a-z0-9]+/).filter(Boolean);
  const emailLocal = normalized.includes('@') ? normalized.split('@')[0] : '';
  return [...rawParts, emailLocal].filter(token => token.length >= 4);
}

async function sha1Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await globalThis.crypto.subtle.digest('SHA-1', bytes);
  return Array.from(new Uint8Array(digest))
    .map(byte => byte.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
}
