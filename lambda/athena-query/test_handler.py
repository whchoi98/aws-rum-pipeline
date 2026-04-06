"""athena-query Lambda 테스트: SQL 안전성 검증, 쿼리 실행, 결과 파싱."""

import json
import os
from unittest.mock import patch, MagicMock
import pytest

# 환경변수 설정 (import 전)
os.environ["GLUE_DATABASE"] = "test_db"
os.environ["ATHENA_WORKGROUP"] = "test-workgroup"
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")


class TestAthenaQueryHandler:
    @patch("handler.athena")
    @patch("handler.time")
    def test_successful_select_query(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-001"
        }
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }
        mock_athena.get_query_results.return_value = {
            "ResultSet": {
                "Rows": [
                    {"Data": [{"VarCharValue": "event_type"}, {"VarCharValue": "count"}]},
                    {"Data": [{"VarCharValue": "page_view"}, {"VarCharValue": "100"}]},
                    {"Data": [{"VarCharValue": "click"}, {"VarCharValue": "50"}]},
                ]
            }
        }

        event = {"name": "query_tool", "input": {"sql": "SELECT event_type, count(*) as count FROM rum_events GROUP BY 1"}}
        result = handler(event, None)

        assert result["rowCount"] == 2
        assert result["columns"] == ["event_type", "count"]
        assert result["data"][0]["event_type"] == "page_view"
        assert result["data"][1]["count"] == "50"
        assert result["queryId"] == "qid-001"

    def test_missing_sql_returns_error(self):
        from handler import handler

        result = handler({"name": "tool", "input": {}}, None)
        assert "error" in result
        assert "sql" in result["error"].lower()

    def test_drop_table_blocked(self):
        from handler import handler

        result = handler({"name": "tool", "input": {"sql": "DROP TABLE rum_events"}}, None)
        assert "error" in result
        assert "SELECT" in result["error"]

    def test_insert_blocked(self):
        from handler import handler

        result = handler({"name": "tool", "input": {"sql": "INSERT INTO rum_events VALUES (1)"}}, None)
        assert "error" in result

    def test_delete_blocked(self):
        from handler import handler

        result = handler({"name": "tool", "input": {"sql": "DELETE FROM rum_events"}}, None)
        assert "error" in result

    @patch("handler.athena")
    @patch("handler.time")
    def test_show_query_allowed(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {"QueryExecutionId": "qid-show"}
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }
        mock_athena.get_query_results.return_value = {
            "ResultSet": {"Rows": [{"Data": [{"VarCharValue": "table_name"}]}]}
        }

        result = handler({"input": {"sql": "SHOW TABLES"}}, None)
        assert "error" not in result

    @patch("handler.athena")
    @patch("handler.time")
    def test_describe_query_allowed(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {"QueryExecutionId": "qid-desc"}
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }
        mock_athena.get_query_results.return_value = {
            "ResultSet": {"Rows": [{"Data": [{"VarCharValue": "col_name"}]}]}
        }

        result = handler({"input": {"sql": "DESCRIBE rum_events"}}, None)
        assert "error" not in result

    @patch("handler.athena")
    @patch("handler.time")
    def test_failed_query_returns_error(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {"QueryExecutionId": "qid-fail"}
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {
                "Status": {"State": "FAILED", "StateChangeReason": "Syntax error"}
            }
        }

        result = handler({"input": {"sql": "SELECT * FROM nonexistent"}}, None)
        assert "error" in result
        assert "FAILED" in result["error"]

    @patch("handler.athena")
    @patch("handler.time")
    def test_empty_result_set(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {"QueryExecutionId": "qid-empty"}
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }
        mock_athena.get_query_results.return_value = {
            "ResultSet": {"Rows": []}
        }

        result = handler({"input": {"sql": "SELECT * FROM rum_events WHERE 1=0"}}, None)
        assert result["data"] == []
        assert result["rowCount"] == 0

    @patch("handler.athena")
    @patch("handler.time")
    def test_mcp_gateway_event_format(self, mock_time, mock_athena):
        """MCP Gateway 호출 형식: event.name + event.input.sql"""
        from handler import handler

        mock_athena.start_query_execution.return_value = {"QueryExecutionId": "qid-mcp"}
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }
        mock_athena.get_query_results.return_value = {
            "ResultSet": {
                "Rows": [
                    {"Data": [{"VarCharValue": "total"}]},
                    {"Data": [{"VarCharValue": "42"}]},
                ]
            }
        }

        event = {"name": "athena_query", "input": {"sql": "SELECT count(*) as total FROM rum_events"}}
        result = handler(event, None)

        assert result["data"][0]["total"] == "42"
