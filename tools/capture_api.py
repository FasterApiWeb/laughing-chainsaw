#!/usr/bin/env python3
"""
mitmproxy addon: capture Oura cloud API traffic to structured JSON.

Run:
    mitmdump -s capture_api.py --listen-port 8080

Then point iPhone Wi-Fi HTTP proxy at <your-mac-ip>:8080 and install the
mitmproxy CA from http://mitm.it (see PRD section 6.4).
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mitmproxy import ctx, http

OUTPUT_DIR = Path("captures/api")
OURA_HOST_SUFFIX = "ouraring.com"
USERCOLLECTION_PREFIX = "/v2/usercollection"


def _headers_dict(headers: http.Headers) -> dict[str, str]:
    return {k: v for k, v in headers.items(multi=True)}


def _body_preview(content: bytes | None, limit: int = 8192) -> dict[str, Any]:
    if not content:
        return {"size": 0, "text": None, "truncated": False}

    truncated = len(content) > limit
    chunk = content[:limit]
    try:
        text = chunk.decode("utf-8")
        parsed: Any
        try:
            parsed = json.loads(text if not truncated else content.decode("utf-8"))
        except json.JSONDecodeError:
            parsed = None
        return {
            "size": len(content),
            "text": text,
            "json": parsed,
            "truncated": truncated,
        }
    except UnicodeDecodeError:
        return {
            "size": len(content),
            "hex": chunk.hex(),
            "truncated": truncated,
        }


class OuraApiCapture:
    """Log requests/responses to cloud.ouraring.com."""

    def __init__(self) -> None:
        self._session_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self._output = OUTPUT_DIR / f"oura_api_{self._session_id}.jsonl"
        self._count = 0

    def load(self, loader: Any) -> None:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        ctx.log.info(f"Oura API capture → {self._output}")

    def _is_oura(self, flow: http.HTTPFlow) -> bool:
        return OURA_HOST_SUFFIX in flow.request.pretty_host

    def _is_usercollection(self, flow: http.HTTPFlow) -> bool:
        return flow.request.path.startswith(USERCOLLECTION_PREFIX)

    def response(self, flow: http.HTTPFlow) -> None:
        if not self._is_oura(flow):
            return

        entry: dict[str, Any] = {
            "index": self._count,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "host": flow.request.pretty_host,
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "path": flow.request.path,
            "status_code": flow.response.status_code if flow.response else None,
            "is_usercollection": self._is_usercollection(flow),
            "request": {
                "headers": _headers_dict(flow.request.headers),
                "body": _body_preview(flow.request.content),
            },
            "response": {
                "headers": _headers_dict(flow.response.headers) if flow.response else {},
                "body": _body_preview(flow.response.content if flow.response else None),
            },
        }

        with self._output.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

        self._count += 1
        tag = "usercollection" if entry["is_usercollection"] else "api"
        ctx.log.info(f"[{tag}] {flow.request.method} {flow.request.path} → {entry['status_code']}")


addons = [OuraApiCapture()]
