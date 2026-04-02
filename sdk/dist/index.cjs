"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/index.ts
var src_exports = {};
__export(src_exports, {
  RumSDK: () => RumSDK
});
module.exports = __toCommonJS(src_exports);

// src/buffer.ts
var EventBuffer = class {
  queue = [];
  timer = null;
  opts;
  constructor(opts) {
    this.opts = opts;
    this.timer = setInterval(() => this.flush(), opts.flushInterval);
  }
  add(event) {
    this.queue.push(event);
    if (this.queue.length >= this.opts.maxBatchSize) {
      this.flush();
    }
  }
  async flush() {
    if (this.queue.length === 0) return;
    const batch = this.queue.splice(0, this.opts.maxBatchSize);
    try {
      await this.opts.onFlush(batch);
    } catch {
      const combined = [...batch, ...this.queue];
      this.queue = combined.slice(-500);
    }
  }
  flushSync(sendBeacon) {
    if (this.queue.length === 0) return;
    sendBeacon(this.queue.splice(0));
  }
  size() {
    return this.queue.length;
  }
  destroy() {
    if (this.timer) clearInterval(this.timer);
  }
};

// src/transport.ts
var Transport = class {
  opts;
  constructor(opts) {
    this.opts = { maxRetries: 3, retryDelay: 1e3, ...opts };
  }
  async send(events) {
    const { endpoint, apiKey, maxRetries, retryDelay } = this.opts;
    const url = `${endpoint}/v1/events`;
    const body = JSON.stringify(events);
    const headers = { "Content-Type": "application/json", "x-api-key": apiKey };
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      const res = await fetch(url, { method: "POST", headers, body });
      if (res.ok) return;
      if (res.status < 500) throw new Error(`HTTP ${res.status}: non-retryable`);
      if (attempt === maxRetries) throw new Error(`HTTP ${res.status}: max retries exceeded`);
      await sleep(retryDelay * 2 ** (attempt - 1));
    }
  }
  sendBeacon(events, endpoint, apiKey) {
    const blob = new Blob([JSON.stringify(events)], { type: "application/json" });
    return navigator.sendBeacon(`${endpoint}/v1/events?apiKey=${apiKey}`, blob);
  }
};
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// src/utils/id.ts
function generateId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c2) => {
    const r = Math.random() * 16 | 0;
    return (c2 === "x" ? r : r & 3 | 8).toString(16);
  });
}

// src/utils/context.ts
function getBrowserContext() {
  const nav = navigator;
  const conn = nav.connection;
  return {
    url: location.pathname + location.search,
    device: {
      os: getOS(navigator.userAgent),
      browser: getBrowser(navigator.userAgent)
    },
    connection: {
      type: conn?.effectiveType ?? "unknown",
      rtt: conn?.rtt ?? 0
    }
  };
}
function getOS(ua) {
  if (/Windows/.test(ua)) return "Windows";
  if (/Mac OS X/.test(ua)) return "macOS";
  if (/Android/.test(ua)) return "Android";
  if (/iPhone|iPad/.test(ua)) return "iOS";
  if (/Linux/.test(ua)) return "Linux";
  return "unknown";
}
function getBrowser(ua) {
  if (/Edg\//.test(ua)) return "Edge";
  if (/Chrome\//.test(ua)) return "Chrome";
  if (/Firefox\//.test(ua)) return "Firefox";
  if (/Safari\//.test(ua)) return "Safari";
  return "unknown";
}

// src/collectors/error.ts
var SDK_FILENAMES = ["rum-sdk.min.js", "rum-sdk.js", "index.mjs", "index.cjs"];
var ErrorCollector = class {
  opts;
  onError;
  onRejection;
  constructor(opts) {
    this.opts = opts;
    this.onError = (e2) => {
      if (SDK_FILENAMES.some((f2) => e2.filename?.includes(f2))) return;
      opts.onEvent(this.makeEvent("js_error", {
        message: e2.message,
        stack: e2.error?.stack?.slice(0, 1e3) ?? "",
        filename: e2.filename,
        lineno: e2.lineno,
        colno: e2.colno
      }));
    };
    this.onRejection = (e2) => {
      const err = e2.reason instanceof Error ? e2.reason : new Error(String(e2.reason));
      opts.onEvent(this.makeEvent("unhandled_rejection", {
        message: err.message,
        stack: err.stack?.slice(0, 1e3) ?? ""
      }));
    };
    window.addEventListener("error", this.onError);
    window.addEventListener("unhandledrejection", this.onRejection);
  }
  makeEvent(name, payload) {
    const { sessionId, deviceId, appVersion } = this.opts;
    return {
      session_id: sessionId,
      user_id: "anonymous",
      device_id: deviceId,
      timestamp: Date.now(),
      platform: "web",
      app_version: appVersion,
      event_type: "error",
      event_name: name,
      payload,
      context: getBrowserContext()
    };
  }
  destroy() {
    window.removeEventListener("error", this.onError);
    window.removeEventListener("unhandledrejection", this.onRejection);
  }
};

// src/collectors/navigation.ts
var NavigationCollector = class {
  opts;
  onPopState;
  origPushState;
  origReplaceState;
  constructor(opts) {
    this.opts = opts;
    opts.onEvent(this.makeEvent("page_view", { url: location.href, referrer: document.referrer, duration: 0 }));
    this.origPushState = history.pushState.bind(history);
    this.origReplaceState = history.replaceState.bind(history);
    history.pushState = (...args) => {
      this.origPushState(...args);
      opts.onEvent(this.makeEvent("route_change", { url: location.href, referrer: "", duration: 0 }));
    };
    history.replaceState = (...args) => {
      this.origReplaceState(...args);
      opts.onEvent(this.makeEvent("route_change", { url: location.href, referrer: "", duration: 0 }));
    };
    this.onPopState = () => {
      opts.onEvent(this.makeEvent("route_change", { url: location.href, referrer: "", duration: 0 }));
    };
    window.addEventListener("popstate", this.onPopState);
  }
  makeEvent(name, payload) {
    const { sessionId, deviceId, appVersion } = this.opts;
    return {
      session_id: sessionId,
      user_id: "anonymous",
      device_id: deviceId,
      timestamp: Date.now(),
      platform: "web",
      app_version: appVersion,
      event_type: "navigation",
      event_name: name,
      payload,
      context: getBrowserContext()
    };
  }
  destroy() {
    history.pushState = this.origPushState;
    history.replaceState = this.origReplaceState;
    window.removeEventListener("popstate", this.onPopState);
  }
};

// node_modules/web-vitals/dist/web-vitals.js
var e;
var o = -1;
var a = function(e2) {
  addEventListener("pageshow", function(n) {
    n.persisted && (o = n.timeStamp, e2(n));
  }, true);
};
var c = function() {
  var e2 = self.performance && performance.getEntriesByType && performance.getEntriesByType("navigation")[0];
  if (e2 && e2.responseStart > 0 && e2.responseStart < performance.now()) return e2;
};
var u = function() {
  var e2 = c();
  return e2 && e2.activationStart || 0;
};
var f = function(e2, n) {
  var t = c(), r = "navigate";
  o >= 0 ? r = "back-forward-cache" : t && (document.prerendering || u() > 0 ? r = "prerender" : document.wasDiscarded ? r = "restore" : t.type && (r = t.type.replace(/_/g, "-")));
  return { name: e2, value: void 0 === n ? -1 : n, rating: "good", delta: 0, entries: [], id: "v4-".concat(Date.now(), "-").concat(Math.floor(8999999999999 * Math.random()) + 1e12), navigationType: r };
};
var s = function(e2, n, t) {
  try {
    if (PerformanceObserver.supportedEntryTypes.includes(e2)) {
      var r = new PerformanceObserver(function(e3) {
        Promise.resolve().then(function() {
          n(e3.getEntries());
        });
      });
      return r.observe(Object.assign({ type: e2, buffered: true }, t || {})), r;
    }
  } catch (e3) {
  }
};
var d = function(e2, n, t, r) {
  var i, o2;
  return function(a2) {
    n.value >= 0 && (a2 || r) && ((o2 = n.value - (i || 0)) || void 0 === i) && (i = n.value, n.delta = o2, n.rating = function(e3, n2) {
      return e3 > n2[1] ? "poor" : e3 > n2[0] ? "needs-improvement" : "good";
    }(n.value, t), e2(n));
  };
};
var l = function(e2) {
  requestAnimationFrame(function() {
    return requestAnimationFrame(function() {
      return e2();
    });
  });
};
var p = function(e2) {
  document.addEventListener("visibilitychange", function() {
    "hidden" === document.visibilityState && e2();
  });
};
var v = function(e2) {
  var n = false;
  return function() {
    n || (e2(), n = true);
  };
};
var m = -1;
var h = function() {
  return "hidden" !== document.visibilityState || document.prerendering ? 1 / 0 : 0;
};
var g = function(e2) {
  "hidden" === document.visibilityState && m > -1 && (m = "visibilitychange" === e2.type ? e2.timeStamp : 0, T());
};
var y = function() {
  addEventListener("visibilitychange", g, true), addEventListener("prerenderingchange", g, true);
};
var T = function() {
  removeEventListener("visibilitychange", g, true), removeEventListener("prerenderingchange", g, true);
};
var E = function() {
  return m < 0 && (m = h(), y(), a(function() {
    setTimeout(function() {
      m = h(), y();
    }, 0);
  })), { get firstHiddenTime() {
    return m;
  } };
};
var C = function(e2) {
  document.prerendering ? addEventListener("prerenderingchange", function() {
    return e2();
  }, true) : e2();
};
var b = [1800, 3e3];
var S = function(e2, n) {
  n = n || {}, C(function() {
    var t, r = E(), i = f("FCP"), o2 = s("paint", function(e3) {
      e3.forEach(function(e4) {
        "first-contentful-paint" === e4.name && (o2.disconnect(), e4.startTime < r.firstHiddenTime && (i.value = Math.max(e4.startTime - u(), 0), i.entries.push(e4), t(true)));
      });
    });
    o2 && (t = d(e2, i, b, n.reportAllChanges), a(function(r2) {
      i = f("FCP"), t = d(e2, i, b, n.reportAllChanges), l(function() {
        i.value = performance.now() - r2.timeStamp, t(true);
      });
    }));
  });
};
var L = [0.1, 0.25];
var w = function(e2, n) {
  n = n || {}, S(v(function() {
    var t, r = f("CLS", 0), i = 0, o2 = [], c2 = function(e3) {
      e3.forEach(function(e4) {
        if (!e4.hadRecentInput) {
          var n2 = o2[0], t2 = o2[o2.length - 1];
          i && e4.startTime - t2.startTime < 1e3 && e4.startTime - n2.startTime < 5e3 ? (i += e4.value, o2.push(e4)) : (i = e4.value, o2 = [e4]);
        }
      }), i > r.value && (r.value = i, r.entries = o2, t());
    }, u2 = s("layout-shift", c2);
    u2 && (t = d(e2, r, L, n.reportAllChanges), p(function() {
      c2(u2.takeRecords()), t(true);
    }), a(function() {
      i = 0, r = f("CLS", 0), t = d(e2, r, L, n.reportAllChanges), l(function() {
        return t();
      });
    }), setTimeout(t, 0));
  }));
};
var A = 0;
var I = 1 / 0;
var P = 0;
var M = function(e2) {
  e2.forEach(function(e3) {
    e3.interactionId && (I = Math.min(I, e3.interactionId), P = Math.max(P, e3.interactionId), A = P ? (P - I) / 7 + 1 : 0);
  });
};
var k = function() {
  return e ? A : performance.interactionCount || 0;
};
var F = function() {
  "interactionCount" in performance || e || (e = s("event", M, { type: "event", buffered: true, durationThreshold: 0 }));
};
var D = [];
var x = /* @__PURE__ */ new Map();
var R = 0;
var B = function() {
  var e2 = Math.min(D.length - 1, Math.floor((k() - R) / 50));
  return D[e2];
};
var H = [];
var q = function(e2) {
  if (H.forEach(function(n2) {
    return n2(e2);
  }), e2.interactionId || "first-input" === e2.entryType) {
    var n = D[D.length - 1], t = x.get(e2.interactionId);
    if (t || D.length < 10 || e2.duration > n.latency) {
      if (t) e2.duration > t.latency ? (t.entries = [e2], t.latency = e2.duration) : e2.duration === t.latency && e2.startTime === t.entries[0].startTime && t.entries.push(e2);
      else {
        var r = { id: e2.interactionId, latency: e2.duration, entries: [e2] };
        x.set(r.id, r), D.push(r);
      }
      D.sort(function(e3, n2) {
        return n2.latency - e3.latency;
      }), D.length > 10 && D.splice(10).forEach(function(e3) {
        return x.delete(e3.id);
      });
    }
  }
};
var O = function(e2) {
  var n = self.requestIdleCallback || self.setTimeout, t = -1;
  return e2 = v(e2), "hidden" === document.visibilityState ? e2() : (t = n(e2), p(e2)), t;
};
var N = [200, 500];
var j = function(e2, n) {
  "PerformanceEventTiming" in self && "interactionId" in PerformanceEventTiming.prototype && (n = n || {}, C(function() {
    var t;
    F();
    var r, i = f("INP"), o2 = function(e3) {
      O(function() {
        e3.forEach(q);
        var n2 = B();
        n2 && n2.latency !== i.value && (i.value = n2.latency, i.entries = n2.entries, r());
      });
    }, c2 = s("event", o2, { durationThreshold: null !== (t = n.durationThreshold) && void 0 !== t ? t : 40 });
    r = d(e2, i, N, n.reportAllChanges), c2 && (c2.observe({ type: "first-input", buffered: true }), p(function() {
      o2(c2.takeRecords()), r(true);
    }), a(function() {
      R = k(), D.length = 0, x.clear(), i = f("INP"), r = d(e2, i, N, n.reportAllChanges);
    }));
  }));
};
var _ = [2500, 4e3];
var z = {};
var G = function(e2, n) {
  n = n || {}, C(function() {
    var t, r = E(), i = f("LCP"), o2 = function(e3) {
      n.reportAllChanges || (e3 = e3.slice(-1)), e3.forEach(function(e4) {
        e4.startTime < r.firstHiddenTime && (i.value = Math.max(e4.startTime - u(), 0), i.entries = [e4], t());
      });
    }, c2 = s("largest-contentful-paint", o2);
    if (c2) {
      t = d(e2, i, _, n.reportAllChanges);
      var m2 = v(function() {
        z[i.id] || (o2(c2.takeRecords()), c2.disconnect(), z[i.id] = true, t(true));
      });
      ["keydown", "click"].forEach(function(e3) {
        addEventListener(e3, function() {
          return O(m2);
        }, { once: true, capture: true });
      }), p(m2), a(function(r2) {
        i = f("LCP"), t = d(e2, i, _, n.reportAllChanges), l(function() {
          i.value = performance.now() - r2.timeStamp, z[i.id] = true, t(true);
        });
      });
    }
  });
};

// src/collectors/web-vitals.ts
var WebVitalsCollector = class {
  constructor(opts) {
    const emit = (name, value, rating, navigationType) => {
      const { sessionId, deviceId, appVersion } = opts;
      opts.onEvent({
        session_id: sessionId,
        user_id: "anonymous",
        device_id: deviceId,
        timestamp: Date.now(),
        platform: "web",
        app_version: appVersion,
        event_type: "performance",
        event_name: name,
        payload: { value, rating, navigationType: navigationType ?? "navigate" },
        context: getBrowserContext()
      });
    };
    G((m2) => emit("lcp", m2.value, m2.rating, m2.navigationType));
    w((m2) => emit("cls", m2.value, m2.rating, m2.navigationType));
    j((m2) => emit("inp", m2.value, m2.rating, m2.navigationType));
  }
};

// src/collectors/resource.ts
var ResourceCollector = class {
  observer = null;
  constructor(opts) {
    if (typeof PerformanceObserver === "undefined") return;
    this.observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!["xmlhttprequest", "fetch"].includes(entry.initiatorType)) continue;
        const { sessionId, deviceId, appVersion } = opts;
        opts.onEvent({
          session_id: sessionId,
          user_id: "anonymous",
          device_id: deviceId,
          timestamp: Date.now(),
          platform: "web",
          app_version: appVersion,
          event_type: "resource",
          event_name: entry.initiatorType === "fetch" ? "fetch" : "xhr",
          payload: { url: entry.name, duration: Math.round(entry.duration), transferSize: entry.transferSize },
          context: getBrowserContext()
        });
      }
    });
    this.observer.observe({ type: "resource", buffered: true });
  }
  destroy() {
    this.observer?.disconnect();
  }
};

// src/index.ts
var _instance = null;
var RumSDK = class {
  static init(config) {
    if (_instance) return;
    if (Math.random() > (config.sampleRate ?? 1)) return;
    const sessionId = generateId();
    const deviceId = generateId();
    const transport = new Transport({ endpoint: config.endpoint, apiKey: config.apiKey });
    const buffer = new EventBuffer({
      maxBatchSize: config.maxBatchSize ?? 10,
      flushInterval: config.flushInterval ?? 3e4,
      onFlush: (events) => transport.send(events)
    });
    const collectorOpts = {
      sessionId,
      deviceId,
      appVersion: config.appVersion,
      onEvent: (e2) => buffer.add(e2)
    };
    const collectors = [
      new ErrorCollector(collectorOpts),
      new NavigationCollector(collectorOpts),
      new WebVitalsCollector(collectorOpts),
      new ResourceCollector(collectorOpts)
    ];
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        buffer.flushSync((events) => transport.sendBeacon(events, config.endpoint, config.apiKey));
      }
    });
    _instance = { buffer, transport, collectors, sessionId, deviceId, userId: "anonymous" };
  }
  static destroy() {
    if (!_instance) return;
    _instance.buffer.flush();
    _instance.buffer.destroy();
    _instance.collectors.forEach((c2) => c2.destroy());
    _instance = null;
  }
  static setUser(userId) {
    if (_instance) _instance.userId = userId;
  }
  static addCustomEvent(name, payload) {
    if (!_instance) return;
    _instance.buffer.add({
      session_id: _instance.sessionId,
      user_id: _instance.userId,
      device_id: _instance.deviceId,
      timestamp: Date.now(),
      platform: "web",
      app_version: "",
      event_type: "action",
      event_name: name,
      payload,
      context: { url: location.pathname, device: { os: "", browser: "" }, connection: { type: "", rtt: 0 } }
    });
  }
};
//# sourceMappingURL=index.cjs.map
