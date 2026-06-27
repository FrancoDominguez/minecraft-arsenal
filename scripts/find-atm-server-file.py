#!/usr/bin/env python3
"""Look up an All the Mods pack's CurseForge project ID and its ServerFiles
file IDs, so you can fill TF_VAR_curseforge_project_id and
TF_VAR_curseforge_server_file_id.

Reads the API key from the environment (TF_VAR_curseforge_api_key or
CURSEFORGE_API_KEY); auto-loads a .env in the repo root if present.

Usage:
    python3 scripts/find-atm-server-file.py [slug]
    # slug defaults to all-the-mods-11; e.g. all-the-mods-10 for the stable fallback
"""
import json
import os
import sys
import urllib.request

API = "https://api.curseforge.com/v1"
GAME_MINECRAFT = 432
CLASS_MODPACKS = 4471


def load_dotenv():
    root = os.path.join(os.path.dirname(__file__), "..")
    path = os.path.join(root, ".env")
    if not os.path.exists(path):
        return
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def get(path, key, params=None):
    url = API + path
    if params:
        url += "?" + "&".join(f"{k}={v}" for k, v in params.items())
    req = urllib.request.Request(url, headers={
        "x-api-key": key,
        "Accept": "application/json",
        "User-Agent": "minecraft-arsenal/1.0",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    load_dotenv()
    key = os.environ.get("TF_VAR_curseforge_api_key") or os.environ.get("CURSEFORGE_API_KEY")
    if not key:
        sys.exit("No API key: set TF_VAR_curseforge_api_key (or CURSEFORGE_API_KEY), or fill .env")

    slug = sys.argv[1] if len(sys.argv) > 1 else "all-the-mods-11"

    found = get("/mods/search", key, {
        "gameId": GAME_MINECRAFT, "classId": CLASS_MODPACKS, "slug": slug,
    }).get("data", [])
    if not found:
        sys.exit(f"No modpack found for slug '{slug}'")
    mod = found[0]
    print(f"\nProject: {mod['name']}  (slug={slug})")
    print(f"  TF_VAR_curseforge_project_id={mod['id']}\n")

    files = get(f"/mods/{mod['id']}/files", key, {"pageSize": 50}).get("data", [])
    server_files = [f for f in files if f.get("isServerPack")]
    if not server_files:
        print("  No ServerFiles found in the latest 50 files. Server packs may be")
        print("  attached to client files via 'serverPackFileId' — check the newest:")
        for f in files[:5]:
            spid = f.get("serverPackFileId")
            print(f"    {f['fileName']}  serverPackFileId={spid}")
        return

    print("  ServerFiles (newest first) — pick one for TF_VAR_curseforge_server_file_id:")
    for f in sorted(server_files, key=lambda x: x.get("fileDate", ""), reverse=True):
        vers = ", ".join(f.get("gameVersions", []))
        print(f"    id={f['id']:<10} {f['fileName']:<40} [{vers}]  {f.get('fileDate','')[:10]}")
    print()


if __name__ == "__main__":
    main()
