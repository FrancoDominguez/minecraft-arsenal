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

    # Two shapes exist in the wild:
    #  - ATM10 etc.: standalone files with isServerPack=true (the ServerFiles zip).
    #  - ATM11: no standalone ServerFiles; each CLIENT file carries a
    #    serverPackFileId pointing at its matching server pack. That client file's
    #    own id and its serverPackFileId are exactly the two TF vars we need:
    #    curseforge_client_file_id and curseforge_server_file_id.
    server_files = [f for f in files if f.get("isServerPack")]
    paired = [f for f in files if f.get("serverPackFileId")]

    if server_files:
        print("  Standalone ServerFiles (newest first) — pick one for TF_VAR_curseforge_server_file_id:")
        for f in sorted(server_files, key=lambda x: x.get("fileDate", ""), reverse=True):
            vers = ", ".join(f.get("gameVersions", []))
            print(f"    server_file_id={f['id']:<10} {f['fileName']:<40} [{vers}]  {f.get('fileDate','')[:10]}")
        print()

    if paired:
        print("  Client files with a matching server pack (newest first):")
        print("    -> client_file_id = TF_VAR_curseforge_client_file_id   (the one-click installer's client pack)")
        print("    -> server_file_id = TF_VAR_curseforge_server_file_id   (the ServerFiles the VM runs)")
        for f in sorted(paired, key=lambda x: x.get("fileDate", ""), reverse=True):
            vers = ", ".join(f.get("gameVersions", []))
            print(f"    client_file_id={f['id']:<10} server_file_id={str(f['serverPackFileId']):<10} "
                  f"{f['fileName']:<40} [{vers}]  {f.get('fileDate','')[:10]}")
        print()

    if not server_files and not paired:
        print("  No ServerFiles or paired client files in the latest 50 files. Newest files:")
        for f in files[:5]:
            print(f"    id={f['id']}  serverPackFileId={f.get('serverPackFileId')}  {f['fileName']}")


if __name__ == "__main__":
    main()
