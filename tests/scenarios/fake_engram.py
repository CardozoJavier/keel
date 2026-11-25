"""Stand-in engram MCP server for keel's memory scenarios (T071).

Speaks MCP over stdio (newline-delimited JSON-RPC 2.0) and exposes engram's tool names. Every tool
call is appended to $FAKE_ENGRAM_LOG as one JSON line ({"tool": ..., "arguments": ...}), so a
scenario can assert exactly which memory calls keel made without touching the user's real memory
store. The second mem_save (counted across sessions) returns judgment_required with one candidate, to check that keel
resolves it without prompting.
"""
import json
import os
import sys

LOG = os.environ.get("FAKE_ENGRAM_LOG", "/dev/null")
COUNT = LOG + ".saves"  # the save count survives across sessions: each session starts a new server
TOOLS = [
    ("mem_search", "Search persistent memory for past decisions.", {"query": {"type": "string"}, "project": {"type": "string"}}),
    ("mem_save", "Save a decision or discovery to persistent memory. topic_key upserts.", {
        "title": {"type": "string"}, "content": {"type": "string"}, "type": {"type": "string"},
        "topic_key": {"type": "string"}, "project": {"type": "string"}}),
    ("mem_judge", "Record a verdict on a pending memory conflict from mem_save.", {
        "judgment_id": {"type": "string"}, "relation": {"type": "string"}, "reason": {"type": "string"}}),
    ("mem_session_summary", "Save an end-of-session summary.", {"content": {"type": "string"}}),
    ("mem_session_start", "Start a memory session.", {"id": {"type": "string"}}),
    ("mem_session_end", "End a memory session.", {"id": {"type": "string"}}),
    ("mem_context", "Recent session history.", {"limit": {"type": "number"}}),
]


def reply(msg_id, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}) + "\n")
    sys.stdout.flush()


def text(payload):
    return {"content": [{"type": "text", "text": payload if isinstance(payload, str) else json.dumps(payload)}]}


def call(name, args):
    with open(LOG, "a") as log:
        log.write(json.dumps({"tool": name, "arguments": args}) + "\n")
    if name == "mem_search":
        return text("Found 1 memory:\n[decision] keel/000-price-basics: Prices are records in minor units; "
                    "rounding is half up to the cent (chosen design: smallest change).")
    if name == "mem_save":
        try:
            saves = int(open(COUNT).read().strip() or 0) + 1
        except (OSError, ValueError):
            saves = 1
        with open(COUNT, "w") as c:
            c.write(str(saves))
        if saves >= 2:
            return text({"id": 100 + saves, "result": "Memory saved", "judgment_required": True,
                         "candidates": [{"id": 7, "judgment_id": "rel-fake0001", "title": "keel/000-price-basics",
                                         "topic_key": "keel/000-price-basics", "type": "decision"}]})
        return text({"id": 100 + saves, "result": "Memory saved", "judgment_required": False})
    return text({"result": "ok"})


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    method, msg_id = msg.get("method"), msg.get("id")
    if msg_id is None:
        continue  # notifications (initialized, cancelled)
    if method == "initialize":
        reply(msg_id, {"protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                       "capabilities": {"tools": {}}, "serverInfo": {"name": "engram", "version": "0.0.0-keel-fake"}})
    elif method == "tools/list":
        reply(msg_id, {"tools": [{"name": n, "description": d, "inputSchema": {"type": "object", "properties": p}}
                                 for n, d, p in TOOLS]})
    elif method == "tools/call":
        params = msg.get("params", {})
        reply(msg_id, call(params.get("name"), params.get("arguments") or {}))
    else:
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32601, "message": "unknown method"}}) + "\n")
        sys.stdout.flush()
