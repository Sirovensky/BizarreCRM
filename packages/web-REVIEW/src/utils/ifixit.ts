export function getIFixitUrl(deviceName: string, customUrl?: string | null): string {
  // Only honour the custom URL if it's an http(s) link — an admin-supplied
  // `javascript:` / `data:` value would otherwise flow directly into the
  // anchor `href` and execute on click. Fall back to the generated search URL
  // if the custom value fails validation.
  if (customUrl && /^https?:\/\//i.test(customUrl)) return customUrl;
  return `https://www.ifixit.com/Search?query=${encodeURIComponent(deviceName)}`;
}
