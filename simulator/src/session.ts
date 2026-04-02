import { randomUUID } from 'crypto';

export interface SessionContext {
  session_id: string;
  user_id: string;
  device_id: string;
  platform: 'web';
  app_version: string;
  context: {
    url: string;
    device: { os: string; browser: string };
    connection: { type: string; rtt: number };
  };
}

const OS = ['macOS', 'Windows', 'Android', 'iOS', 'Linux'];
const BROWSERS = ['Chrome', 'Firefox', 'Safari', 'Edge'];
const CONNECTIONS = ['4g', '3g', 'wifi'];
const PAGES = ['/', '/products', '/cart', '/checkout', '/account'];

export function generateSession(appVersion = '2.1.0'): SessionContext {
  return {
    session_id: randomUUID(),
    user_id: Math.random() < 0.3 ? 'anonymous' : `user_${randomUUID().slice(0, 8)}`,
    device_id: randomUUID(),
    platform: 'web',
    app_version: appVersion,
    context: {
      url: PAGES[Math.floor(Math.random() * PAGES.length)],
      device: {
        os: OS[Math.floor(Math.random() * OS.length)],
        browser: BROWSERS[Math.floor(Math.random() * BROWSERS.length)],
      },
      connection: {
        type: CONNECTIONS[Math.floor(Math.random() * CONNECTIONS.length)],
        rtt: Math.floor(Math.random() * 200),
      },
    },
  };
}
