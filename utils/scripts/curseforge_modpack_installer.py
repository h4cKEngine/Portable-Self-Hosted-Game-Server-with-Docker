#!/usr/bin/env python3

"""Scarica un modpack CurseForge e prepara un server Minecraft completo.

Uso:
    python utils/scripts/curseforge_modpack_installer.py <modpackId | URL del modpack>

Legge la chiave API da env/.env (variabile CURSEFORGE_API_KEY), scarica il piu'
recente .zip del modpack, estrae manifest.json e gli overrides (config,
kubejs, ecc.), scarica tutte le mod, installa il mod loader (Forge/
NeoForge/Fabric) e accetta la EULA.

Ogni modpack viene installato in una cartella dedicata: servers/<slug>
(usare --server-dir per un percorso personalizzato).
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile
from datetime import datetime
from pathlib import Path

import requests

BASE_URL = "https://api.curseforge.com/v1"
DEFAULT_ENV_PATH = Path("env/.env")
DEFAULT_SERVER_DIR = Path("server_modpacks")
MINECRAFT_GAME_ID = 432
MODPACK_CLASS_ID = 4471
FORGE_MAVEN_URL = "https://maven.minecraftforge.net/net/minecraftforge/forge"
NEOFORGE_MAVEN_URL = "https://maven.neoforged.net/releases/net/neoforged/neoforge"
FABRIC_META_URL = "https://meta.fabricmc.net/v2"
CLIENT_ONLY_KEYWORDS = (
    # Shaders / Rendering / Performance
    "oculus", "rubidium", "iris", "sodium", "optifine", "embeddium", "magnesium", "indium",
    "betterfps", "smoothboot", "lazydfu", "entityculling", "ferritecore", "dashloader", "fastcraft",
    # Audio / Effects
    "soundfilters", "sound-filters", "dynamicsurroundings", "dynamic-surroundings",
    "ambientsounds", "ambient-sounds", "presencefootsteps", "presence-footsteps",
    # HUD / UI / Tools
    "fullscreen", "borderless", "armorchroma", "babyanimals", "baby-animals",
    "defaultkeys", "defaultoptions", "default-options", "custommainmenu", "custom-main-menu",
    "inventorytweaks", "inventory-tweaks", "mousetweaks", "mouse-tweaks", "neat",
    "trashslot", "trash-slot", "chatflow", "chat-flow", "limi", "controlling", "appleskin",
    "lightoverlay", "light-overlay", "waila", "hwyla", "jade", "theoneprobe",
    "journeymap", "xaeros", "minimap", "worldmap", "voxelmap", "mapwriter",
    "reauth", "notenoughanimations", "firstperson", "3dskinlayers", "skinlayers", "waveycapes",
    "itemphysic-lite", "blur", "toastcontrol", "modnametooltip",
    "haynokill", "hay-no-kill",
)

# Hardcoded key for public download
CURSEFORGE_API_KEY = "$2a$10$n/Yb8yC2d3Yvd2wWkP9.HeKMCC9A1l2/p0I2LCx/cI8LiPESErmae"
CHUNK_SIZE = 8192


class CurseForgeError(Exception):
    """Errore bloccante durante l'installazione del modpack."""


def load_api_key(env_path=DEFAULT_ENV_PATH):
    """Restituisce la CURSEFORGE_API_KEY impostata o la legge dal file .env."""
    if CURSEFORGE_API_KEY:
        return CURSEFORGE_API_KEY
    if not env_path.is_file():
        raise CurseForgeError(
            f"File di configurazione non trovato: {env_path}. "
            "Crealo e aggiungi la riga CURSEFORGE_API_KEY=<tua-chiave>."
        )
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "CURSEFORGE_API_KEY":
            value = value.strip().strip('"').strip("'")
            if value:
                return value
            break
    raise CurseForgeError(
        f"La variabile CURSEFORGE_API_KEY non e' definita (o e' vuota) in {env_path}. "
        "Puoi ottenerla su https://console.curseforge.com/"
    )


def make_headers(api_key):
    return {
        "x-api-key": api_key,
        "Accept": "application/json",
    }


def ensure_mods_dir(mods_dir=None):
    if mods_dir is None:
        mods_dir = DEFAULT_SERVER_DIR / "mods"
    mods_dir = Path(mods_dir)
    mods_dir.mkdir(parents=True, exist_ok=True)
    return mods_dir


class ApiSource:
    """Sorgente mod ufficiale: API CurseForge con chiave."""

    def __init__(self, session):
        self.session = session

    def get_meta(self, project_id, file_id):
        data = api_get(self.session, f"/mods/{project_id}/files/{file_id}") or {}
        file_name = data.get("fileName") or f"{project_id}-{file_id}.jar"
        return file_name, data.get("downloadUrl")

    def fetch(self, handle, file_name, dest):
        return download_file(self.session, handle, dest)


class CdnSource:
    """Sorgente alternativa senza chiave: cfwidget + CDN pubblico Forge."""

    def __init__(self):
        self._memory_cache = {}

    def _cached_fetch(self, ref):
        if ref in self._memory_cache:
            return self._memory_cache[ref]
        cache_file = CF_CACHE_DIR / f"{re.sub(r'[^0-9A-Za-z_-]', '_', str(ref))}.json"
        if cache_file.is_file():
            try:
                payload = json.loads(cache_file.read_text(encoding="utf-8"))
                self._memory_cache[ref] = payload
                return payload
            except (OSError, ValueError):
                pass
        payload = fetch_cfwidget(ref)
        self._memory_cache[ref] = payload
        try:
            CF_CACHE_DIR.mkdir(exist_ok=True)
            cache_file.write_text(json.dumps(payload), encoding="utf-8")
        except OSError:
            pass
        return payload

    def get_meta(self, project_id, file_id):
        file_name = resolve_mod_filename_cdn(
            project_id, file_id, fetcher=self._cached_fetch
        )
        return file_name, (project_id, file_id)

    def fetch(self, handle, file_name, dest):
        _, file_id = handle
        return download_file_cdn(file_id, file_name, dest)


def build_cdn_file_urls(file_id, file_name):
    quoted = urllib.parse.quote(file_name)
    base = f"/files/{file_id // 1000}/{file_id % 1000:03d}/{quoted}"
    return [f"https://mediafilez.forgecdn.net{base}", f"https://edge.forgecdn.net{base}"]


def download_file_cdn(file_id, file_name, dest_path):
    last_status = "?"
    for url in build_cdn_file_urls(file_id, file_name):
        try:
            with requests.get(url, stream=True, timeout=600) as response:
                if response.ok:
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(dest_path, "wb") as fh:
                        for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                            if chunk:
                                fh.write(chunk)
                    return dest_path
                last_status = response.status_code
        except requests.RequestException as exc:
            last_status = str(exc)[:80]
    raise CurseForgeError(
        f"Download CDN fallito ({last_status}) per {file_name}"
    )


def fetch_cfwidget(ref, retries=6, pause=4):
    """Interroga l'API pubblica cfwidget; ripete se il progetto e' in coda."""
    url = f"{CFWIDGET_URL}/{ref}"
    for attempt in range(retries):
        response = requests.get(url, timeout=60)
        if not response.ok and response.status_code != 202:
            break
        payload = response.json()
        if isinstance(payload, dict) and payload.get("accept"):
            time.sleep(pause)
            continue
        if isinstance(payload, dict) and payload.get("error"):
            raise CurseForgeError(
                f"cfwidget: {payload.get('error')} per '{ref}'"
            )
        return payload
    raise CurseForgeError(
        f"Impossibile ottenere i dati di '{ref}' da cfwidget dopo {retries} tentativi."
    )


def get_latest_release_from_widget(widget):
    files = [f for f in widget.get("files", []) if f.get("type") == "release"]
    if not files:
        raise CurseForgeError(
            f"Nessun file release trovato per '{widget.get('title')}' su cfwidget."
        )
    return max(files, key=lambda f: f.get("uploaded_at", ""))


def resolve_mod_filename_cdn(project_id, file_id, fetcher=fetch_cfwidget):
    widget = fetcher(project_id)
    for entry in widget.get("files", []):
        if entry.get("id") == int(file_id):
            return entry["name"]
    raise CurseForgeError(
        f"File {file_id} non trovato nel progetto {project_id} su cfwidget."
    )


def slug_from_widget(widget):
    cf_path = (widget.get("urls") or {}).get("curseforge") or ""
    slug = cf_path.rstrip("/").rsplit("/", 1)[-1]
    return slug or None


def resolve_server_dir(explicit, pack_slug):
    """Una cartella per modpack: server_modpacks/<slug>, salvo percorso esplicito."""
    if explicit:
        return Path(explicit)
    safe = re.sub(r"[^0-9A-Za-z_.-]", "-", str(pack_slug or "modpack"))
    return DEFAULT_SERVER_DIR / safe


def widget_ref(target):
    target = str(target).strip()
    if re.fullmatch(r"\d+", target):
        return target
    match = re.search(r"/minecraft/modpacks/([^/?#]+)", target)
    if match:
        return f"minecraft/modpacks/{match.group(1)}"
    cleaned = target.strip("/").split("/")[-1]
    return f"minecraft/modpacks/{cleaned}"


def inspect_modpack(target, api_key=None):
    """Estrae metadati di un modpack (nome, slug, mc_version, loader, logo, ecc.) senza scaricare mod."""
    api_key = api_key or CURSEFORGE_API_KEY
    session = requests.Session()
    use_cdn = False
    try:
        session.headers.update(make_headers(api_key))
        probe = requests.get(
            f"{BASE_URL}/games/{MINECRAFT_GAME_ID}",
            headers=make_headers(api_key),
            timeout=15,
        )
        use_cdn = not probe.ok
    except Exception:
        use_cdn = True

    if not use_cdn:
        try:
            modpack_id = resolve_modpack_id(session, target)
            info = get_mod_info(session, modpack_id)
            latest = get_latest_server_file(session, modpack_id)
            input_slug = re.search(r"/minecraft/modpacks/([^/?#]+)", str(target))
            pack_slug = input_slug.group(1) if input_slug else (info.get("slug") or str(modpack_id))
            logo_dict = info.get("logo") or {}
            logo_url = logo_dict.get("thumbnailUrl") or logo_dict.get("url") or ""

            gv = latest.get("gameVersions") or []
            loader = "FORGE"
            mc_ver = "1.20.1"
            found_mc = False
            for v in gv:
                v_str = str(v).strip()
                v_lower = v_str.lower()
                if "forge" in v_lower and "neoforge" not in v_lower:
                    loader = "FORGE"
                elif "fabric" in v_lower:
                    loader = "FABRIC"
                elif "neoforge" in v_lower:
                    loader = "NEOFORGE"
                elif re.match(r"^1\.\d+(\.\d+)?$", v_str):
                    mc_ver = v_str
                    found_mc = True

            if not found_mc:
                # Check sortableGameVersions
                for sv in latest.get("sortableGameVersions") or []:
                    sv_name = str(sv.get("gameVersionName") or sv.get("gameVersion") or "").strip()
                    if re.match(r"^1\.\d+(\.\d+)?$", sv_name):
                        mc_ver = sv_name
                        break

            return {
                "id": modpack_id,
                "name": info.get("name", pack_slug),
                "slug": pack_slug,
                "summary": info.get("summary", ""),
                "icon_url": logo_url,
                "download_count": info.get("downloadCount", 0),
                "website_url": (info.get("links") or {}).get("websiteUrl") or f"https://www.curseforge.com/minecraft/modpacks/{pack_slug}",
                "latest_file_name": latest.get("displayName") or latest.get("fileName"),
                "latest_file_id": latest.get("id"),
                "file_date": latest.get("fileDate"),
                "mc_version": mc_ver,
                "server_type": loader,
            }
        except Exception:
            use_cdn = True

    if use_cdn:
        ref = widget_ref(target)
        widget = fetch_cfwidget(ref)
        name = widget.get("title", ref)
        input_slug = re.search(r"/minecraft/modpacks/([^/?#]+)", str(target))
        pack_slug = input_slug.group(1) if input_slug else (slug_from_widget(widget) or ref.split("/")[-1])
        latest = get_latest_release_from_widget(widget)

        gv = widget.get("versions") or []
        mc_ver = "1.20.1"
        loader = "FORGE"
        if isinstance(gv, dict):
            keys = list(gv.keys())
            if keys:
                mc_ver = keys[0]
        elif isinstance(gv, list) and gv:
            for item in gv:
                if re.match(r"^1\.\d+(\.\d+)?$", str(item)):
                    mc_ver = str(item)
                    break

        return {
            "id": widget.get("id"),
            "name": name,
            "slug": pack_slug,
            "summary": widget.get("summary", ""),
            "icon_url": widget.get("thumbnail") or "",
            "download_count": (widget.get("downloads") or {}).get("total", 0),
            "website_url": (widget.get("urls") or {}).get("curseforge") or f"https://www.curseforge.com/minecraft/modpacks/{pack_slug}",
            "latest_file_name": latest.get("name"),
            "latest_file_id": latest.get("id"),
            "file_date": latest.get("uploaded_at"),
            "mc_version": mc_ver,
            "server_type": loader,
        }


def api_get(session, path, **params):
    response = session.get(f"{BASE_URL}{path}", params=params or None)
    if not response.ok:
        message = f"Richiesta API fallita ({response.status_code}) su {path}: {response.text[:200]}"
        if response.status_code in (401, 403):
            message += (
                "\nLa CURSEFORGE_API_KEY risulta rifiutata dal server. Verifica di aver "
                "incollato la chiave corretta generata su https://console.curseforge.com/"
                " (le chiavi valide iniziano con '$2a$')."
            )
        raise CurseForgeError(message)
    return response.json().get("data")


def resolve_modpack_id(session, target):
    """Accetta un ID numerico oppure l'URL/slug di un modpack."""
    target_str = str(target).strip()
    if re.fullmatch(r"\d+", target_str):
        return int(target_str)
    match = re.search(r"/minecraft/modpacks/([^/?#]+)", target_str)
    if match:
        slug = match.group(1)
    else:
        slug = target_str.strip("/").split("/")[-1]
    results = api_get(
        session,
        "/mods/search",
        gameId=MINECRAFT_GAME_ID,
        classId=MODPACK_CLASS_ID,
        slug=slug,
    )
    if not results:
        raise CurseForgeError(f"Nessun modpack trovato con lo slug '{slug}'.")
    modpack = results[0]
    print(f"Modpack trovato: {modpack.get('name')} (ID {modpack['id']})")
    return modpack["id"]



def get_mod_info(session, modpack_id):
    return api_get(session, f"/mods/{modpack_id}")


def get_latest_server_file(session, modpack_id):
    """Restituisce il file (.zip) disponibile piu' recente del modpack."""
    files = api_get(session, f"/mods/{modpack_id}/files") or []
    available = [f for f in files if f.get("isAvailable", True)]
    if not available:
        raise CurseForgeError("Nessun file disponibile per questo modpack.")

    def sort_key(f):
        date = f.get("fileDate") or ""
        return (date, f.get("id", 0))

    latest = max(available, key=sort_key)
    print(f"File selezionato: {latest.get('displayName', latest.get('fileName'))}")
    return latest


def download_file(session, url, dest_path):
    """Scarica un file in streaming sul percorso di destinazione."""
    if not url:
        raise CurseForgeError("URL di download non disponibile per questo file.")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    with session.get(url, stream=True) as response:
        if not response.ok:
            raise CurseForgeError(
                f"Download fallito ({response.status_code}): {url}"
            )
        with open(dest_path, "wb") as fh:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    fh.write(chunk)
    return dest_path


def fetch_pack_zip(session, latest, dest_path):
    """Scarica lo zip del modpack via API o, se disabilitato dall'autore, via CDN."""
    url = latest.get("downloadUrl")
    if url:
        download_file(session, url, dest_path)
        return dest_path
    name = latest.get("fileName") or latest.get("displayName") or f"{latest.get('id')}.zip"
    print(
        "NOTA: l'autore ha disabilitato il download diretto di questo file via API.\n"
        f"Provo con il CDN pubblico ({name})..."
    )
    return download_file_cdn(latest["id"], name, dest_path)


def extract_manifest(zip_path, extract_to=None):
    """Estrae il manifest.json dall'archivio del modpack e opzionalmente lo scrive su disco."""
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if n == "manifest.json"]
        if not names:
            raise CurseForgeError("manifest.json non presente nell'archivio del modpack.")
        raw = zf.read(names[0])
    
    if extract_to:
        target = Path(extract_to)
        if target.is_dir() or str(extract_to).endswith("/") or not target.suffix:
            target.mkdir(parents=True, exist_ok=True)
            target = target / "manifest.json"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)

    return json.loads(raw.decode("utf-8"))


def summarize_manifest(manifest):
    minecraft = manifest.get("minecraft", {})
    version = minecraft.get("version", "?")
    loaders = minecraft.get("modLoaders") or []
    if loaders:
        primary = next((l for l in loaders if l.get("primary")), loaders[0])
        loader = str(primary.get("id", "?")).split("-")[0]
        summary = f"Minecraft {version} con mod loader {loader}"
    else:
        summary = f"Minecraft {version} senza mod loader specificato"
    return summary


def get_minecraft_version(manifest):
    return (manifest.get("minecraft") or {}).get("version", "?")


def parse_mod_loaders(manifest):
    """Restituisce (nome_loader, versione) dal manifest, preferendo il primary."""
    loaders = (manifest.get("minecraft") or {}).get("modLoaders") or []
    if not loaders:
        raise CurseForgeError("Il manifest non specifica alcun mod loader.")
    primary = next((l for l in loaders if l.get("primary")), loaders[0])
    loader_id = str(primary.get("id", ""))
    name, sep, version = loader_id.partition("-")
    if not sep or not name or not version:
        raise CurseForgeError(f"ID del mod loader non riconosciuto: '{loader_id}'")
    return name.lower(), version


def build_forge_installer_urls(mc_version, forge_version):
    candidates = []
    # Candidate 1: {mc}-{forge}-{mc} (standard for 1.7.10 - 1.12.2 legacy)
    candidates.append(
        f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}-{mc_version}/forge-{mc_version}-{forge_version}-{mc_version}-installer.jar"
    )
    # Candidate 2: {mc}-{forge} (standard for modern Forge >= 1.13)
    candidates.append(
        f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}/forge-{mc_version}-{forge_version}-installer.jar"
    )
    # Candidate 3: {mc}-{forge} with target filename {mc}-{forge}-{mc}
    candidates.append(
        f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}/forge-{mc_version}-{forge_version}-{mc_version}-installer.jar"
    )
    return candidates


def build_neoforge_installer_url(neo_version):
    return f"{NEOFORGE_MAVEN_URL}/{neo_version}/neoforge-{neo_version}-installer.jar"


def build_fabric_server_url(mc_version, loader_version, installer_version):
    return (
        f"{FABRIC_META_URL}/versions/loader/"
        f"{mc_version}/{loader_version}/{installer_version}/server/jar"
    )


def get_latest_fabric_installer_version():
    response = requests.get(f"{FABRIC_META_URL}/versions/installer", timeout=60)
    if not response.ok:
        raise CurseForgeError(
            f"Impossibile recuperare le versioni dell'installer Fabric ({response.status_code})."
        )
    data = response.json()
    if not data or "version" not in data[0]:
        raise CurseForgeError("Nessuna versione dell'installer Fabric disponibile.")
    return data[0]["version"]


def build_forge_install_command(installer_path, java="java"):
    return [str(java), "-jar", str(installer_path), "--installServer"]


def extract_overrides(zip_path, server_dir):
    """Estrae gli overrides (config, kubejs, ecc.) nella root del server.

    Salta la cartella overrides/mods: le mod vengono gestite dal manifest
    per poter applicare il filtro client-only.
    """
    server_dir = Path(server_dir)
    server_dir.mkdir(parents=True, exist_ok=True)
    server_root = server_dir.resolve()
    extracted = 0
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir() or not info.filename.startswith("overrides/"):
                continue
            rel = info.filename[len("overrides/"):]
            if not rel or rel.startswith("mods/") or rel.startswith("world/") or rel.startswith("world_nether/") or rel.startswith("world_the_end/") or rel.startswith("saves/"):
                continue
            target = (server_dir / rel).resolve()
            if target != server_root and server_root not in target.parents:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted += 1
    return extracted


def ensure_eula(server_dir):
    """Accetta la EULA scrivendo eula=true se il file non esiste gia'."""
    eula_path = Path(server_dir) / "eula.txt"
    if eula_path.exists():
        return False
    eula_path.write_text(
        "# Accettazione EULA Minecraft: https://aka.ms/MinecraftEULA\neula=true\n",
        encoding="utf-8",
    )
    return True


def get_java_docker_image(mc_version):
    """Restituisce l'immagine docker Java adatta alla versione di Minecraft per l'installer."""
    parts = str(mc_version).split(".")
    try:
        major = int(parts[0])
        minor = int(parts[1]) if len(parts) > 1 else 0
        patch = int(parts[2]) if len(parts) > 2 else 0
    except ValueError:
        major, minor, patch = 1, 20, 1

    if minor < 17:
        return "eclipse-temurin:8-jre"
    elif minor < 20 or (minor == 20 and patch < 5):
        return "eclipse-temurin:17-jre"
    else:
        return "eclipse-temurin:21-jre"


def install_loader(session, manifest, server_dir, workdir, log_fn=None):
    """Installa la base del server Forge, NeoForge o Fabric in base al manifest."""
    def _log(msg):
        if log_fn:
            log_fn(str(msg))
        else:
            print(msg)

    loader_name, loader_version = parse_mod_loaders(manifest)
    mc_version = get_minecraft_version(manifest)

    if loader_name in ("forge", "neoforge"):
        installer = Path(server_dir) / f"{loader_name}-{mc_version}-{loader_version}-installer.jar"
        _log(f"Download installer server {loader_name} ({mc_version}-{loader_version})...")

        downloaded = False
        if loader_name == "forge":
            urls = build_forge_installer_urls(mc_version, loader_version)
            for u in urls:
                try:
                    download_file(session, u, installer)
                    downloaded = True
                    break
                except Exception:
                    continue
        else:
            url = build_neoforge_installer_url(loader_version)
            try:
                download_file(session, url, installer)
                downloaded = True
            except Exception as e:
                _log(f"Download installer fallito: {e}")

        if not downloaded:
            _log(f"ATTENZIONE: Impossibile scaricare installer server per {loader_name} {loader_version}.")
            return False

        # 1. First attempt: run installer in Docker container with exact Java version
        docker_bin = shutil.which("docker")
        docker_img = get_java_docker_image(mc_version)
        installed = False

        if docker_bin:
            # Ensure Docker credentials config is sanitized in WSL
            try:
                subprocess.run([str(Path(__file__).parent / "fix-docker-creds.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
            _log(f"Esecuzione installer server {loader_name} tramite Docker ({docker_img})...")
            abs_server = str(Path(server_dir).resolve())
            docker_cmd = [
                docker_bin, "run", "--rm",
                "-v", f"{abs_server}:/server",
                "-w", "/server",
                docker_img,
                "java", "-jar", installer.name, "--installServer"
            ]
            res = subprocess.run(docker_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if res.returncode == 0:
                _log(f"Installazione base server {loader_name} e librerie completata con successo!")
                installed = True
            else:
                _log(f"Nota esecuzione installer: {res.stdout[-300:] if res.stdout else ''}")

        # 2. Second attempt: run on host Java if Docker failed or not available
        if not installed:
            java = shutil.which("java")
            if java:
                _log(f"Tentativo esecuzione installer {loader_name} tramite Java host ({java})...")
                cmd = build_forge_install_command(installer, java=java)
                res = subprocess.run(cmd, cwd=str(server_dir), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                if res.returncode == 0:
                    _log(f"Installazione base server {loader_name} completata con successo tramite Java host.")
                    installed = True
                else:
                    _log(f"Nota installer host: {res.stdout[-300:] if res.stdout else ''}")
            else:
                _log("ATTENZIONE: Java non disponibile per eseguire l'installer in locale.")

        return installed

    if loader_name == "fabric":
        installer_version = get_latest_fabric_installer_version()
        url = build_fabric_server_url(mc_version, loader_version, installer_version)
        dest = Path(server_dir) / "fabric-server-launch.jar"
        _log(f"Download launcher Fabric (loader {loader_version}, installer {installer_version})...")
        download_file(session, url, dest)
        _log("Launcher Fabric scaricato con successo.")
        return True

    return False



def is_client_only(file_name, keywords=CLIENT_ONLY_KEYWORDS):
    normalized = re.sub(r"[^a-z0-9]", "", file_name.lower().replace(".jar", ""))
    for keyword in keywords:
        clean_kw = re.sub(r"[^a-z0-9]", "", keyword.lower())
        if clean_kw in normalized:
            return True
    return False


def process_manifest_files(source, manifest, mods_dir):
    """Scarica le mod elencate nel manifest. Restituisce un report riepilogativo."""
    mods_dir = ensure_mods_dir(mods_dir)
    report = {
        "downloaded": [],
        "already_present": [],
        "skipped_client_only": [],
        "manual": [],
        "failed": [],
    }

    entries = [
        e
        for e in manifest.get("files", [])
        if e.get("required", True)
    ]
    print(f"\nMod richieste dal manifest: {len(entries)}\n")

    for index, entry in enumerate(entries, start=1):
        project_id = entry.get("projectID")
        file_id = entry.get("fileID")
        try:
            file_name, handle = source.get_meta(project_id, file_id)
        except CurseForgeError as exc:
            print(f"[{index}/{len(entries)}] Errore per progetto {project_id}: {exc}")
            report["failed"].append((project_id, file_id))
            continue

        prefix = f"[{index}/{len(entries)}]"

        if is_client_only(file_name):
            print(f"{prefix} SKIP (client-only): {file_name}")
            report["skipped_client_only"].append(file_name)
            continue

        if (mods_dir / file_name).exists():
            print(f"{prefix} Gia' presente: {file_name}")
            report["already_present"].append(file_name)
            continue

        if not handle:
            dest = mods_dir / file_name
            print(
                f"{prefix} Download diretto disabilitato via API, "
                f"provo il CDN pubblico..."
            )
            try:
                download_file_cdn(file_id, file_name, dest)
            except CurseForgeError as exc:
                print(
                    f"{prefix} ATTENZIONE: '{file_name}' non scaricabile "
                    "(API e CDN).\n"
                    f"{' ' * len(prefix)} Inseriscila manualmente da:\n"
                    f"{' ' * len(prefix)} https://www.curseforge.com/minecraft/mc-mods "
                    f"(progetto {project_id}, file {file_id}) [{exc}]"
                )
                report["manual"].append((file_name,))
                continue
            size_kb = dest.stat().st_size / 1024
            print(f"{prefix} Scaricata dal CDN: {file_name} ({size_kb:.0f} KB)")
            report["downloaded"].append(file_name)
            continue

        dest = mods_dir / file_name
        try:
            source.fetch(handle, file_name, dest)
            size_kb = dest.stat().st_size / 1024
            print(f"{prefix} Scaricata: {file_name} ({size_kb:.0f} KB)")
            report["downloaded"].append(file_name)
        except CurseForgeError as exc:
            print(f"{prefix} Download non riuscito per {file_name}: {exc}")
            report["failed"].append((project_id, file_name))

    return report


def print_report(report):
    print("\n========== RIEPILOGO ==========")
    print(f"Mod scaricate:          {len(report['downloaded'])}")
    print(f"Gia' presenti:          {len(report['already_present'])}")
    print(f"Saltate (client-only):  {len(report['skipped_client_only'])}")
    print(f"Da inserire a mano:     {len(report['manual'])}")
    if report["manual"]:
        for (name,) in report["manual"]:
            print(f"  - {name}")
    if report["failed"]:
        print(f"Fallite:                {len(report['failed'])}")
        for item in report["failed"]:
            print(f"  - {item}")
    print("===============================")


def process_manifest_files(source, manifest, mods_dir, log_fn=print, progress_fn=None):
    """Scarica le mod elencate nel manifest. Restituisce un report riepilogativo."""
    mods_dir = ensure_mods_dir(mods_dir)
    report = {
        "downloaded": [],
        "already_present": [],
        "skipped_client_only": [],
        "manual": [],
        "failed": [],
    }

    entries = [
        e
        for e in manifest.get("files", [])
        if e.get("required", True)
    ]
    total_mods = len(entries)
    log_fn(f"\nMod richieste dal manifest: {total_mods}\n")

    for index, entry in enumerate(entries, start=1):
        if progress_fn and total_mods > 0:
            # Scale mod downloads between 45% and 85%
            pct = 45 + int((index / total_mods) * 40)
            progress_fn(pct, f"Download mod [{index}/{total_mods}]...")

        project_id = entry.get("projectID")
        file_id = entry.get("fileID")
        try:
            file_name, handle = source.get_meta(project_id, file_id)
        except CurseForgeError as exc:
            log_fn(f"[{index}/{total_mods}] Errore per progetto {project_id}: {exc}")
            report["failed"].append((project_id, file_id))
            continue

        prefix = f"[{index}/{total_mods}]"

        if is_client_only(file_name):
            log_fn(f"{prefix} SKIP (client-only): {file_name}")
            report["skipped_client_only"].append(file_name)
            continue

        if (mods_dir / file_name).exists():
            log_fn(f"{prefix} Gia' presente: {file_name}")
            report["already_present"].append(file_name)
            continue

        if not handle:
            dest = mods_dir / file_name
            log_fn(
                f"{prefix} Download diretto disabilitato via API, "
                f"provo il CDN pubblico..."
            )
            try:
                download_file_cdn(file_id, file_name, dest)
            except CurseForgeError as exc:
                log_fn(
                    f"{prefix} ATTENZIONE: '{file_name}' non scaricabile "
                    "(API e CDN).\n"
                    f"{' ' * len(prefix)} Inseriscila manualmente da:\n"
                    f"{' ' * len(prefix)} https://www.curseforge.com/minecraft/mc-mods "
                    f"(progetto {project_id}, file {file_id}) [{exc}]"
                )
                report["manual"].append((file_name,))
                continue
            size_kb = dest.stat().st_size / 1024
            log_fn(f"{prefix} Scaricata dal CDN: {file_name} ({size_kb:.0f} KB)")
            report["downloaded"].append(file_name)
            continue

        dest = mods_dir / file_name
        try:
            source.fetch(handle, file_name, dest)
            size_kb = dest.stat().st_size / 1024
            log_fn(f"{prefix} Scaricata: {file_name} ({size_kb:.0f} KB)")
            report["downloaded"].append(file_name)
        except CurseForgeError as exc:
            log_fn(f"{prefix} Download non riuscito per {file_name}: {exc}")
            report["failed"].append((project_id, file_name))

    # Automatic fix for legacy Minecraft 1.7.10 CodeChickenLib offline server issue
    has_ccc = any("codechicken" in str(m).lower() or "notenoughitems" in str(m).lower() for m in mods_dir.glob("*.jar"))
    if has_ccc:
        ccl_dir = mods_dir / "1.7.10"
        ccl_dir.mkdir(parents=True, exist_ok=True)
        ccl_file = ccl_dir / "CodeChickenLib-1.7.10-1.1.3.138-universal.jar"
        if not ccl_file.exists() or ccl_file.stat().st_size < 1000:
            log_fn("Download fix automatico CodeChickenLib 1.7.10 (308 KB)...")
            try:
                ccl_url = "https://maven.covers1624.net/codechicken/CodeChickenLib/1.7.10-1.1.3.138/CodeChickenLib-1.7.10-1.1.3.138-universal.jar"
                resp = requests.get(ccl_url, timeout=30)
                if resp.ok and len(resp.content) > 1000:
                    ccl_file.write_bytes(resp.content)
            except Exception as e:
                log_fn(f"Nota download CodeChickenLib: {e}")

    return report


def print_report(report, log_fn=print):
    log_fn("\n========== RIEPILOGO ==========")
    log_fn(f"Mod scaricate:          {len(report['downloaded'])}")
    log_fn(f"Gia' presenti:          {len(report['already_present'])}")
    log_fn(f"Saltate (client-only):  {len(report['skipped_client_only'])}")
    log_fn(f"Da inserire a mano:     {len(report['manual'])}")
    if report["manual"]:
        for (name,) in report["manual"]:
            log_fn(f"  - {name}")
    if report["failed"]:
        log_fn(f"Fallite:                {len(report['failed'])}")
        for item in report["failed"]:
            log_fn(f"  - {item}")
    log_fn("===============================")


def cleanup(*paths):
    for path in paths:
        try:
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        except OSError:
            pass


def install_modpack_task(target, server_dir=None, log_callback=None, progress_callback=None):
    """Esegue l'installazione completa di un modpack con supporto a callback di log e stato."""
    def log(msg):
        if log_callback:
            log_callback(str(msg))
        else:
            print(msg)

    def progress(pct, status_text=""):
        if progress_callback:
            progress_callback(pct, status_text)

    workdir = Path(tempfile.mkdtemp(prefix="cf_installer_"))
    zip_path = workdir / "modpack.zip"

    try:
        progress(5, "Inizializzazione sessione API...")
        session = requests.Session()
        api_key = load_api_key()
        session.headers.update(make_headers(api_key))

        use_cdn = False
        try:
            probe = requests.get(
                f"{BASE_URL}/games/{MINECRAFT_GAME_ID}",
                headers=make_headers(api_key),
                timeout=30,
            )
            use_cdn = not probe.ok
            if use_cdn:
                log(f"NOTA: Chiave API non attiva o rifiutata (HTTP {probe.status_code}). Uso fonti pubbliche.")
        except Exception as exc:
            log(f"NOTA: {exc}. Uso CDN pubblico.")
            use_cdn = True

        progress(15, "Risoluzione metadati del modpack...")
        if use_cdn:
            ref = widget_ref(target)
            widget = fetch_cfwidget(ref)
            name = widget.get("title", ref)
            input_slug = re.search(r"/minecraft/modpacks/([^/?#]+)", str(target))
            pack_slug = input_slug.group(1) if input_slug else (slug_from_widget(widget) or ref)
            server_dir_path = resolve_server_dir(server_dir, pack_slug)
            mods_dir = ensure_mods_dir(server_dir_path / "mods")
            log(f"=== Installazione modpack: {name} ===")
            log(f"Cartella server di destinazione: {server_dir_path.resolve()}")
            latest = get_latest_release_from_widget(widget)
            log(f"File selezionato: {latest['name']}")
            progress(25, f"Download archivio: {latest['name']}...")
            download_file_cdn(latest["id"], latest["name"], zip_path)
            source = CdnSource()
        else:
            modpack_id = resolve_modpack_id(session, target)
            info = get_mod_info(session, modpack_id)
            name = info.get("name", f"ID {modpack_id}")
            input_slug = re.search(r"/minecraft/modpacks/([^/?#]+)", str(target))
            pack_slug = input_slug.group(1) if input_slug else (info.get("slug") or str(modpack_id))
            server_dir_path = resolve_server_dir(server_dir, pack_slug)
            mods_dir = ensure_mods_dir(server_dir_path / "mods")
            log(f"=== Installazione modpack: {name} ===")
            log(f"Cartella server di destinazione: {server_dir_path.resolve()}")
            latest = get_latest_server_file(session, modpack_id)
            file_title = latest.get("displayName") or latest.get("fileName")
            progress(25, f"Download archivio: {file_title}...")
            fetch_pack_zip(session, latest, zip_path)
            source = ApiSource(session)

        progress(35, "Estrazione manifest.json...")
        manifest = extract_manifest(zip_path, server_dir_path / "manifest.json")
        log(f"Versioni richieste: {summarize_manifest(manifest)}")
        mc_ver = get_minecraft_version(manifest)
        try:
            loader_name, loader_version = parse_mod_loaders(manifest)
        except Exception:
            loader_name, loader_version = "forge", ""

        # Step 1: Install base Minecraft engine, loader and libraries
        progress(40, f"Installazione base server Minecraft {mc_ver} & {loader_name} {loader_version}...")
        try:
            install_loader(session, manifest, server_dir_path, workdir, log_fn=log)
        except Exception as exc:
            log(f"Nota durante l'installazione del loader: {exc}")

        # Step 2: Extract modpack overrides (configs, scripts, kubejs, etc.)
        progress(55, "Estrazione e applicazione configurazioni (overrides)...")
        n_overrides = extract_overrides(zip_path, server_dir_path)
        log(f"Estratti {n_overrides} file di configurazione (overrides) in {server_dir_path.name}.")

        # Step 3: Download mods
        progress(65, "Download delle mod richieste...")
        report = process_manifest_files(source, manifest, mods_dir, log_fn=log, progress_fn=progress)
        print_report(report, log_fn=log)

        # Step 4: Ensure EULA
        progress(95, "Configurazione EULA e salvataggio metadati...")
        if ensure_eula(server_dir_path):
            log("EULA Minecraft accettata automaticamente (eula.txt).")

        # Step 5: Save modpack_metadata.json
        meta_info = {
            "name": name,
            "slug": pack_slug,
            "mc_version": mc_ver,
            "server_type": loader_name.upper(),
            "loader_name": loader_name,
            "loader_version": loader_version,
            "mods_count": len(report["downloaded"]) + len(report["already_present"]),
            "installed_at": datetime.now().isoformat()
        }
        try:
            (server_dir_path / "modpack_metadata.json").write_text(
                json.dumps(meta_info, indent=2), encoding="utf-8"
            )
        except OSError:
            pass

        cleanup(zip_path, workdir)
        progress(100, "Installazione completata con successo!")
        log(f"\nCompletato! Server pronto in: {server_dir_path.resolve()}")

        return {
            "success": True,
            "name": name,
            "slug": pack_slug,
            "server_dir": str(server_dir_path.resolve()),
            "mc_version": mc_ver,
            "server_type": loader_name.upper(),
            "loader_name": loader_name,
            "loader_version": loader_version,
            "report": {
                "downloaded": len(report["downloaded"]),
                "already_present": len(report["already_present"]),
                "skipped_client_only": len(report["skipped_client_only"]),
                "manual": [m[0] for m in report["manual"]],
                "failed": [f[1] if isinstance(f, (list, tuple)) and len(f) > 1 else str(f) for f in report["failed"]],
            }
        }
    except Exception:
        cleanup(zip_path, workdir)
        raise

def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Installa automaticamente un server Minecraft da un modpack "
            "CurseForge: mod, config (overrides), loader Forge/Fabric ed EULA."
        )
    )
    parser.add_argument(
        "modpack",
        help="ID numerico del modpack oppure URL/slug della pagina CurseForge",
    )
    parser.add_argument(
        "--server-dir",
        default=None,
        help="Root del server (default: server_modpacks/<slug> del modpack, una cartella per pack)",
    )
    args = parser.parse_args(argv)

    try:
        install_modpack_task(args.modpack, server_dir=args.server_dir)
    except CurseForgeError as exc:
        print(f"ERRORE: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrotto dall'utente.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
