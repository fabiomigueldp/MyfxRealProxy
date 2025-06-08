"""force_real.py – mitmproxy addon
Forces every Myfxbook account to appear as REAL by changing "demo": true → false
in the JSON returned from /api/get-my-accounts.json
"""
from mitmproxy import http, ctx
import json, re

TARGET_RE = re.compile(r"/api/get-my-accounts\.json(?:\?|$)")

def response(flow: http.HTTPFlow):
    # Only patch responses from Myfxbook account list endpoint
    if flow.request.host == "www.myfxbook.com" and TARGET_RE.search(flow.request.path):
        try:
            # Attempt to parse the JSON response
            try:
                data = json.loads(flow.response.text)
            except json.JSONDecodeError as jde:
                ctx.log.warn(f"[force_real] JSON decoding failed: {jde}. Response text started with: {flow.response.text[:200]}")
                return  # Exit if JSON is invalid

            patched = 0
            accounts = data.get("accounts")

            # Check if 'accounts' is a list, which is expected
            if not isinstance(accounts, list):
                ctx.log.warn(f"[force_real] 'accounts' field is not a list, but type: {type(accounts)}. Data: {data}")
                return # Exit if 'accounts' is not a list

            for acct in accounts:
                # Check if 'acct' is a dictionary
                if not isinstance(acct, dict):
                    ctx.log.warn(f"[force_real] Account item is not a dictionary, but type: {type(acct)}. Account data: {acct}")
                    continue # Skip this account and proceed with the next

                if acct.get("demo") is not False:  # Handles missing "demo" key gracefully
                    acct["demo"] = False
                    patched += 1

            if patched:
                try:
                    flow.response.text = json.dumps(data)
                    ctx.log.info(f"[patched] forced demo->false on {patched} account(s)")
                except Exception as e: # Catch potential errors during re-dumping, though less likely
                    ctx.log.error(f"[force_real] Failed to re-encode JSON: {e}")

        except Exception as exc: # General fallback for unexpected errors
            # Log the exception with more details, e.g. type of exception
            ctx.log.error(f"[force_real] An unexpected error occurred: {type(exc).__name__} - {exc}. Response text snippet: {flow.response.text[:200]}")