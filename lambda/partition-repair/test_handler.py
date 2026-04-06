"""partition-repair Lambda 테스트: MSCK REPAIR TABLE 실행 및 폴링 검증."""

import json
import os
from unittest.mock import patch, MagicMock
import pytest

# 환경변수 설정 (import 전)
os.environ["GLUE_DATABASE"] = "test_db"
os.environ["GLUE_TABLE"] = "test_table"
os.environ["ATHENA_WORKGROUP"] = "test-workgroup"
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")


class TestPartitionRepairHandler:
    @patch("handler.athena")
    @patch("handler.time")
    def test_successful_repair(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-123"
        }
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }

        result = handler({}, None)

        assert result["statusCode"] == 200
        assert result["queryId"] == "qid-123"
        assert result["state"] == "SUCCEEDED"
        mock_athena.start_query_execution.assert_called_once_with(
            QueryString="MSCK REPAIR TABLE test_table",
            QueryExecutionContext={"Database": "test_db"},
            WorkGroup="test-workgroup",
        )

    @patch("handler.athena")
    @patch("handler.time")
    def test_failed_repair_raises_exception(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-456"
        }
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {
                "Status": {
                    "State": "FAILED",
                    "StateChangeReason": "Table not found",
                }
            }
        }

        with pytest.raises(Exception, match="MSCK REPAIR TABLE failed"):
            handler({}, None)

    @patch("handler.athena")
    @patch("handler.time")
    def test_cancelled_repair_raises_exception(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-789"
        }
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "CANCELLED"}}
        }

        with pytest.raises(Exception, match="MSCK REPAIR TABLE failed"):
            handler({}, None)

    @patch("handler.athena")
    @patch("handler.time")
    def test_polls_until_completion(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-poll"
        }
        # RUNNING 2회 후 SUCCEEDED
        mock_athena.get_query_execution.side_effect = [
            {"QueryExecution": {"Status": {"State": "RUNNING"}}},
            {"QueryExecution": {"Status": {"State": "RUNNING"}}},
            {"QueryExecution": {"Status": {"State": "SUCCEEDED"}}},
        ]

        result = handler({}, None)

        assert result["state"] == "SUCCEEDED"
        assert mock_athena.get_query_execution.call_count == 3

    @patch("handler.athena")
    @patch("handler.time")
    def test_query_uses_correct_database_and_workgroup(self, mock_time, mock_athena):
        from handler import handler

        mock_athena.start_query_execution.return_value = {
            "QueryExecutionId": "qid-env"
        }
        mock_athena.get_query_execution.return_value = {
            "QueryExecution": {"Status": {"State": "SUCCEEDED"}}
        }

        handler({}, None)

        call_kwargs = mock_athena.start_query_execution.call_args.kwargs
        assert call_kwargs["QueryExecutionContext"]["Database"] == "test_db"
        assert call_kwargs["WorkGroup"] == "test-workgroup"
