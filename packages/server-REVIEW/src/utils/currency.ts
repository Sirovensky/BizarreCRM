/** Round a currency value to 2 decimal places to prevent float drift */
export function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}
