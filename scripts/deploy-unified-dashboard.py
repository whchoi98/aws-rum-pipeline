#!/usr/bin/env python3
"""Deploy premium RUM dashboard to Grafana — Datadog RUM 수준의 종합 대시보드."""
import json, urllib.request, os

GRAFANA_URL = os.environ.get("GRAFANA_URL", "https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com")
TOKEN = os.environ["TOKEN"]
DS_UID = "efhx8g5mrvuo0d"
DB = "rum_pipeline_db"
TBL = f"{DB}.rum_events"

# 날짜 필터 (오늘 + 어제)
DF = (
    "year = CAST(year(current_date) AS VARCHAR) "
    "AND month = LPAD(CAST(month(current_date) AS VARCHAR), 2, '0') "
    "AND day IN (LPAD(CAST(day(current_date) AS VARCHAR), 2, '0'), "
    "LPAD(CAST(day(date_add('day', -1, current_date)) AS VARCHAR), 2, '0'))"
)
PF = DF + " AND ('${platform}' = 'all' OR platform = '${platform}') AND ('${page}' = 'all' OR json_extract_scalar(context, '$.url') LIKE '%' || '${page}' || '%')"

# 오늘만
TDF = (
    "year = CAST(year(current_date) AS VARCHAR) "
    "AND month = LPAD(CAST(month(current_date) AS VARCHAR), 2, '0') "
    "AND day = LPAD(CAST(day(current_date) AS VARCHAR), 2, '0')"
)
TPF = TDF + " AND ('${platform}' = 'all' OR platform = '${platform}') AND ('${page}' = 'all' OR json_extract_scalar(context, '$.url') LIKE '%' || '${page}' || '%')"

# 어제만
YDF = (
    "year = CAST(year(current_date) AS VARCHAR) "
    "AND month = LPAD(CAST(month(current_date) AS VARCHAR), 2, '0') "
    "AND day = LPAD(CAST(day(date_add('day', -1, current_date)) AS VARCHAR), 2, '0')"
)

# ─── 색상 팔레트 ───
C = {
    "purple": "#8B5CF6", "blue": "#3B82F6", "cyan": "#06B6D4",
    "green": "#10B981", "yellow": "#F59E0B", "orange": "#F97316",
    "red": "#EF4444", "pink": "#EC4899", "indigo": "#6366F1",
    "teal": "#14B8A6", "slate": "#64748B", "bg_dark": "#1E1E2E",
}


def ds():
    return {"type": "grafana-athena-datasource", "uid": DS_UID}


def tgt(sql, ref="A"):
    return {
        "datasource": ds(),
        "connectionArgs": {"catalog": "AwsDataCatalog", "database": DB, "region": "ap-northeast-2", "resultReuseEnabled": False},
        "format": 1, "rawSQL": sql, "refId": ref,
    }


def multi_tgt(sqls):
    return [tgt(sql, chr(65 + i)) for i, sql in enumerate(sqls)]


def p(pid, title, ptype, x, y, w, h, sql, **kw):
    r = {
        "id": pid, "title": title, "type": ptype,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": ds(),
    }
    if isinstance(sql, list):
        r["targets"] = multi_tgt(sql)
    else:
        r["targets"] = [tgt(sql)]
    for k in ("description", "fieldConfig", "options", "transparent"):
        if k in kw:
            r[k] = kw[k]
    return r


def row(pid, title, y, collapsed=False):
    return {"id": pid, "type": "row", "title": title, "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}, "collapsed": collapsed, "panels": []}


def stat(pid, title, x, y, w, h, sql, color, unit=None, decimals=None):
    fc = {"defaults": {"color": {"mode": "fixed", "fixedColor": color}, "noValue": "0"}}
    if unit:
        fc["defaults"]["unit"] = unit
    if decimals is not None:
        fc["defaults"]["decimals"] = decimals
    return p(pid, title, "stat", x, y, w, h, sql,
             fieldConfig=fc,
             options={"colorMode": "background_solid", "textMode": "value_and_name", "graphMode": "none",
                      "reduceOptions": {"calcs": ["lastNotNull"]}})


def stat_thresh(pid, title, x, y, w, h, sql, steps, unit=None, decimals=None):
    fc = {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": steps}, "noValue": "0"}}
    if unit:
        fc["defaults"]["unit"] = unit
    if decimals is not None:
        fc["defaults"]["decimals"] = decimals
    return p(pid, title, "stat", x, y, w, h, sql,
             fieldConfig=fc,
             options={"colorMode": "background_solid", "textMode": "value_and_name", "graphMode": "area",
                      "reduceOptions": {"calcs": ["lastNotNull"]}})


def gauge(pid, title, x, y, w, h, sql, steps, unit="ms", vmin=0, vmax=8000, desc="", decimals=None):
    fc = {"defaults": {"unit": unit, "min": vmin, "max": vmax, "color": {"mode": "thresholds"},
                        "thresholds": {"mode": "absolute", "steps": steps}}}
    if decimals is not None:
        fc["defaults"]["decimals"] = decimals
    return p(pid, title, "gauge", x, y, w, h, sql, fieldConfig=fc, description=desc)


# ──────────────────────────────────────────────────────────────
# 패널 조립
# ──────────────────────────────────────────────────────────────
panels = []

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 1: Executive KPI Bar (관리자 핵심 KPI)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(100, "📊 핵심 KPI", 0))

# 8개 KPI — 세션, DAU, 페이지뷰, 에러, 에러율, 크래시, 평균 세션 시간, 액션
panels.append(stat(1, "세션", 0, 1, 3, 3,
    f"SELECT COUNT(DISTINCT session_id) AS v FROM {TBL} WHERE {TPF}", C["purple"]))
panels.append(stat(2, "DAU (고유 사용자)", 3, 1, 3, 3,
    f"SELECT COUNT(DISTINCT user_id) AS v FROM {TBL} WHERE {TPF}", C["indigo"]))
panels.append(stat(3, "페이지뷰", 6, 1, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_name='page_view' AND {TPF}", C["blue"]))
panels.append(stat(4, "액션", 9, 1, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_type='action' AND {TPF}", C["cyan"]))
panels.append(stat_thresh(5, "에러", 12, 1, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_type='error' AND {TPF}",
    [{"value": None, "color": C["green"]}, {"value": 100, "color": C["yellow"]}, {"value": 500, "color": C["red"]}]))
panels.append(stat_thresh(6, "에러율 (%)", 15, 1, 3, 3,
    f"SELECT ROUND(CAST(SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS DOUBLE)*100.0/NULLIF(COUNT(*),0),2) AS v FROM {TBL} WHERE {TPF}",
    [{"value": None, "color": C["green"]}, {"value": 3, "color": C["yellow"]}, {"value": 10, "color": C["red"]}], unit="percent"))
panels.append(stat(7, "크래시", 18, 1, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_name IN ('crash', 'anr') AND {TPF}", C["red"]))
panels.append(stat(8, "리소스 요청", 21, 1, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_type='resource' AND {TPF}", C["teal"]))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 2: 트래픽 추이 (시간별)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(200, "📈 트래픽 추이", 4))

# 시간별 이벤트 추이 (event_type별 스택)
sql_hourly_events = (
    f"SELECT hour AS h, "
    f"SUM(CASE WHEN event_type='performance' THEN 1 ELSE 0 END) AS performance, "
    f"SUM(CASE WHEN event_type='action' THEN 1 ELSE 0 END) AS action, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS error, "
    f"SUM(CASE WHEN event_type='resource' THEN 1 ELSE 0 END) AS resource, "
    f"SUM(CASE WHEN event_type='navigation' OR event_name='page_view' THEN 1 ELSE 0 END) AS navigation "
    f"FROM {TBL} WHERE {PF} GROUP BY 1 ORDER BY 1"
)
panels.append(p(10, "시간별 이벤트 추이 (유형별)", "barchart", 0, 5, 16, 7, sql_hourly_events,
    fieldConfig={"defaults": {"color": {"mode": "fixed"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "performance"}, "properties": [{"id": "color", "value": {"fixedColor": C["blue"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "action"}, "properties": [{"id": "color", "value": {"fixedColor": C["cyan"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "error"}, "properties": [{"id": "color", "value": {"fixedColor": C["red"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "resource"}, "properties": [{"id": "color", "value": {"fixedColor": C["teal"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "navigation"}, "properties": [{"id": "color", "value": {"fixedColor": C["purple"], "mode": "fixed"}}]},
        ]},
    options={"stacking": {"mode": "normal"}, "barWidth": 0.7, "legend": {"displayMode": "list", "placement": "bottom"}}))

# 시간별 고유 세션/사용자
sql_hourly_users = (
    f"SELECT hour AS h, "
    f"COUNT(DISTINCT session_id) AS sessions, "
    f"COUNT(DISTINCT user_id) AS users "
    f"FROM {TBL} WHERE {PF} GROUP BY 1 ORDER BY 1"
)
panels.append(p(11, "시간별 세션 & 사용자", "barchart", 16, 5, 8, 7, sql_hourly_users,
    fieldConfig={"defaults": {"color": {"mode": "fixed"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "sessions"}, "properties": [{"id": "color", "value": {"fixedColor": C["purple"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "users"}, "properties": [{"id": "color", "value": {"fixedColor": C["indigo"], "mode": "fixed"}}]},
        ]},
    options={"barWidth": 0.6, "legend": {"displayMode": "list", "placement": "bottom"}}))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 3: Core Web Vitals (성능)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(300, "⚡ Core Web Vitals", 12))

# 3개 게이지
panels.append(gauge(20, "LCP (최대 콘텐츠 페인트)", 0, 13, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75)) AS v FROM {TBL} WHERE event_name='lcp' AND {PF}",
    [{"value": None, "color": C["green"]}, {"value": 2500, "color": C["yellow"]}, {"value": 4000, "color": C["red"]}],
    desc="양호 < 2.5초 | 개선필요 < 4초 | 불량 > 4초"))

panels.append(gauge(21, "CLS (누적 레이아웃 시프트)", 8, 13, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75), 3) AS v FROM {TBL} WHERE event_name='cls' AND {PF}",
    [{"value": None, "color": C["green"]}, {"value": 0.1, "color": C["yellow"]}, {"value": 0.25, "color": C["red"]}],
    unit="", vmin=0, vmax=1, desc="양호 < 0.1 | 개선필요 < 0.25 | 불량 > 0.25", decimals=3))

panels.append(gauge(22, "INP (다음 페인트 상호작용)", 16, 13, 8, 5,
    f"SELECT ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75)) AS v FROM {TBL} WHERE event_name='inp' AND {PF}",
    [{"value": None, "color": C["green"]}, {"value": 200, "color": C["yellow"]}, {"value": 500, "color": C["red"]}],
    vmax=1000, desc="양호 < 200ms | 개선필요 < 500ms | 불량 > 500ms"))

# 등급 분포 (스택바)
sql_rating = (
    f"SELECT event_name AS metric, "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='good' THEN 1 ELSE 0 END) AS \"양호\", "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='needs-improvement' THEN 1 ELSE 0 END) AS \"개선필요\", "
    f"SUM(CASE WHEN json_extract_scalar(payload, '$.rating')='poor' THEN 1 ELSE 0 END) AS \"불량\" "
    f"FROM {TBL} WHERE event_type='performance' AND {PF} GROUP BY 1 ORDER BY 1"
)
panels.append(p(23, "CWV 등급 분포", "barchart", 0, 18, 12, 6, sql_rating,
    fieldConfig={"defaults": {"color": {"mode": "fixed"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "양호"}, "properties": [{"id": "color", "value": {"fixedColor": C["green"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "개선필요"}, "properties": [{"id": "color", "value": {"fixedColor": C["yellow"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "불량"}, "properties": [{"id": "color", "value": {"fixedColor": C["red"], "mode": "fixed"}}]},
        ]},
    options={"stacking": {"mode": "normal"}, "orientation": "horizontal", "barWidth": 0.7, "legend": {"displayMode": "list", "placement": "bottom"}}))

# LCP/CLS/INP 백분위수 (4열 stat)
sql_pct_all = (
    f"SELECT "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.50)) AS lcp_p50, "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS lcp_p75, "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.95)) AS lcp_p95, "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.99)) AS lcp_p99, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.50)) AS inp_p50, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS inp_p75, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.95)) AS inp_p95, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.99)) AS inp_p99 "
    f"FROM {TBL} WHERE event_type='performance' AND {PF}"
)
panels.append(p(24, "LCP & INP 백분위수 (P50/P75/P95/P99)", "table", 12, 18, 12, 6, sql_pct_all,
    fieldConfig={"defaults": {"unit": "ms", "color": {"mode": "palette-classic"}, "custom": {"align": "center"}}},
    description="LCP: ms, INP: ms"))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 4: 에러 & 크래시
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(400, "🔴 에러 & 크래시", 24))

# 시간별 에러 추이
sql_error_trend = (
    f"SELECT hour AS h, "
    f"SUM(CASE WHEN event_name='js_error' THEN 1 ELSE 0 END) AS js_error, "
    f"SUM(CASE WHEN event_name='crash' THEN 1 ELSE 0 END) AS crash, "
    f"SUM(CASE WHEN event_name='anr' THEN 1 ELSE 0 END) AS anr, "
    f"SUM(CASE WHEN event_name NOT IN ('js_error','crash','anr') AND event_type='error' THEN 1 ELSE 0 END) AS other "
    f"FROM {TBL} WHERE event_type='error' AND {PF} GROUP BY 1 ORDER BY 1"
)
panels.append(p(30, "시간별 에러 추이 (유형별)", "barchart", 0, 25, 12, 6, sql_error_trend,
    fieldConfig={"defaults": {"color": {"mode": "fixed"}},
        "overrides": [
            {"matcher": {"id": "byName", "options": "js_error"}, "properties": [{"id": "color", "value": {"fixedColor": C["red"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "crash"}, "properties": [{"id": "color", "value": {"fixedColor": C["pink"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "anr"}, "properties": [{"id": "color", "value": {"fixedColor": C["orange"], "mode": "fixed"}}]},
            {"matcher": {"id": "byName", "options": "other"}, "properties": [{"id": "color", "value": {"fixedColor": C["slate"], "mode": "fixed"}}]},
        ]},
    options={"stacking": {"mode": "normal"}, "barWidth": 0.7, "legend": {"displayMode": "list", "placement": "bottom"}}))

# 에러 유형 파이
sql_error_pie = f"SELECT event_name AS type, COUNT(*) AS cnt FROM {TBL} WHERE event_type='error' AND {PF} GROUP BY 1 ORDER BY 2 DESC"
panels.append(p(31, "에러 유형 분포", "piechart", 12, 25, 6, 6, sql_error_pie,
    options={"pieType": "donut", "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"]}}))

# 에러 영향 범위 (세션/사용자)
sql_error_impact = (
    f"SELECT event_name AS type, "
    f"COUNT(*) AS total, "
    f"COUNT(DISTINCT session_id) AS sessions, "
    f"COUNT(DISTINCT user_id) AS users "
    f"FROM {TBL} WHERE event_type='error' AND {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 10"
)
panels.append(p(32, "에러별 영향 범위", "table", 18, 25, 6, 6, sql_error_impact,
    description="에러 유형별 영향 세션/사용자 수"))

# 에러 상세 목록
sql_errors = (
    f"SELECT json_extract_scalar(payload, '$.message') AS error_message, "
    f"event_name AS type, COUNT(*) AS occurrences, "
    f"COUNT(DISTINCT session_id) AS sessions, "
    f"COUNT(DISTINCT user_id) AS users, "
    f"json_extract_scalar(payload, '$.filename') AS source, "
    f"MIN(from_unixtime(timestamp/1000)) AS first_seen, "
    f"MAX(from_unixtime(timestamp/1000)) AS last_seen "
    f"FROM {TBL} WHERE event_type='error' AND {PF} "
    f"GROUP BY 1, 2, 6 ORDER BY 3 DESC LIMIT 20"
)
panels.append(p(33, "에러 상세 목록 (Top 20)", "table", 0, 31, 24, 8, sql_errors,
    description="발생 빈도순 에러 목록 — 영향 세션/사용자 포함"))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 5: 리소스 & 네트워크
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(500, "🌐 리소스 & 네트워크", 39))

# 리소스 유형 분포
sql_res_type = f"SELECT event_name AS type, COUNT(*) AS cnt FROM {TBL} WHERE event_type='resource' AND {PF} GROUP BY 1"
panels.append(p(40, "리소스 유형", "piechart", 0, 40, 6, 7, sql_res_type,
    options={"pieType": "donut", "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"]}}))

# 에러 리소스 (HTTP 에러)
sql_res_errors = (
    f"SELECT json_extract_scalar(payload, '$.url') AS resource_url, "
    f"event_name AS type, COUNT(*) AS errors "
    f"FROM {TBL} WHERE event_type='resource' AND json_extract_scalar(payload, '$.status') >= '400' AND {PF} "
    f"GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 10"
)
panels.append(p(41, "실패 리소스 Top 10 (HTTP 4xx/5xx)", "table", 6, 40, 9, 7, sql_res_errors,
    description="HTTP 상태 400+ 리소스"))

# 느린 리소스
sql_res_slow = (
    f"SELECT json_extract_scalar(payload, '$.url') AS url, event_name AS type, "
    f"COUNT(*) AS calls, "
    f"ROUND(AVG(CAST(json_extract_scalar(payload, '$.duration') AS DOUBLE))) AS avg_ms, "
    f"ROUND(approx_percentile(CAST(json_extract_scalar(payload, '$.duration') AS DOUBLE), 0.95)) AS p95_ms, "
    f"ROUND(AVG(CAST(json_extract_scalar(payload, '$.transferSize') AS DOUBLE))/1024, 1) AS avg_kb "
    f"FROM {TBL} WHERE event_type='resource' AND {PF} "
    f"GROUP BY 1, 2 HAVING COUNT(*) > 1 ORDER BY 4 DESC LIMIT 10"
)
panels.append(p(42, "느린 리소스 Top 10 (평균 응답시간)", "table", 15, 40, 9, 7, sql_res_slow))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 6: 모바일 바이탈 (iOS/Android)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(600, "📱 모바일 바이탈", 47))

MF = DF + " AND platform IN ('ios', 'android')"

panels.append(stat(50, "iOS 세션", 0, 48, 3, 3,
    f"SELECT COUNT(DISTINCT session_id) AS v FROM {TBL} WHERE platform='ios' AND {TDF}", C["blue"]))
panels.append(stat(51, "Android 세션", 3, 48, 3, 3,
    f"SELECT COUNT(DISTINCT session_id) AS v FROM {TBL} WHERE platform='android' AND {TDF}", C["green"]))
panels.append(stat(52, "모바일 크래시", 6, 48, 3, 3,
    f"SELECT COUNT(*) AS v FROM {TBL} WHERE event_name IN ('crash','anr') AND {MF}", C["red"]))
panels.append(stat(53, "모바일 에러율 (%)", 9, 48, 3, 3,
    f"SELECT ROUND(CAST(SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS DOUBLE)*100.0/NULLIF(COUNT(*),0),2) AS v FROM {TBL} WHERE {MF}",
    C["orange"], unit="percent"))

# 모바일 화면별 성능
sql_mobile_screens = (
    f"SELECT json_extract_scalar(context, '$.screen_name') AS screen, "
    f"platform, COUNT(*) AS events, "
    f"COUNT(DISTINCT session_id) AS sessions, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS errors "
    f"FROM {TBL} WHERE platform IN ('ios','android') AND {DF} "
    f"GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 15"
)
panels.append(p(54, "모바일 화면별 트래픽", "table", 12, 48, 12, 7, sql_mobile_screens,
    description="iOS/Android 화면별 이벤트, 세션, 에러 수"))

# 모바일 OS 버전 분포
sql_mobile_os = (
    f"SELECT platform, json_extract_scalar(context, '$.device.os') AS os_version, "
    f"COUNT(DISTINCT session_id) AS sessions "
    f"FROM {TBL} WHERE platform IN ('ios','android') AND {DF} "
    f"GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 10"
)
panels.append(p(55, "모바일 OS 버전 분포", "barchart", 0, 51, 12, 4, sql_mobile_os,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 7: 사용자 분석
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(700, "👥 사용자 분석", 55))

# 플랫폼별 세션 비율
sql_plat = f"SELECT platform, COUNT(DISTINCT session_id) AS sessions FROM {TBL} WHERE {PF} GROUP BY 1"
panels.append(p(60, "플랫폼별 세션", "piechart", 0, 56, 6, 7, sql_plat,
    options={"pieType": "donut", "legend": {"displayMode": "table", "placement": "bottom", "values": ["value", "percent"]}}))

# 브라우저 분포
sql_br = f"SELECT json_extract_scalar(context, '$.device.browser') AS browser, COUNT(DISTINCT session_id) AS sessions FROM {TBL} WHERE {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 10"
panels.append(p(61, "브라우저 Top 10", "barchart", 6, 56, 6, 7, sql_br,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

# OS 분포
sql_os = f"SELECT json_extract_scalar(context, '$.device.os') AS os, COUNT(DISTINCT session_id) AS sessions FROM {TBL} WHERE {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 10"
panels.append(p(62, "OS Top 10", "barchart", 12, 56, 6, 7, sql_os,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

# 앱 버전 분포
sql_ver = f"SELECT app_version, COUNT(DISTINCT session_id) AS sessions FROM {TBL} WHERE app_version IS NOT NULL AND {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 10"
panels.append(p(63, "앱 버전별 세션", "barchart", 18, 56, 6, 7, sql_ver,
    fieldConfig={"defaults": {"color": {"mode": "palette-classic"}}},
    options={"orientation": "horizontal", "barWidth": 0.6}))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 8: 페이지/화면별 성능
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(800, "📄 페이지별 성능 분석", 63))

sql_views = (
    f"SELECT json_extract_scalar(context, '$.url') AS page, "
    f"COUNT(*) AS events, COUNT(DISTINCT session_id) AS sessions, "
    f"ROUND(approx_percentile(CASE WHEN event_name='lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS lcp_p75, "
    f"ROUND(approx_percentile(CASE WHEN event_name='cls' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75), 3) AS cls_p75, "
    f"ROUND(approx_percentile(CASE WHEN event_name='inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75)) AS inp_p75, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS errors, "
    f"ROUND(CAST(SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS DOUBLE)*100.0/NULLIF(COUNT(*),0), 1) AS error_pct "
    f"FROM {TBL} WHERE {PF} GROUP BY 1 ORDER BY 2 DESC LIMIT 20"
)
panels.append(p(70, "페이지별 CWV & 에러율", "table", 0, 64, 24, 8, sql_views,
    description="페이지별 핵심 웹 지표(LCP/CLS/INP) p75 및 에러율 — 상위 20개"))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 9: 세션 탐색기
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
panels.append(row(900, "🔍 세션 탐색기", 72))

sql_sess = (
    f"SELECT session_id, user_id, platform, "
    f"json_extract_scalar(context, '$.device.browser') AS browser, "
    f"json_extract_scalar(context, '$.device.os') AS os, "
    f"app_version AS ver, "
    f"COUNT(*) AS events, "
    f"SUM(CASE WHEN event_type='error' THEN 1 ELSE 0 END) AS errors, "
    f"SUM(CASE WHEN event_name='page_view' OR event_name='screen_view' THEN 1 ELSE 0 END) AS views, "
    f"SUM(CASE WHEN event_type='action' THEN 1 ELSE 0 END) AS actions, "
    f"MIN(from_unixtime(timestamp/1000)) AS started, "
    f"MAX(from_unixtime(timestamp/1000)) AS ended, "
    f"ROUND((MAX(timestamp) - MIN(timestamp))/1000.0, 1) AS duration_sec "
    f"FROM {TBL} WHERE {PF} "
    f"GROUP BY 1, 2, 3, 4, 5, 6 ORDER BY 7 DESC LIMIT 30"
)
panels.append(p(80, "세션 탐색기 (최근 30개)", "table", 0, 73, 24, 9, sql_sess,
    description="세션별 상세 — 이벤트/에러/뷰/액션/체류시간"))


# ──────────────────────────────────────────────────────────────
# 대시보드 조립 및 배포
# ──────────────────────────────────────────────────────────────
dashboard = {
    "uid": "rum-unified-v2",
    "title": "RUM — 실사용자 모니터링 (관리자 대시보드)",
    "description": "핵심 KPI, Core Web Vitals, 에러/크래시, 리소스, 모바일, 사용자 분석, 세션 탐색기",
    "schemaVersion": 39, "version": 1, "editable": True,
    "tags": ["rum", "monitoring", "admin"],
    "time": {"from": "now-24h", "to": "now"},
    "refresh": "5m",
    "fiscalYearStartMonth": 0,
    "liveNow": False,
    "style": "dark",
    "timezone": "browser",
    "templating": {"list": [
        {"name": "platform", "label": "플랫폼", "type": "custom",
         "current": {"text": "전체", "value": "all"},
         "options": [
             {"text": "전체", "value": "all", "selected": True},
             {"text": "Web", "value": "web"},
             {"text": "iOS", "value": "ios"},
             {"text": "Android", "value": "android"},
         ],
         "query": "all,web,ios,android"},
        {"name": "page", "label": "페이지/화면", "type": "custom",
         "current": {"text": "전체", "value": "all"},
         "options": [
             {"text": "전체", "value": "all", "selected": True},
             {"text": "홈 (/)", "value": "/"},
             {"text": "상품 (/products)", "value": "/products"},
             {"text": "장바구니 (/cart)", "value": "/cart"},
             {"text": "결제 (/checkout)", "value": "/checkout"},
             {"text": "계정 (/account)", "value": "/account"},
         ],
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
    print(f"✅ 배포 완료: status={resp.get('status')}, url={resp.get('url')}")
    print(f"   대시보드 UID: rum-unified-v2")
    print(f"   패널 수: {len(panels)}개")
except urllib.error.HTTPError as e:
    print(f"❌ HTTP {e.code} - {e.read().decode()[:500]}")
