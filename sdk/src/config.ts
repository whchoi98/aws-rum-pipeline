export interface RumConfig {
  endpoint: string;
  apiKey: string;
  appVersion: string;
  sampleRate?: number;
  flushInterval?: number;
  maxBatchSize?: number;
  debug?: boolean;
}

export interface RumEvent {
  session_id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  platform: 'web';
  app_version: string;
  event_type: 'performance' | 'action' | 'error' | 'navigation' | 'resource';
  event_name: string;
  payload: Record<string, unknown>;
  context: {
    url: string;
    device: { os: string; browser: string };
    connection: { type: string; rtt: number };
  };
}
