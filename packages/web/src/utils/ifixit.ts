export function getIFixitUrl(deviceName: string, customUrl?: string | null): string {
  if (customUrl) return customUrl;
  return `https://www.ifixit.com/Search?query=${encodeURIComponent(deviceName)}`;
}
