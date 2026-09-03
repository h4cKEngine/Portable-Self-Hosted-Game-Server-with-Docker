#!/usr/bin/env python3

"""Scarica un modpack Technic (Server Zip) e prepara un server Minecraft completo.

Uso:
    python utils/scripts/technic_modpack_installer.py <URL_diretto_allo_zip_del_server>

Data l'inaccessibilità dell'API pubblica di Technicpack, questo script si aspetta
un URL diretto al pacchetto "Server" fornito dagli autori del modpack.
Scarica lo zip, lo estrae nella cartella del server, cerca un installer Forge/Fabric
(se presente) per avviarlo, ed accetta la EULA.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

import requests

DEFAULT_SERVER_DIR = Path("server_modpacks")
CHUNK_SIZE = 8192

class TechnicError(Exception):
    pass

def resolve_server_dir(explicit, url):
    if explicit:
        return Path(explicit)
    
    # Cerca di dedurre un nome dallo zip
    name = url.split("/")[-1].split("?")[0]
    if name.endswith(".zip"):
        name = name[:-4]
    
    safe = re.sub(r"[^0-9A-Za-z_.-]", "-", str(name or "technic_modpack"))
    return DEFAULT_SERVER_DIR / safe

def download_file(url, dest_path):
    if not url:
        raise TechnicError("URL di download non disponibile.")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if url.startswith("file://"):
        local_path = Path(url[7:])
        shutil.copy2(local_path, dest_path)
        return dest_path
    elif not url.startswith("http"):
        local_path = Path(url)
        shutil.copy2(local_path, dest_path)
        return dest_path
        
    with requests.get(url, stream=True, timeout=60) as response:
        if not response.ok:
            raise TechnicError(f"Download fallito ({response.status_code}): {url}")
        with open(dest_path, "wb") as fh:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    fh.write(chunk)
    return dest_path

def extract_zip(zip_path, extract_to):
    """Estrae l'intero archivio zip nella directory di destinazione."""
    extract_to = Path(extract_to)
    extract_to.mkdir(parents=True, exist_ok=True)
    
    with zipfile.ZipFile(zip_path) as zf:
        # Cerca se tutto è dentro una sottocartella radice
        top_level_dirs = set()
        for info in zf.infolist():
            parts = Path(info.filename).parts
            if parts:
                top_level_dirs.add(parts[0])
                
        # Se c'è un'unica directory radice che non è 'config' o 'mods', estrai il suo contenuto
        strip_prefix = None
        if len(top_level_dirs) == 1:
            top_dir = list(top_level_dirs)[0]
            if top_dir not in ('config', 'mods', 'bin', 'libraries', 'versions'):
                strip_prefix = top_dir
        
        extracted = 0
        for info in zf.infolist():
            if info.is_dir():
                continue
            
            rel = info.filename
            if strip_prefix and rel.startswith(strip_prefix + "/"):
                rel = rel[len(strip_prefix) + 1:]
                
            if not rel:
                continue
                
            target = (extract_to / rel).resolve()
            
            # Sicurezza path traversal
            if target != extract_to.resolve() and extract_to.resolve() not in target.parents:
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

def find_and_run_installer(server_dir, log_fn=print):
    """Cerca un installer Forge/Fabric nella root ed esegue l'installazione se necessario."""
    server_dir = Path(server_dir)
    
    # Cerca installer noti
    installers = list(server_dir.glob("forge-*-installer.jar")) + \
                 list(server_dir.glob("neoforge-*-installer.jar")) + \
                 list(server_dir.glob("fabric-installer-*.jar"))
                 
    if not installers:
        log_fn("Nessun installer trovato. Il server potrebbe essere gia' pre-installato.")
        return False
        
    installer = installers[0]
    log_fn(f"Trovato installer: {installer.name}")
    
    # Estrai versione mc dal nome per usare il java corretto
    mc_version = "1.12.2"
    m = re.search(r"1\.\d+(\.\d+)?", installer.name)
    if m:
        mc_version = m.group(0)
        
    parts = mc_version.split(".")
    try:
        minor = int(parts[1]) if len(parts) > 1 else 0
        patch = int(parts[2]) if len(parts) > 2 else 0
    except ValueError:
        minor = 12
        patch = 2

    if minor < 17:
        docker_img = "eclipse-temurin:8-jre"
    elif minor < 20 or (minor == 20 and patch < 5):
        docker_img = "eclipse-temurin:17-jre"
    else:
        docker_img = "eclipse-temurin:21-jre"
        
    docker_bin = shutil.which("docker")
    installed = False

    if docker_bin:
        try:
            subprocess.run([str(Path(__file__).parent / "fix-docker-creds.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        log_fn(f"Esecuzione installer server tramite Docker ({docker_img})...")
        abs_server = str(server_dir.resolve())
        
        args = ["--installServer"]
        if "fabric" in installer.name.lower():
            args = ["server", "-downloadMinecraft"]
            
        docker_cmd = [
            docker_bin, "run", "--rm",
            "-v", f"{abs_server}:/server",
            "-w", "/server",
            docker_img,
            "java", "-jar", installer.name
        ] + args
        
        res = subprocess.run(docker_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if res.returncode == 0:
            log_fn("Installazione base server e librerie completata con successo!")
            installed = True
        else:
            log_fn(f"Nota esecuzione installer: {res.stdout[-300:] if res.stdout else ''}")
            
    if not installed:
        java = shutil.which("java")
        if java:
            log_fn(f"Tentativo esecuzione installer tramite Java host ({java})...")
            args = ["--installServer"]
            if "fabric" in installer.name.lower():
                args = ["server", "-downloadMinecraft"]
                
            cmd = [str(java), "-jar", str(installer)] + args
            res = subprocess.run(cmd, cwd=str(server_dir), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if res.returncode == 0:
                log_fn("Installazione base server completata con successo tramite Java host.")
                installed = True
            else:
                log_fn(f"Nota installer host: {res.stdout[-300:] if res.stdout else ''}")
        else:
            log_fn("ATTENZIONE: Java non disponibile per eseguire l'installer in locale.")
            
    return installed

def get_mods_count(server_dir):
    mods_dir = Path(server_dir) / "mods"
    if mods_dir.is_dir():
        return len(list(mods_dir.glob("*.jar")))
    return 0

def resolve_technic_url(target):
    """Risolve uno slug o URL di Technic nell'URL del server pack ZIP."""
    target = target.strip()
    if target.endswith(".zip") or target.startswith("file://"):
        return target, target.split("/")[-1].replace(".zip", "")
        
    # Estrai slug da URL o stringa
    slug = target
    match = re.search(r"technicpack\.net/modpack/([a-zA-Z0-9_-]+)", target)
    if match:
        slug = match.group(1)
        
    try:
        # 1. Ottieni la versione corrente del launcher
        r = requests.get("http://api.technicpack.net/launcher/version/stable4", timeout=15)
        r.raise_for_status()
        build = r.json().get("build", "1133")
        
        # 2. Interroga l'API per il pacchetto
        r = requests.get(f"http://api.technicpack.net/modpack/{slug}?build={build}", timeout=15)
        if r.status_code == 404:
            raise TechnicError(f"Modpack '{slug}' non trovato su Technic.")
        r.raise_for_status()
        
        data = r.json()
        server_url = data.get("serverPackUrl")
        
        if not server_url:
            raise TechnicError(
                f"Il modpack '{data.get('displayName', slug)}' non fornisce un file Server ufficiale su Technic.\n"
                "Installa la versione Client o usa CurseForge se disponibile."
            )
            
        return server_url, slug
    except requests.RequestException as e:
        raise TechnicError(f"Errore di comunicazione con l'API Technic: {e}")

def install_modpack_task(target, server_dir=None, log_callback=None, progress_callback=None):
    def log(msg):
        if log_callback: log_callback(str(msg))
        else: print(msg)

    def progress(pct, status_text=""):
        if progress_callback: progress_callback(pct, status_text)

    workdir = Path(tempfile.mkdtemp(prefix="technic_installer_"))
    zip_path = workdir / "modpack.zip"

    try:
        progress(5, "Risoluzione URL pacchetto server...")
        target_url, pack_slug = resolve_technic_url(target)
        
        progress(10, "Preparazione download...")
        server_dir_path = resolve_server_dir(server_dir, pack_slug)
        log(f"=== Installazione modpack Technic (Direct ZIP) ===")
        log(f"URL: {target_url}")
        log(f"Cartella server di destinazione: {server_dir_path.resolve()}")

        progress(20, "Download archivio server in corso...")
        download_file(target_url, zip_path)
        
        size_mb = zip_path.stat().st_size / (1024 * 1024)
        log(f"Archivio scaricato con successo ({size_mb:.1f} MB).")

        progress(60, "Estrazione file del server...")
        n_files = extract_zip(zip_path, server_dir_path)
        log(f"Estratti {n_files} file nella cartella del server.")

        progress(80, "Ricerca e avvio installer (se presente)...")
        installato = find_and_run_installer(server_dir_path, log_fn=log)

        progress(90, "Configurazione EULA...")
        if ensure_eula(server_dir_path):
            log("EULA Minecraft accettata automaticamente (eula.txt).")

        mods_count = get_mods_count(server_dir_path)

        meta_info = {
            "name": server_dir_path.name,
            "url": target_url,
            "server_type": "TECHNIC_ZIP",
            "mods_count": mods_count,
            "installer_run": installato,
            "installed_at": datetime.now().isoformat()
        }
        try:
            (server_dir_path / "modpack_metadata.json").write_text(
                json.dumps(meta_info, indent=2), encoding="utf-8"
            )
        except OSError:
            pass

        log("\n========== RIEPILOGO ==========")
        log(f"File estratti:          {n_files}")
        log(f"Mod trovate:            {mods_count}")
        log(f"Installer avviato:      {'Si' if installato else 'No (Pre-installato o Assente)'}")
        log("===============================")

        progress(100, "Installazione completata con successo!")
        log(f"\nCompletato! Server pronto in: {server_dir_path.resolve()}")

    except Exception:
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Installa un server Minecraft da uno ZIP di un modpack Technic."
    )
    parser.add_argument(
        "url",
        help="URL diretto al file .zip del pacchetto Server",
    )
    parser.add_argument(
        "--server-dir",
        default=None,
        help="Root del server (default: server_modpacks/<nome>)",
    )
    args = parser.parse_args(argv)

    try:
        install_modpack_task(args.url, server_dir=args.server_dir)
    except TechnicError as exc:
        print(f"ERRORE: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrotto dall'utente.", file=sys.stderr)
        return 130
    return 0

if __name__ == "__main__":
    sys.exit(main())
