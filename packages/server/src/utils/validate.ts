import { AppError } from '../middleware/errorHandler.js';

export function validatePrice(value: unknown, fieldName = 'price'): number {
  const num = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(num) || !isFinite(num) || num < 0) throw new AppError(`${fieldName} must be non-negative`, 400);
  if (num > 999999.99) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return Math.round(num * 100) / 100;
}

export function validateQuantity(value: unknown, fieldName = 'quantity'): number {
  const num = typeof value === 'number' ? value : parseInt(value as string, 10);
  if (isNaN(num) || num < 1) throw new AppError(`${fieldName} must be at least 1`, 400);
  if (num > 100000) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return num;
}

export function validateTextLength(value: string | undefined, maxLength: number, fieldName = 'text'): string {
  if (!value) return '';
  if (value.length > maxLength) throw new AppError(`${fieldName} exceeds ${maxLength} characters`, 400);
  return value;
}

/**
 * SEC-M10: Validate multiple string field lengths in one call.
 * Pass an object of field values and a rules map of fieldName → maxLength.
 * Skips undefined/null fields. Throws on first violation.
 */
export function validateInputLengths(
  data: Record<string, unknown>,
  rules: Record<string, number>,
): void {
  for (const [field, maxLen] of Object.entries(rules)) {
    const val = data[field];
    if (typeof val === 'string' && val.length > maxLen) {
      throw new AppError(`${field} exceeds ${maxLen} characters`, 400);
    }
  }
}
