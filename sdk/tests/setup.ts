// Polyfill PromiseRejectionEvent for jsdom environments
if (typeof PromiseRejectionEvent === 'undefined') {
  class PromiseRejectionEventPolyfill extends Event {
    public readonly promise: Promise<unknown>;
    public readonly reason: unknown;

    constructor(type: string, init: { promise: Promise<unknown>; reason?: unknown }) {
      super(type, { bubbles: false, cancelable: true });
      this.promise = init.promise;
      this.reason = init.reason;
    }
  }
  (globalThis as unknown as Record<string, unknown>).PromiseRejectionEvent = PromiseRejectionEventPolyfill;
}
