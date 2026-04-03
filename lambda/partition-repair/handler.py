"""Lambda: runs MSCK REPAIR TABLE on Athena to register new Glue partitions."""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

athena = boto3.client("athena")
DATABASE = os.environ["GLUE_DATABASE"]
TABLE = os.environ["GLUE_TABLE"]
WORKGROUP = os.environ["ATHENA_WORKGROUP"]


def handler(event, context):
    query = f"MSCK REPAIR TABLE {TABLE}"
    logger.info(f"Running: {query} on database={DATABASE}, workgroup={WORKGROUP}")

    resp = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
    )
    query_id = resp["QueryExecutionId"]

    # Wait for completion (max 60s)
    for _ in range(12):
        time.sleep(5)
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break

    logger.info(f"Query {query_id} finished with state: {state}")
    if state != "SUCCEEDED":
        reason = status["QueryExecution"]["Status"].get("StateChangeReason", "")
        logger.error(f"Query failed: {reason}")
        raise Exception(f"MSCK REPAIR TABLE failed: {state} - {reason}")

    return {"statusCode": 200, "queryId": query_id, "state": state}
