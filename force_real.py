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
            data = json.loads(flow.response.text)  # mitmproxy auto‑decodes to string
            patched = 0
            for acct in data.get("accounts", []):
                if acct.get("demo") is not False:
                    acct["demo"] = False
                    patched += 1
            if patched:
                flow.response.text = json.dumps(data)
                ctx.log.info(f"[patched] forced demo→false on {patched} account(s)")
        except Exception as exc:
            ctx.log.warn(f"[force_real] patch failed: {exc}")