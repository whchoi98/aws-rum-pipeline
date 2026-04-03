import { randomUUID } from 'crypto';

export interface SessionContext {
  session_id: string;
  user_id: string;
  device_id: string;
  platform: 'web' | 'ios' | 'android';
  app_version: string;
  context: {
    url: string;
    screen_name?: string;
    device: { os: string; browser: string; model?: string };
    connection: { type: string; rtt: number };
  };
}

// Platform distribution: web 60%, ios 25%, android 15%
const PLATFORMS: Array<{ platform: SessionContext['platform']; weight: number }> = [
  { platform: 'web', weight: 0.60 },
  { platform: 'ios', weight: 0.25 },
  { platform: 'android', weight: 0.15 },
];

const WEB_OS = ['macOS', 'Windows', 'Linux'];
const WEB_BROWSERS = ['Chrome', 'Firefox', 'Safari', 'Edge'];
const IOS_MODELS = ['iPhone 15', 'iPhone 14', 'iPhone 13', 'iPad Pro', 'iPad Air'];
const ANDROID_MODELS = ['Galaxy S24', 'Galaxy S23', 'Pixel 8', 'Pixel 7', 'OnePlus 12'];
const CONNECTIONS = ['4g', '3g', 'wifi'];
const WEB_PAGES = ['/', '/products', '/cart', '/checkout', '/account'];
const MOBILE_SCREENS = ['Home', 'ProductList', 'ProductDetail', 'Cart', 'Checkout', 'Account', 'Search'];

function pickPlatform(): SessionContext['platform'] {
  const r = Math.random();
  let acc = 0;
  for (const { platform, weight } of PLATFORMS) {
    acc += weight;
    if (r < acc) return platform;
  }
  return 'web';
}

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

export function generateSession(appVersion = '2.1.0'): SessionContext {
  const platform = pickPlatform();

  if (platform === 'ios') {
    return {
      session_id: randomUUID(), device_id: randomUUID(),
      user_id: Math.random() < 0.3 ? 'anonymous' : `user_${randomUUID().slice(0, 8)}`,
      platform, app_version: appVersion,
      context: {
        url: '', screen_name: pick(MOBILE_SCREENS),
        device: { os: `iOS ${14 + Math.floor(Math.random() * 4)}`, browser: 'Safari', model: pick(IOS_MODELS) },
        connection: { type: pick(CONNECTIONS), rtt: Math.floor(Math.random() * 150) },
      },
    };
  }

  if (platform === 'android') {
    return {
      session_id: randomUUID(), device_id: randomUUID(),
      user_id: Math.random() < 0.3 ? 'anonymous' : `user_${randomUUID().slice(0, 8)}`,
      platform, app_version: appVersion,
      context: {
        url: '', screen_name: pick(MOBILE_SCREENS),
        device: { os: `Android ${12 + Math.floor(Math.random() * 3)}`, browser: 'WebView', model: pick(ANDROID_MODELS) },
        connection: { type: pick(CONNECTIONS), rtt: Math.floor(Math.random() * 200) },
      },
    };
  }

  // web
  return {
    session_id: randomUUID(), device_id: randomUUID(),
    user_id: Math.random() < 0.3 ? 'anonymous' : `user_${randomUUID().slice(0, 8)}`,
    platform, app_version: appVersion,
    context: {
      url: pick(WEB_PAGES),
      device: { os: pick(WEB_OS), browser: pick(WEB_BROWSERS) },
      connection: { type: pick(CONNECTIONS), rtt: Math.floor(Math.random() * 200) },
    },
  };
}
