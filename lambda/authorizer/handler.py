# lambda/authorizer/handler.py
"""Lambda Authorizer: validates x-api-key header against SSM Parameter Store."""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
SSM_PARAMETER_NAME = os.environ["SSM_PARAMETER_NAME"]
CACHE_TTL_SECONDS = 300

_key_cache = {"keys": None, "expires": 0}


def _get_valid_keys():
    """Fetch valid API keys from SSM, with in-memory caching."""
    now = time.time()
    if _key_cache["keys"] is not None and now < _key_cache["expires"]:
        return _key_cache["keys"]

    resp = ssm.get_parameter(Name=SSM_PARAMETER_NAME, WithDecryption=True)
    raw = resp["Parameter"]["Value"]
    keys = {k.strip() for k in raw.split(",") if k.strip()}
    _key_cache["keys"] = keys
    _key_cache["expires"] = now + CACHE_TTL_SECONDS
    return keys


def handler(event, context):
    headers = event.get("headers", {})
    api_key = headers.get("x-api-key", "")

    if not api_key:
        logger.info("Denied: missing x-api-key header")
        return {"isAuthorized": False}

    try:
        valid_keys = _get_valid_keys()
    except Exception:
        logger.exception("Failed to fetch API keys from SSM")
        return {"isAuthorized": False}

    if api_key not in valid_keys:
        logger.info("Denied: invalid API key")
        return {"isAuthorized": False}

    return {
        "isAuthorized": True,
        "context": {"apiKeyId": api_key},
    }
