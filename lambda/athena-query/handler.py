"""Lambda: executes Athena SQL queries for AgentCore RUM analysis agent."""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

athena = boto3.client("athena")
DATABASE = os.environ.get("GLUE_DATABASE", "rum_pipeline_db")
WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "rum-pipeline-athena")


def handler(event, context):
    """Execute an Athena SQL query and return results."""
    logger.info(f"Event: {json.dumps(event)}")

    # MCP Gateway sends tool invocations in this format
    tool_name = event.get("name", "")
    tool_input = event.get("input", event)

    sql = tool_input.get("sql", "")
    if not sql:
        return {"error": "Missing 'sql' parameter"}

    # Safety: only allow SELECT
    sql_upper = sql.strip().upper()
    if not sql_upper.startswith("SELECT") and not sql_upper.startswith("SHOW") and not sql_upper.startswith("DESCRIBE"):
        return {"error": "Only SELECT/SHOW/DESCRIBE queries are allowed"}

    try:
        resp = athena.start_query_execution(
            QueryString=sql,
            QueryExecutionContext={"Database": DATABASE},
            WorkGroup=WORKGROUP,
        )
        query_id = resp["QueryExecutionId"]

        # Wait for completion (max 30s)
        for _ in range(15):
            time.sleep(2)
            status = athena.get_query_execution(QueryExecutionId=query_id)
            state = status["QueryExecution"]["Status"]["State"]
            if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
                break

        if state != "SUCCEEDED":
            reason = status["QueryExecution"]["Status"].get("StateChangeReason", "")
            return {"error": f"Query failed: {state} - {reason}"}

        # Get results
        results = athena.get_query_results(QueryExecutionId=query_id)
        rows = results["ResultSet"]["Rows"]

        if not rows:
            return {"data": [], "rowCount": 0}

        # Parse header + data
        headers = [col["VarCharValue"] for col in rows[0]["Data"]]
        data = []
        for row in rows[1:]:
            record = {}
            for i, col in enumerate(row["Data"]):
                record[headers[i]] = col.get("VarCharValue", "")
            data.append(record)

        return {
            "data": data,
            "rowCount": len(data),
            "columns": headers,
            "queryId": query_id,
        }

    except Exception as e:
        logger.exception("Athena query failed")
        return {"error": str(e)}
