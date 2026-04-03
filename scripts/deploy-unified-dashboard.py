#!/usr/bin/env python3
"""Deploy RUM unified dashboard to Grafana."""
import json, urllib.request, os

GRAFANA_URL = os.environ.get("GRAFANA_URL", "https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com")
TOKEN = os.environ["TOKEN"]
DS_UID = "efhx8g5mrvuo0d"
DB = "rum_pipeline_db"
DF = (
    "year = CAST(year(current_date) AS VARCHAR) "
    "AND month = LPAD(CAST(month(current_date) AS VARCHAR), 2, '0') "
    "AND day IN (LPAD(CAST(day(current_date) AS VARCHAR), 2, '0'), "
    "LPAD(CAST(day(date_add('day', -1, current_date)) AS VARCHAR), 2, '0'))"
)
PF = DF + " AND ('${platform}' = 'all' OR platform = '${platform}') AND ('${page}' = 'all' OR json_extract_scalar(context, '$.url') = '${page}')"


def ds():
    return {"type": "grafana-athena-datasource", "uid": DS_UID}


def tgt(sql, ref="A"):
    return {
        "datasource": ds(),
        "connectionArgs": {"catalog": "AwsDataCatalog", "database": DB, "region": "ap-northeast-2", "resultReuseEnabled": False},
        "format": 1, "rawSQL": sql, "refId": ref,
    }


def panel(pid, title, ptype, x, y, w, h, sql, **kw):
    r = {
        "id": pid, "title": title, "type": ptype,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": ds(), "targets": [tgt(sql)],
    }
    for k in ("description", "fieldConfig", "options", "transparent"):
        if k in kw:
            r[k] = kw[k]
    return r


def row(pid, title, y):
    return {"id": pid, "type": "row", "title": title, "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}, "collapsed": False, "panels": []}


def stat_bg(pid, title, x, y, w, h, sql, color, unit=None):
    fc = {"defaults": {"color": {"mode": "fixed", "fixedColor": color}, "noValue": "0"}}
    if unit:
        fc["defaults"]["unit"] = unit
    return panel(pid, title, "stat", x, y, w, h, sql,
                 fieldConfig=fc,
                 options={"colorMode": "background", "textMode": "value_and_name", "graphMode": "none"})


def stat_thresh(pid, title, x, y, w, h, sql, steps, unit=None):
    fc = {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"steps": steps}, "noValue": "0"}}
    if unit:
        fc["defaults"]["unit"] = unit
    return panel(pid, title, "stat", x, y, w, h, sql,
                 fieldConfig=fc,
                 options={"colorMode": "background", "textMode": "value_and_name", "graphMode": "none"})


def gauge(pid, title, x, y, w, h, sql, steps, unit="ms", vmin=0, vmax=8000, desc="", decimals=None):
    fc = {"defaults": {"unit": unit, "min": vmin, "max": vmax, "color": {"mode": "thresholds"},
                        "thresholds": {"mode": "absolute", "steps": steps}}}
    if decimals is not None:
        fc["defaults"]["decimals"] = decimals
    return panel(pid, title, "gauge", x, y, w, h, sql, fieldConfig=fc, description=desc)


# ============================================================
# Build dashboard
# ============================================================
panels = []

# --- Top Bar: Key Metrics ---
panels.append(row(300, "", 0))

panels.append(stat_bg(1, "\uc138\uc158", 0, 1, 4, 3,
    f"SELECT COUNT(DISTINCT session_id) AS v FROM {DB}.rum_events WHERE {PF}", "#7B61FF"))
panels.append(stat_bg(2, "\ud398\uc774\uc9c0\ubdf0", 4, 1, 4, 3,
    f"SELECT COUNT(*) AS v FROM {DB}.rum_events WHERE event_name='page_view' AND {PF}", "#3B78E7"))
panels.append(stat_bg(3, "\uc5d0\ub7ec", 8, 1, 4, 3,
    f"SELECT COUNT(*) AS v FROM {DB}.rum_events WHERE event_type='error' AND {PF}", "#F2495C"))
panels.append(stat_thresh(4, "\uc5d0\ub7ec\uc728", 12, 1, 4, 3,
    f"SELECT ROUND(CAST(SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS DOUBLE)*100.0/NULLIF(COUNT(*),0),2) AS v FROM {DB}.rum_events WHERE {PF}",
    [{"value": None, "color": "#73BF69"}, {"value": 5, "color": "#FF9830"}, {"value": 10, "color": "#F2495C"}], unit="percent"))
panels.append(stat_bg(5, "\uc561\uc158", 16, 1, 4, 3,
    f"SELECT COUNT(*) AS v FROM {DB}.rum_events WHERE event_type='action' AND {PF}", "#FF9830"))
panels.append(stat_bg(6, "\ub9ac\uc18c\uc2a4", 20, 1, 4, 3,
    f"SELECT COUNT(*) AS v FROM {DB}.rum_events WHERE event_type='resource' AND {PF}", "#33B5E5"))

# --- Performance Overview ---
panels.append(row(301, "\uc131\ub2a5 \uac1c\uc694", 4))

panels.append(gauge(10, "\ucd5c\ub300 \ucf58\ud150\uce20 \ud398\uc778\ud2b8 (LCP)", 0, 5, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75)) AS v FROM {DB}.rum_events WHERE event_name='lcp' AND {PF}",
    [{"value": None, "color": "#73BF69"}, {"value": 2500, "color": "#FF9830"}, {"value": 4000, "color": "#F2495C"}],
    desc="\uc591\ud638 < 2.5\ucd08 | \uac1c\uc120\ud544\uc694 < 4\ucd08 | \ubd88\ub7c9 > 4\ucd08"))

panels.append(gauge(11, "\ub204\uc801 \ub808\uc774\uc544\uc6c3 \uc2dc\ud504\ud2b8 (CLS)", 8, 5, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75), 3) AS v FROM {DB}.rum_events WHERE event_name='cls' AND {PF}",
    [{"value": None, "color": "#73BF69"}, {"value": 0.1, "color": "#FF9830"}, {"value": 0.25, "color": "#F2495C"}],
    unit="", vmin=0, vmax=1, desc="\uc591\ud638 < 0.1 | \uac1c\uc120\ud544\uc694 < 0.25 | \ubd88\ub7c9 > 0.25", decimals=3))

panels.append(gauge(12, "\ub2e4\uc74c \ud398\uc778\ud2b8\uae4c\uc9c0 \uc0c1\ud638\uc791\uc6a9 (INP)", 16, 5, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75)) AS v FROM {DB}.rum_events WHERE event_name='inp' AND {PF}",
    [{"value": None, "color": "#73BF69"}, {"value": 200, "color": "#FF9830"}, {"value": 500, "color": "#F2495C"}],
    vmax=1000, desc="\uc591\ud638 < 200ms | \uac1c\uc120\ud544\uc694 < 500ms | \ubd88\ub7c9 > 500ms"))

# Rating Distribution (stacked bar)
sql_rating = (
    f"SELECT event_name AS metric, "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='good' THEN 1 ELSE 0 END) AS good, "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='needs-improvement' THEN 1 ELSE 0 END) AS needs_improvement, "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='poor' THEN 1 ELSE 0 END) AS poor "
    f"FROM {DB}.rum_events WHERE event_type='performance' AND {PF} GROUP BY 1 ORDER BY 1"
)
panels.append(panel(13, "\ud575\uc2ec \uc6f9 \uc9c0\ud45c \u2014 \ub4f1\uae09 \ubd84\ud3ec", "barchart", 0, 10, 16, 6, sql_rating,
    fieldConfig={"defaults": {"color": {"mode": "fixed"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "good"}, "properties": [{"id": "color", "value": {"fixedColor": "#73BF69", "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "needs_improvement"}, "properties": [{"id": "color", "value": {"fixedColor": "#FF9830", "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "poor"}, "properties": [{"id": "color", "value": {"fixedColor": "#F2495C", "mode": "fixed"}}]},
        ]},
    options={"stacking": {"mode": "normal"}, "orientation": "horizontal", "barWidth": 0.7, "legend": {"displayMode": "list", "placement": "bottom"}}))

# Percentiles
sql_pct = (
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.50)) AS p50, "
    f"ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75)) AS p75, "
    f"ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.95)) AS p95, "
    f"ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.99)) AS p99 "
    f"FROM {DB}.rum_events WHERE event_name='lcp' AND {PF}"
)
panels.append(panel(14, "LCP \ubc31\ubd84\uc704\uc218", "stat", 16, 10, 8, 6, sql_pct,
    fieldConfig={"defaults": {"unit": "ms", "color": {"mode": "palette-classic"}}},
    options={"textMode": "value_and_name", "colorMode": "value", "graphMode": "none"}))

# --- Errors ---
panels.append(row(302, "\uc5d0\ub7ec \ucd94\uc801", 16))

sql_errors = (
    f"SELECT json_extract_scalar(payload, '$.message') AS error_message, "
    f"event_name AS type, COUNT(*) AS occurrences, "
    f"COUNT(DISTINCT session_id) AS impacted_sessions, "
    f"COUNT(DISTINCT user_id) AS impacted_users, "
    f"json_extract_scalar(payload, '$.filename') AS source, "
    f"MIN(from_unixtime(timestamp/1000)) AS first_seen, "
    f"MAX(from_unixtime(timestamp/1000)) AS last_seen "
    f"FROM {DB}.rum_events WHERE event_type='error' AND {PF} "
    f"GROUP BY 1, 2, 6 ORDER BY 3 DESC LIMIT 15"
)
panels.append(panel(20, "\uc5d0\ub7ec \ubaa9\ub85d", "table", 0, 17, 24, 8, sql_errors,
    description="\ubc1c\uc0dd \ube48\ub3c4\uc21c \uc5d0\ub7ec \ubaa9\ub85d \u2014 \uc601\ud5a5 \uc138\uc158/\uc0ac\uc6a9\uc790 \ud3ec\ud568"))

# --- Resources ---
panels.append(row(303, "\ub9ac\uc18c\uc2a4", 25))

sql_res_type = f"SELECT event_name AS type, COUNT(*) AS cnt FROM {DB}.rum_events WHERE event_type='resource' AND {PF} GROUP BY 1"
panels.append(panel(30, "\ub9ac\uc18c\uc2a4 \uc720\ud615", "piechart", 0, 26, 8, 7, sql_res_type,
    options={"pieType": "donut", "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"]}}))

sql_res_slow = (
    f"SELECT json_extract_scalar(payload, '$.url') AS resource_url, event_name AS type, "
    f"COUNT(*) AS calls, "
    f"ROUND(AVG(CAST(json_extract_scalar(payload, '$.duration') AS DOUBLE))) AS avg_ms, "
    f"ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.duration') AS DOUBLE), 0.95)) AS p95_ms, "
    f"ROUND(AVG(CAST(json_extract_scalar(payload, '$.transferSize') AS DOUBLE))/1024, 1) AS avg_kb "
    f"FROM {DB}.rum_events WHERE event_type='resource' AND {PF} "
    f"GROUP BY 1, 2 ORDER BY 4 DESC LIMIT 10"
)
panels.append(panel(31, "\ub290\ub9b0 \ub9ac\uc18c\uc2a4 Top 10", "table", 8, 26, 16, 7, sql_res_slow,
    description="\ud3c9\uade0 \uc751\ub2f5\uc2dc\uac04 \uae30\uc900 \uac00\uc7a5 \ub290\ub9b0 \ub9ac\uc18c\uc2a4"))

# --- User Sessions ---
panels.append(row(304, "\uc0ac\uc6a9\uc790 \uc138\uc158", 33))

sql_sess_plat = f"SELECT platform, COUNT(DISTINCT session_id) AS sessions FROM {DB}.rum_events WHERE {PF} GROUP BY 1"
panels.append(panel(40, "\ud50c\ub7ab\ud3fc\ubcc4", "piechart", 0, 34, 6, 7, sql_sess_plat,
    options={"pieType": "donut", "legend": {"displayMode": "table", "placement": "bottom", "values": ["value", "percent"]}}))

sql_sess_br = f"SELECT json_extract_scalar(context, '$.device.browser') AS browser, COUNT(DISTINCT session_id) AS sessions FROM {DB}.rum_events WHERE {PF} GROUP BY 1 ORDER BY 2 DESC"
panels.append(panel(41, "\ube0c\ub77c\uc6b0\uc800\ubcc4", "barchart", 6, 34, 9, 7, sql_sess_br,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

sql_sess_os = f"SELECT json_extract_scalar(context, '$.device.os') AS os, COUNT(DISTINCT session_id) AS sessions FROM {DB}.rum_events WHERE {PF} GROUP BY 1 ORDER BY 2 DESC"
panels.append(panel(42, "\uc6b4\uc601\uccb4\uc81c\ubcc4", "barchart", 15, 34, 9, 7, sql_sess_os,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

sql_sess_explore = (
    f"SELECT session_id, user_id, "
    f"json_extract_scalar(context, '$.device.browser') AS browser, "
    f"json_extract_scalar(context, '$.device.os') AS os, "
    f"COUNT(*) AS events, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS errors, "
    f"SUM(CASE WHEN event_name='page_view' THEN 1 ELSE 0 END) AS views, "
    f"MIN(from_unixtime(timestamp/1000)) AS started, "
    f"MAX(from_unixtime(timestamp/1000)) AS ended "
    f"FROM {DB}.rum_events WHERE {PF} "
    f"GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC LIMIT 20"
)
panels.append(panel(43, "\uc138\uc158 \ud0d0\uc0c9\uae30", "table", 0, 41, 24, 8, sql_sess_explore,
    description="\ucd5c\uadfc \uc138\uc158\ubcc4 \ud65c\ub3d9 \uc0c1\uc138 (\uc774\ubca4\ud2b8/\uc5d0\ub7ec/\ud398\uc774\uc9c0\ubdf0/\uc2dc\uc791-\uc885\ub8cc)"))

# --- Views Performance ---
panels.append(row(305, "\ud398\uc774\uc9c0\ubcc4 \uc131\ub2a5", 49))

sql_views = (
    f"SELECT json_extract_scalar(context, '$.url') AS view_name, "
    f"COUNT(*) AS total_events, COUNT(DISTINCT session_id) AS sessions, "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS lcp_p75_ms, "
    f"ROUND(approx_percentile(CASE WHEN event_name='cls' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75), 3) AS cls_p75, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS inp_p75_ms, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS errors, "
    f"ROUND(CAST(SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS DOUBLE)*100.0/NULLIF(COUNT(*),0), 1) AS error_rate "
    f"FROM {DB}.rum_events WHERE {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 15"
)
panels.append(panel(50, "\ud398\uc774\uc9c0\ubcc4 \uc131\ub2a5 \uc9c0\ud45c", "table", 0, 50, 24, 8, sql_views,
    description="\ud398\uc774\uc9c0\ubcc4 \ud575\uc2ec \uc6f9 \uc9c0\ud45c(CWV) \ubc0f \uc5d0\ub7ec\uc728 \uc0c1\uc138"))

# ============================================================
# Assemble and deploy
# ============================================================
dashboard = {
    "uid": "rum-unified",
    "title": "RUM \u2014 \uc2e4\uc0ac\uc6a9\uc790 \ubaa8\ub2c8\ud130\ub9c1",
    "description": "\uc138\uc158, \uc131\ub2a5, \uc5d0\ub7ec, \ub9ac\uc18c\uc2a4, \uc0ac\uc6a9\uc790 \uc138\uc158 \ud1b5\ud569 \ub300\uc2dc\ubcf4\ub4dc",
    "schemaVersion": 39, "version": 1, "editable": True,
    "tags": ["rum", "monitoring"],
    "time": {"from": "now-24h", "to": "now"},
    "templating": {"list": [
        {"name": "platform", "label": "\ud50c\ub7ab\ud3fc", "type": "custom",
         "current": {"text": "All", "value": "all"},
         "options": [{"text": "\uc804\uccb4", "value": "all", "selected": True}, {"text": "Web", "value": "web"}, {"text": "iOS", "value": "ios"}, {"text": "Android", "value": "android"}],
         "query": "all,web,ios,android"},
        {"name": "page", "label": "\ud398\uc774\uc9c0", "type": "custom",
         "current": {"text": "\uc804\uccb4 \ud398\uc774\uc9c0", "value": "all"},
         "options": [{"text": "\uc804\uccb4 \ud398\uc774\uc9c0", "value": "all", "selected": True}, {"text": "\ud648 (/)", "value": "/"}, {"text": "\uc0c1\ud488 (/products)", "value": "/products"}, {"text": "\uc7a5\ubc14\uad6c\ub2c8 (/cart)", "value": "/cart"}, {"text": "\uacb0\uc81c (/checkout)", "value": "/checkout"}, {"text": "\uacc4\uc815 (/account)", "value": "/account"}],
         "query": "all,/,/products,/cart,/checkout,/account"},
    ]},
    "panels": panels,
    "id": None,
}

payload = json.dumps({"dashboard": dashboard, "overwrite": True}).encode()
req = urllib.request.Request(
    f"{GRAFANA_URL}/api/dashboards/db", data=payload,
    headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}, method="POST"
)
try:
    resp = json.loads(urllib.request.urlopen(req).read())
    print(f"status={resp.get('status')}, url={resp.get('url')}")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code} - {e.read().decode()[:500]}")
