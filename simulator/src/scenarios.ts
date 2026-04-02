export interface ScenarioConfig {
  name: string;
  lcpMultiplier?: number;  // 1.0 = normal, 3.0 = slow
  errorRate?: number;      // fraction of error events that are "spiked"
}

export const scenarios: Record<string, ScenarioConfig> = {
  normal:     { name: 'normal',     lcpMultiplier: 1.0, errorRate: 0.05 },
  slowPage:   { name: 'slowPage',   lcpMultiplier: 3.0, errorRate: 0.08 },
  errorSpike: { name: 'errorSpike', lcpMultiplier: 1.2, errorRate: 0.80 },
};

export function pickScenario(): ScenarioConfig {
  const r = Math.random();
  if (r < 0.70) return scenarios.normal;
  if (r < 0.90) return scenarios.slowPage;
  return scenarios.errorSpike;
}
