#!/usr/bin/env bash
# ==============================================================================
# Script: fix-docker-creds.sh
# Purpose: Fix and sanitize Docker ~/.docker/config.json in WSL2/Linux
# Prevents: "docker-credential-desktop.exe: executable file not found in $PATH"
# ==============================================================================

fix_docker_credentials() {
  local docker_cfg="${HOME}/.docker/config.json"
  [ ! -f "$docker_cfg" ] && return 0

  # 1. Primary method: Python3 safe JSON parse and cleanup
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, os, shutil

cfg_path = os.path.expanduser('~/.docker/config.json')
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        changed = False

        # Remove credsStore if desktop.exe / desktop or if helper binary is missing from PATH
        if 'credsStore' in data:
            store = str(data['credsStore']).strip()
            if store in ('desktop.exe', 'desktop') or (not shutil.which(f'docker-credential-{store}') and not shutil.which(store)):
                del data['credsStore']
                changed = True

        # Remove invalid entries in credHelpers
        if 'credHelpers' in data and isinstance(data['credHelpers'], dict):
            for k, store_val in list(data['credHelpers'].items()):
                store_str = str(store_val).strip()
                if store_str in ('desktop.exe', 'desktop') or (not shutil.which(f'docker-credential-{store_str}') and not shutil.which(store_str)):
                    del data['credHelpers'][k]
                    changed = True
            if not data['credHelpers']:
                del data['credHelpers']
                changed = True

        if changed:
            with open(cfg_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
    except Exception:
        pass
" 2>/dev/null || true
  fi

  # 2. Fallback method: Sed cleanup if python was unavailable or config is still referencing desktop/desktop.exe
  if [ -f "$docker_cfg" ]; then
    if grep -Eq 'desktop(\.exe)?' "$docker_cfg" 2>/dev/null; then
      sed -i '/"credsStore"[[:space:]]*:[[:space:]]*"desktop/d' "$docker_cfg" 2>/dev/null || true
      sed -i '/"desktop\.exe"/d' "$docker_cfg" 2>/dev/null || true
      sed -i 's/,\([[:space:]]*[}\]]\)/\1/g' "$docker_cfg" 2>/dev/null || true
      # If file became empty or invalid, write clean empty JSON
      local content
      content="$(cat "$docker_cfg" 2>/dev/null | tr -d '[:space:]' || true)"
      if [ -z "$content" ] || [ "$content" = "{}" ]; then
        echo "{}" > "$docker_cfg"
      fi
    fi
  fi
}

fix_docker_credentials
