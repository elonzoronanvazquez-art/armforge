"""Concise Creator Store audio search through Studio MCP. Usage: python scripts/search_audio.py "query" ["query" ...]"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

c = studio_mcp.Client()
for q in sys.argv[1:]:
    r = c.call("search_asset", {"query": q, "assetType": "Audio", "scope": "creator_store", "maxResults": 10, "priceFilter": "free"}).get("result", {})
    data = json.loads(r["content"][0]["text"])
    print("##", q)
    for item in data.get("results", []):
        desc = item.get("description", "").replace("\n", " ")
        m = re.search(r"Duration: ([0-9.]+)", desc)
        print(item["assetId"], "|", item["name"][:50], "|", item.get("creatorName"), "|", (m.group(1) + "s") if m else "?", "|", desc[:70])
