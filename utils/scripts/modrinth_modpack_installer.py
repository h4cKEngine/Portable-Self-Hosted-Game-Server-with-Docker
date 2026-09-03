#!/usr/bin/env python3

"""Scarica un modpack Modrinth e prepara un server Minecraft completo.

Uso:
    python utils/scripts/modrinth_modpack_installer.py <modpack_slug_o_id>

Legge la pagina del modpack, scarica il file .mrpack più recente,
estrae l'index, scarica le mod bypassando quelle solo-client e applica gli overrides.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
from datetime import datetime
from pathlib import Path

import requests

BASE_URL = "https://api.modrinth.com/v2"
DEFAULT_SERVER_DIR = Path("server_modpacks")
FORGE_MAVEN_URL = "https://maven.minecraftforge.net/net/minecraftforge/forge"
NEOFORGE_MAVEN_URL = "https://maven.neoforged.net/releases/net/neoforged/neoforge"
FABRIC_META_URL = "https://meta.fabricmc.net/v2"
CHUNK_SIZE = 8192

class ModrinthError(Exception):
    pass

def ensure_mods_dir(mods_dir):
    mods_dir = Path(mods_dir)
    mods_dir.mkdir(parents=True, exist_ok=True)
    return mods_dir

def resolve_server_dir(explicit, pack_slug):
    if explicit:
        return Path(explicit)
    safe = re.sub(r"[^0-9A-Za-z_.-]", "-", str(pack_slug or "modpack"))
    return DEFAULT_SERVER_DIR / safe

def get_project_metadata(session, slug_or_id):
    """Recupera i dati del progetto Modrinth."""
    slug_or_id = slug_or_id.strip("/")
    if "/" in slug_or_id:
        slug_or_id = slug_or_id.split("/")[-1]
    
    url = f"{BASE_URL}/project/{slug_or_id}"
    resp = session.get(url, timeout=15)
    if not resp.ok:
        raise ModrinthError(f"Impossibile trovare il modpack '{slug_or_id}' su Modrinth ({resp.status_code})")
    return resp.json()

def get_latest_version(session, project_id):
    """Ottiene l'ultima versione disponibile del modpack."""
    url = f"{BASE_URL}/project/{project_id}/version"
    resp = session.get(url, timeout=15)
    if not resp.ok:
        raise ModrinthError(f"Impossibile ottenere le versioni per il progetto {project_id}")
    
    versions = resp.json()
    if not versions:
        raise ModrinthError("Nessuna versione trovata per questo modpack.")
    
    # Prendi la prima (più recente)
    latest = versions[0]
    return latest

def download_file(session, url, dest_path):
    if not url:
        raise ModrinthError("URL di download non disponibile.")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    with session.get(url, stream=True, timeout=60) as response:
        if not response.ok:
            raise ModrinthError(f"Download fallito ({response.status_code}): {url}")
        with open(dest_path, "wb") as fh:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    fh.write(chunk)
    return dest_path

def extract_manifest(zip_path, extract_to=None):
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if n == "modrinth.index.json"]
        if not names:
            raise ModrinthError("modrinth.index.json non presente nell'archivio del modpack.")
        raw = zf.read(names[0])
    
    if extract_to:
        target = Path(extract_to)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)

    return json.loads(raw.decode("utf-8"))

def extract_overrides(zip_path, server_dir):
    """Estrae overrides e server-overrides nella root del server."""
    server_dir = Path(server_dir)
    server_dir.mkdir(parents=True, exist_ok=True)
    server_root = server_dir.resolve()
    extracted = 0
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            
            rel = None
            if info.filename.startswith("overrides/"):
                rel = info.filename[len("overrides/"):]
            elif info.filename.startswith("server-overrides/"):
                rel = info.filename[len("server-overrides/"):]
                
            if not rel:
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
    eula_path = Path(server_dir) / "eula.txt"
    if eula_path.exists():
        return False
    eula_path.write_text("# Accettazione EULA Minecraft\neula=true\n", encoding="utf-8")
    return True

# --- INIZIO LOGICA LOADER (condivisa con CurseForge) ---
def get_java_docker_image(mc_version):
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

def get_latest_fabric_installer_version():
    response = requests.get(f"{FABRIC_META_URL}/versions/installer", timeout=60)
    data = response.json()
    if not data or "version" not in data[0]:
        raise ModrinthError("Nessuna versione dell'installer Fabric disponibile.")
    return data[0]["version"]

def build_forge_installer_urls(mc_version, forge_version):
    candidates = []
    candidates.append(f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}-{mc_version}/forge-{mc_version}-{forge_version}-{mc_version}-installer.jar")
    candidates.append(f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}/forge-{mc_version}-{forge_version}-installer.jar")
    candidates.append(f"{FORGE_MAVEN_URL}/{mc_version}-{forge_version}/forge-{mc_version}-{forge_version}-{mc_version}-installer.jar")
    return candidates

def build_neoforge_installer_url(neo_version):
    return f"{NEOFORGE_MAVEN_URL}/{neo_version}/neoforge-{neo_version}-installer.jar"

def install_loader(session, loader_name, loader_version, mc_version, server_dir, log_fn=print):
    if loader_name in ("forge", "neoforge"):
        installer = Path(server_dir) / f"{loader_name}-{mc_version}-{loader_version}-installer.jar"
        log_fn(f"Download installer server {loader_name} ({mc_version}-{loader_version})...")

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
                log_fn(f"Download installer fallito: {e}")

        if not downloaded:
            log_fn(f"ATTENZIONE: Impossibile scaricare installer server per {loader_name} {loader_version}.")
            return False

        docker_bin = shutil.which("docker")
        docker_img = get_java_docker_image(mc_version)
        installed = False

        if docker_bin:
            try:
                subprocess.run([str(Path(__file__).parent / "fix-docker-creds.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
            log_fn(f"Esecuzione installer server {loader_name} tramite Docker ({docker_img})...")
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
                log_fn(f"Installazione base server {loader_name} e librerie completata con successo!")
                installed = True
            else:
                log_fn(f"Nota esecuzione installer: {res.stdout[-300:] if res.stdout else ''}")

        if not installed:
            java = shutil.which("java")
            if java:
                log_fn(f"Tentativo esecuzione installer {loader_name} tramite Java host ({java})...")
                cmd = [str(java), "-jar", str(installer), "--installServer"]
                res = subprocess.run(cmd, cwd=str(server_dir), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                if res.returncode == 0:
                    log_fn(f"Installazione base server {loader_name} completata con successo tramite Java host.")
                    installed = True
                else:
                    log_fn(f"Nota installer host: {res.stdout[-300:] if res.stdout else ''}")
            else:
                log_fn("ATTENZIONE: Java non disponibile per eseguire l'installer in locale.")
        return installed

    if loader_name == "fabric" or loader_name == "quilt-loader":
        # Anche se quilt-loader, possiamo usare una logica simile se ci fosse un installer, ma per fabric:
        installer_version = get_latest_fabric_installer_version()
        url = f"{FABRIC_META_URL}/versions/loader/{mc_version}/{loader_version}/{installer_version}/server/jar"
        dest = Path(server_dir) / f"{loader_name}-server-launch.jar"
        log_fn(f"Download launcher {loader_name} (loader {loader_version}, installer {installer_version})...")
        download_file(session, url, dest)
        log_fn(f"Launcher {loader_name} scaricato con successo.")
        return True

    return False
# --- FINE LOGICA LOADER ---


def process_manifest_files(session, manifest, server_dir, log_fn=print, progress_fn=None):
    server_dir = Path(server_dir)
    report = {
        "downloaded": [],
        "already_present": [],
        "skipped_client_only": [],
        "failed": [],
    }

    files = manifest.get("files", [])
    total_mods = len(files)
    log_fn(f"\nFile richiesti dal manifest: {total_mods}\n")

    for index, entry in enumerate(files, start=1):
        if progress_fn and total_mods > 0:
            pct = 45 + int((index / total_mods) * 40)
            progress_fn(pct, f"Download file [{index}/{total_mods}]...")

        env = entry.get("env", {})
        path = entry.get("path")
        downloads = entry.get("downloads", [])
        
        prefix = f"[{index}/{total_mods}]"
        
        if env.get("server") == "unsupported":
            log_fn(f"{prefix} SKIP (client-only): {path}")
            report["skipped_client_only"].append(path)
            continue
            
        if not downloads:
            log_fn(f"{prefix} SKIP (nessun download): {path}")
            continue

        url = downloads[0]
        dest = server_dir / path
        file_name = dest.name

        if dest.exists():
            log_fn(f"{prefix} Gia' presente: {path}")
            report["already_present"].append(path)
            continue

        try:
            download_file(session, url, dest)
            size_kb = dest.stat().st_size / 1024
            log_fn(f"{prefix} Scaricato: {path} ({size_kb:.0f} KB)")
            report["downloaded"].append(path)
        except Exception as exc:
            log_fn(f"{prefix} Download non riuscito per {path}: {exc}")
            report["failed"].append(path)

    return report


def install_modpack_task(target, server_dir=None, log_callback=None, progress_callback=None):
    def log(msg):
        if log_callback: log_callback(str(msg))
        else: print(msg)

    def progress(pct, status_text=""):
        if progress_callback: progress_callback(pct, status_text)

    workdir = Path(tempfile.mkdtemp(prefix="mr_installer_"))
    zip_path = workdir / "modpack.mrpack"

    try:
        progress(5, "Inizializzazione sessione API...")
        session = requests.Session()
        session.headers.update({"User-Agent": "Antigravity/ModpackInstaller"})

        progress(15, "Risoluzione metadati del modpack...")
        project_meta = get_project_metadata(session, target)
        pack_slug = project_meta.get("slug")
        name = project_meta.get("title", pack_slug)
        server_dir_path = resolve_server_dir(server_dir, pack_slug)
        
        log(f"=== Installazione modpack Modrinth: {name} ===")
        log(f"Cartella server di destinazione: {server_dir_path.resolve()}")

        latest = get_latest_version(session, project_meta["id"])
        
        file_info = None
        for file in latest.get("files", []):
            if file.get("primary"):
                file_info = file
                break
        if not file_info and latest.get("files"):
            file_info = latest["files"][0]
            
        if not file_info:
            raise ModrinthError("Nessun file zip/mrpack associato a questa versione.")

        dl_url = file_info["url"]
        file_name = file_info["filename"]

        progress(25, f"Download archivio: {file_name}...")
        download_file(session, dl_url, zip_path)

        progress(35, "Estrazione modrinth.index.json...")
        manifest = extract_manifest(zip_path, server_dir_path / "modrinth.index.json")
        
        deps = manifest.get("dependencies", {})
        mc_ver = deps.get("minecraft", "1.20.1")
        
        loader_name = "forge"
        loader_version = ""
        for loader_type in ["fabric-loader", "forge", "neoforge", "quilt-loader"]:
            if loader_type in deps:
                loader_name = loader_type.replace("-loader", "")
                loader_version = deps[loader_type]
                break
                
        log(f"Minecraft {mc_ver} con mod loader {loader_name} {loader_version}")

        progress(40, f"Installazione base server Minecraft {mc_ver} & {loader_name} {loader_version}...")
        try:
            install_loader(session, loader_name, loader_version, mc_version, server_dir_path, log_fn=log)
        except Exception as exc:
            log(f"Nota durante l'installazione del loader: {exc}")

        progress(55, "Estrazione e applicazione configurazioni (overrides)...")
        n_overrides = extract_overrides(zip_path, server_dir_path)
        log(f"Estratti {n_overrides} file di configurazione (overrides) in {server_dir_path.name}.")

        progress(65, "Download delle mod richieste...")
        report = process_manifest_files(session, manifest, server_dir_path, log_fn=log, progress_fn=progress)

        progress(95, "Configurazione EULA e salvataggio metadati...")
        if ensure_eula(server_dir_path):
            log("EULA Minecraft accettata automaticamente (eula.txt).")

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

        log("\n========== RIEPILOGO ==========")
        log(f"File scaricati:         {len(report['downloaded'])}")
        log(f"Gia' presenti:          {len(report['already_present'])}")
        log(f"Saltati (client-only):  {len(report['skipped_client_only'])}")
        if report["failed"]:
            log(f"Falliti:                {len(report['failed'])}")
        log("===============================")

        progress(100, "Installazione completata con successo!")
        log(f"\nCompletato! Server pronto in: {server_dir_path.resolve()}")

    except Exception:
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Installa automaticamente un server Minecraft da un modpack Modrinth."
    )
    parser.add_argument(
        "modpack",
        help="ID o slug del progetto Modrinth (es. fabulously-optimized)",
    )
    parser.add_argument(
        "--server-dir",
        default=None,
        help="Root del server (default: server_modpacks/<slug>)",
    )
    args = parser.parse_args(argv)

    try:
        install_modpack_task(args.modpack, server_dir=args.server_dir)
    except ModrinthError as exc:
        print(f"ERRORE: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrotto dall'utente.", file=sys.stderr)
        return 130
    return 0

if __name__ == "__main__":
    sys.exit(main())
