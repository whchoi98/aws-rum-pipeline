import type { RumEvent } from '../config';

type Context = RumEvent['context'];

export function getBrowserContext(): Context {
  const nav = navigator as Navigator & { connection?: { effectiveType?: string; rtt?: number } };
  const conn = nav.connection;
  return {
    url: location.pathname + location.search,
    device: {
      os: getOS(navigator.userAgent),
      browser: getBrowser(navigator.userAgent),
    },
    connection: {
      type: conn?.effectiveType ?? 'unknown',
      rtt: conn?.rtt ?? 0,
    },
  };
}

function getOS(ua: string): string {
  if (/Windows/.test(ua)) return 'Windows';
  if (/Mac OS X/.test(ua)) return 'macOS';
  if (/Android/.test(ua)) return 'Android';
  if (/iPhone|iPad/.test(ua)) return 'iOS';
  if (/Linux/.test(ua)) return 'Linux';
  return 'unknown';
}

function getBrowser(ua: string): string {
  if (/Edg\//.test(ua)) return 'Edge';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Firefox\//.test(ua)) return 'Firefox';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'unknown';
}
