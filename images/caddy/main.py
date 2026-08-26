import json
import os
import re
import shutil
import subprocess
import sys
import threading
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from mcstatus import JavaServer

app = FastAPI(title="Minecraft Server Manager & Config API", version="1.0.0")

# Allow localhost / same-origin CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

MC_HOST = os.getenv("MC_HOST", "mc")
MC_PORT = int(os.getenv("MC_PORT", "25565"))

# Determine base env directory (default /app/env inside container, ./env locally)
ENV_DIR_PATH = Path(os.getenv("ENV_DIR", "/app/env")).resolve()
if not ENV_DIR_PATH.exists():
    local_env_dir = Path("./env").resolve()
    if local_env_dir.exists():
        ENV_DIR_PATH = local_env_dir

ENV_FILE_PATH = ENV_DIR_PATH / ".env"
ENV_EXAMPLE_PATH = ENV_DIR_PATH / ".env-example"
RCLONE_CONF_PATH = ENV_DIR_PATH / "rclone.conf"
RCLONE_CONF_EXAMPLE_PATH = ENV_DIR_PATH / "rclone.conf.example"

# Determine server_modpacks directory (default /app/server_modpacks inside container, ./server_modpacks locally)
MODPACKS_DIR_PATH = Path(os.getenv("MODPACKS_DIR", "/app/server_modpacks")).resolve()
if not MODPACKS_DIR_PATH.exists():
    local_modpacks_dir = Path("./server_modpacks").resolve()
    if local_modpacks_dir.exists():
        MODPACKS_DIR_PATH = local_modpacks_dir
    else:
        try:
            MODPACKS_DIR_PATH.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass

# Determine data directory for Minecraft server
DATA_DIR_PATH = Path(os.getenv("DATA_DIR", "/app/data")).resolve()
if not DATA_DIR_PATH.exists():
    local_data_dir = Path("./data").resolve()
    if local_data_dir.exists():
        DATA_DIR_PATH = local_data_dir
    else:
        try:
            DATA_DIR_PATH.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass

# Determine overrides directory for ddns.skip logic
OVERRIDES_DIR_PATH = Path(os.getenv("OVERRIDES_DIR", "/project/overrides")).resolve()
if not OVERRIDES_DIR_PATH.exists():
    local_overrides_dir = Path("./overrides").resolve()
    if local_overrides_dir.exists():
        OVERRIDES_DIR_PATH = local_overrides_dir

# Add utils to sys.path to allow importing curseforge_modpack_installer
for possible_utils in [Path("/app/utils"), Path("./utils").resolve(), Path(__file__).parent.parent.parent / "utils"]:
    if possible_utils.exists() and str(possible_utils) not in sys.path:
        sys.path.insert(0, str(possible_utils))

try:
    import curseforge_modpack_installer as cf_installer
except ImportError:
    try:
        from utils import curseforge_modpack_installer as cf_installer
    except ImportError:
        cf_installer = None

# Task store for ongoing and completed modpack installation jobs
MODPACK_TASKS: Dict[str, Dict] = {}


def slugify(text: str) -> str:
    """Slugify modpack/container name to lowercase alphanumeric, dash, and underscore."""
    if not text:
        return "minecraft-server"
    cleaned = re.sub(r'[^a-zA-Z0-9_-]', '', text.lower()).strip('_-')
    return cleaned or "minecraft-server"


def get_full_ddns_domain(domain: str, provider: str) -> str:
    """Format full FQDN for DDNS domain based on provider."""
    if not domain or not domain.strip():
        return ""
    d = domain.strip()
    if "." in d:
        return d
    p = (provider or "duckdns").strip().lower()
    if p in ["duckdns", "duckdns.org"]:
        return f"{d}.duckdns.org"
    if p in ["desec", "desec.io"]:
        return f"{d}.dedyn.io"
    return d


def derive_ddns_provider_name(provider: str) -> str:
    """Map DDNS provider domain/name to Caddy DNS plugin shortname."""
    if not provider:
        return ""
    norm = provider.strip().lower()
    first_part = norm.split(".")[0]
    mapping = {
        "duckdns": "duckdns",
        "desec": "desec",
        "dynu": "dynu",
        "ydns": "ydns",
        "afraid": "freedns",
        "freedns": "freedns",
        "noip": "noip",
    }
    return mapping.get(first_part, first_part)


def parse_env_file(filepath: Path) -> Dict[str, str]:
    """Parse key-value pairs from a .env file."""
    values: Dict[str, str] = {}
    if not filepath.is_file():
        return values
    
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip()
                if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                values[key] = val
    return values


def parse_rclone_sections() -> Dict[str, Dict[str, str]]:
    """Parse all sections and their properties from rclone.conf."""
    target_conf = RCLONE_CONF_PATH if RCLONE_CONF_PATH.is_file() else RCLONE_CONF_EXAMPLE_PATH
    if not target_conf.is_file():
        return {}

    sections: Dict[str, Dict[str, str]] = {}
    current_sec = None

    with open(target_conf, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            m = re.match(r"^\[([^\]]+)\]", line)
            if m:
                current_sec = m.group(1)
                sections[current_sec] = {}
            elif current_sec and "=" in line:
                k, v = line.split("=", 1)
                sections[current_sec][k.strip()] = v.strip()
    return sections


def parse_rclone_remotes() -> List[str]:
    """Parse configured remote names from rclone.conf."""
    return list(parse_rclone_sections().keys())


def obscure_rclone_password(password: str) -> str:
    """Obscure password using rclone obscure command or fallback."""
    try:
        res = subprocess.run(
            ["rclone", "obscure", password],
            capture_output=True,
            text=True,
            timeout=5
        )
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except Exception:
        pass
    # If rclone command is not available, store with warning or plain
    return password


def upsert_rclone_block(name: str, service_type: str, user: str, password: str) -> None:
    """Add or replace a remote section in rclone.conf."""
    ENV_DIR_PATH.mkdir(parents=True, exist_ok=True)
    conf_file = RCLONE_CONF_PATH

    # Backup existing
    if conf_file.is_file():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = ENV_DIR_PATH / f"rclone.conf.bak.{ts}"
        try:
            shutil.copyfile(conf_file, backup_path)
        except Exception:
            pass

    obscured = obscure_rclone_password(password)

    lines: List[str] = []
    if conf_file.is_file():
        with open(conf_file, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

    # Filter out existing section with this name
    new_lines: List[str] = []
    skip = False
    for line in lines:
        if re.match(rf"^\[{re.escape(name)}\]\s*$", line.strip()):
            skip = True
            continue
        if skip and line.strip().startswith("["):
            skip = False
        if not skip:
            new_lines.append(line)

    # Append new block
    if new_lines and not new_lines[-1].endswith("\n"):
        new_lines[-1] += "\n"
    if new_lines and new_lines[-1].strip():
        new_lines.append("\n")

    new_lines.append(f"[{name}]\n")
    new_lines.append(f"type = {service_type}\n")
    if user:
        new_lines.append(f"user = {user}\n")
    if obscured:
        new_lines.append(f"pass = {obscured}\n")

    with open(conf_file, "w", encoding="utf-8") as f:
        f.writelines(new_lines)


# ─── Pydantic Models ─────────────────────────────────────────────────────────

class ServerConfigModel(BaseModel):
    # Server & Modpack
    name: str = Field(default="minecraft-server", description="Modpack / Container name")
    version: str = Field(default="1.21.1", description="Minecraft version")
    server_type: str = Field(default="FORGE", description="Server engine type")
    ip_server: str = Field(default="127.0.0.1", description="Server Public IP or VPN address (Primary)")
    ip_fallbacks: Optional[str] = Field(default="", description="Comma-separated fallback IPs")
    
    # Engine specific versions
    forge_version: Optional[str] = Field(default="", description="Forge version")
    neoforge_version: Optional[str] = Field(default="", description="NeoForge version")
    fabric_launcher_version: Optional[str] = Field(default="", description="Fabric Launcher version")
    fabric_loader_version: Optional[str] = Field(default="", description="Fabric Loader version")
    
    # Performance & Config
    init_memory: str = Field(default="2G", description="Initial memory (e.g. 2G, 512M)")
    memory: str = Field(default="6G", description="Maximum memory (e.g. 6G, 8G)")
    max_players: int = Field(default=8, ge=1, le=1000, description="Max players")
    motd: Optional[str] = Field(default="", description="Message of the day")
    seed: Optional[str] = Field(default="", description="World seed")
    operators: Optional[str] = Field(default="", description="Comma-separated ops")
    view_distance: int = Field(default=10, ge=2, le=64, description="View distance")
    simulation_distance: int = Field(default=5, ge=2, le=32, description="Simulation distance")
    eula: str = Field(default="TRUE", description="Accept EULA")
    online_mode: str = Field(default="FALSE", description="Online mode")
    
    # Cloud & Rclone
    rclone_service: str = Field(default="mega", description="Rclone remote name")
    rclone_config: str = Field(default="/etc/rclone/rclone.conf", description="Rclone config path")
    rclone_conf_host: str = Field(default="./env/rclone.conf", description="Rclone host path")
    
    # DDNS
    ddns_provider: Optional[str] = Field(default="duckdns", description="DDNS Provider")
    ddns_domain: Optional[str] = Field(default="", description="DDNS Domain")
    ddns_token: Optional[str] = Field(default="", description="DDNS Token / Key")
    ddns_skip: bool = Field(default=False, description="Skip DDNS configuration")
    
    # Restic Backup
    restic_hostname: str = Field(default="MinecraftServer", description="Restic Hostname")
    restic_password: str = Field(default="minecraft", description="Restic encryption password")
    restic_keep_last: int = Field(default=10, ge=1, le=1000, description="Snapshots to keep")
    restic_image: str = Field(default="docker.io/tofran/restic-rclone:0.17.0_1.68.2")
    rcon_password: str = Field(default="minecraft", description="RCON Password")
    backup_enabled: str = Field(default="true")
    
    # AutoStop / AutoPause
    enable_autostop: Optional[str] = Field(default="")
    autostop_timeout_est: Optional[int] = Field(default=3600)
    autostop_timeout_init: Optional[int] = Field(default=1800)
    enable_autopause: Optional[str] = Field(default="")
    max_tick_time: Optional[int] = Field(default=-1)
    pause_when_empty_seconds: int = Field(default=300, ge=0, description="Pause when empty seconds")

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        s = slugify(v)
        if not re.match(r"^[a-zA-Z0-9_-]+$", s):
            raise ValueError("Name can only contain letters, numbers, hyphens and underscores.")
        return s

    @field_validator("version")
    @classmethod
    def validate_version(cls, v: str) -> str:
        if not re.match(r"^[a-zA-Z0-9.-]+$", v.strip()):
            raise ValueError("Invalid Minecraft version format.")
        return v.strip()

    @field_validator("server_type")
    @classmethod
    def validate_server_type(cls, v: str) -> str:
        v_upper = v.strip().upper()
        if v_upper not in ["VANILLA", "FORGE", "FABRIC", "NEOFORGE"]:
            raise ValueError("Server type must be one of: VANILLA, FORGE, FABRIC, NEOFORGE.")
        return v_upper

    @field_validator("init_memory", "memory")
    @classmethod
    def validate_memory(cls, v: str) -> str:
        if not re.match(r"^[0-9]+[MmGg]$", v.strip()):
            raise ValueError("Memory must be in format like '2G' or '512M'.")
        return v.strip().upper()


class RcloneRemoteModel(BaseModel):
    name: str = Field(..., min_length=1, max_length=50, description="Remote name, e.g. mega")
    service_type: str = Field(default="mega", description="Service type: mega, drive, dropbox, s3, etc.")
    user: str = Field(..., description="Username / Email")
    password: str = Field(..., description="Password (will be obscured)")

    @field_validator("name")
    @classmethod
    def validate_remote_name(cls, v: str) -> str:
        s = slugify(v)
        if not s:
            raise ValueError("Invalid remote name.")
        return s


class RcloneTestModel(BaseModel):
    remote_name: str = Field(..., description="Remote name to test")


class RcloneRawModel(BaseModel):
    content: str = Field(..., description="Raw rclone.conf content")


class CurseForgeInfoRequest(BaseModel):
    url_or_id: str = Field(..., min_length=1, max_length=500, description="CurseForge URL, slug, or numeric ID")


class CurseForgeInstallRequest(BaseModel):
    url_or_id: str = Field(..., min_length=1, max_length=500, description="CurseForge URL, slug, or numeric ID")
    server_dir_name: Optional[str] = Field(default=None, description="Optional custom folder name inside server_modpacks")


class CurseForgeActivateRequest(BaseModel):
    slug: str = Field(..., min_length=1, max_length=100, description="Modpack folder slug")
    clean_all_data: bool = Field(default=True, description="Clean all files and folders in data/ before copying to avoid conflicts")





def render_env_content(cfg: ServerConfigModel) -> str:
    """Render structured .env content matching install_and_configure.sh format."""
    final_container_name = slugify(cfg.name)
    final_restic_tag = f"{final_container_name}_backups"
    final_restic_repo = f"rclone:{cfg.rclone_service}:/{final_container_name}"
    final_mutex_dir = f"{cfg.rclone_service}:/{final_container_name}"
    
    if cfg.motd and cfg.motd.strip():
        final_motd = cfg.motd.strip()
    else:
        final_motd = f"§6{final_container_name} §7| §b{cfg.server_type} {cfg.version}"
    
    ddns_prov = (cfg.ddns_provider or "").strip().lower()
    ddns_prov_name = derive_ddns_provider_name(ddns_prov)
    ddns_dom = (cfg.ddns_domain or "").strip()
    ddns_tok = (cfg.ddns_token or "").strip()

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    raw_fallbacks = [x.strip() for x in (cfg.ip_fallbacks or "").split(",") if x.strip()]
    clean_fallbacks = ",".join(raw_fallbacks)

    lines = [
        f"# Generated by Web Configurator on {now_str}",
        "",
        "# === Network ===",
        f"IP_SERVER={cfg.ip_server.strip()}",
        f'IP_FALLBACKS="{clean_fallbacks}"',
        f"DDNS_DOMAIN={ddns_dom}",
        f"DDNS_TOKEN={ddns_tok}",
        f"DDNS_PROVIDER={ddns_prov}",
        f"DDNS_PROVIDER_NAME={ddns_prov_name}",
        "",
        "# === RCON ===",
        f"RCON_PASSWORD={cfg.rcon_password.strip()}",
        f"BACKUP={cfg.backup_enabled}",
        "",
        "# === Server Properties ===",
        f"VERSION={cfg.version.strip()}",
        f"TYPE={cfg.server_type}",
        f"FORGE_VERSION={(cfg.forge_version or '').strip()}",
        f"NEOFORGE_VERSION={(cfg.neoforge_version or '').strip()}",
        f"FABRIC_LAUNCHER_VERSION={(cfg.fabric_launcher_version or '').strip()}",
        f"FABRIC_LOADER_VERSION={(cfg.fabric_loader_version or '').strip()}",
        f"INIT_MEMORY={cfg.init_memory}",
        f"MEMORY={cfg.memory}",
        f"MAX_PLAYERS={cfg.max_players}",
        f'MOTD="{final_motd}"',
        f"SEED={(cfg.seed or '').strip()}",
        f"OPERATORS={(cfg.operators or '').strip()}",
        f"VIEW_DISTANCE={cfg.view_distance}",
        f"SIMULATION_DISTANCE={cfg.simulation_distance}",
        f"EULA={cfg.eula.upper()}",
        f"ONLINE_MODE={cfg.online_mode.upper()}",
        "",
        "# === Restic Backup ===",
        f"RESTIC_HOSTNAME={cfg.restic_hostname.strip()}",
        f"RESTIC_PASSWORD={cfg.restic_password.strip()}",
        f"RESTIC_REPOSITORY={final_restic_repo}",
        f"RESTIC_TAG={final_restic_tag}",
        f"RESTIC_KEEP_LAST={cfg.restic_keep_last}",
        f"RESTIC_IMAGE={cfg.restic_image.strip()}",
        "",
        "# === AutoStop / AutoPause ===",
    ]

    if cfg.enable_autostop:
        lines.append(f"ENABLE_AUTOSTOP={cfg.enable_autostop}")
        lines.append(f"AUTOSTOP_TIMEOUT_EST={cfg.autostop_timeout_est or 3600}")
        lines.append(f"AUTOSTOP_TIMEOUT_INIT={cfg.autostop_timeout_init or 1800}")
    else:
        lines.append("# ENABLE_AUTOSTOP=TRUE")
        lines.append("# AUTOSTOP_TIMEOUT_EST=3600")
        lines.append("# AUTOSTOP_TIMEOUT_INIT=1800")
    
    lines.append("#")
    if cfg.enable_autopause:
        lines.append(f"ENABLE_AUTOPAUSE={cfg.enable_autopause}")
        lines.append(f"MAX_TICK_TIME={cfg.max_tick_time if cfg.max_tick_time is not None else -1}")
    else:
        lines.append("# ENABLE_AUTOPAUSE=TRUE")
        lines.append("# MAX_TICK_TIME=-1")

    lines.append(f"PAUSE_WHEN_EMPTY_SECONDS={cfg.pause_when_empty_seconds}")
    lines.append("")
    lines.append("# === Rclone ===")
    lines.append(f"RCLONE_CONFIG={cfg.rclone_config.strip()}")
    lines.append(f"RCLONE_CONF_HOST={cfg.rclone_conf_host.strip()}")
    lines.append("")
    lines.append("# === Mutex (Locking) ===")
    lines.append(f"MUTEX_REMOTE_DIR={final_mutex_dir}")
    lines.append("")
    lines.append("# === Docker Compose Names ===")
    lines.append(f"MC_CONTAINER_NAME={final_container_name}")
    lines.append("")

    return "\n".join(lines)


# ─── API Endpoints ───────────────────────────────────────────────────────────

@app.get("/api/server-info")
def get_server_info():
    """Returns dynamic server information including full DDNS FQDN."""
    source_file = ENV_FILE_PATH if ENV_FILE_PATH.is_file() else ENV_EXAMPLE_PATH
    parsed = parse_env_file(source_file)
    raw_domain = parsed.get("DDNS_DOMAIN", os.getenv("DDNS_DOMAIN", ""))
    provider = parsed.get("DDNS_PROVIDER", os.getenv("DDNS_PROVIDER", "duckdns"))
    full_domain = get_full_ddns_domain(raw_domain, provider)
    return {
        "ip": parsed.get("IP_SERVER", os.getenv("IP_SERVER", "127.0.0.1")),
        "domain": full_domain,
        "raw_domain": raw_domain,
        "provider": provider,
        "name": parsed.get("MC_CONTAINER_NAME", os.getenv("MC_CONTAINER_NAME", "minecraft-server"))
    }


@app.get("/api/status")
async def get_status():
    """Returns server status via JavaServer lookup (mimics mcsrvstat.us response)."""
    try:
        server = await JavaServer.async_lookup(f"{MC_HOST}:{MC_PORT}", timeout=3.0)
        status = await server.async_status()
        return {
            "online": True,
            "version": status.version.name,
            "players": {
                "online": status.players.online,
                "max": status.players.max
            },
            "motd": {
                "clean": [status.motd.to_plain()]
            }
        }
    except Exception as e:
        return {
            "online": False,
            "error": str(e)
        }


# ─── Rclone API Endpoints ───────────────────────────────────────────────────

@app.get("/api/rclone/remotes")
def get_rclone_remotes():
    """List detected remotes from rclone.conf."""
    sections = parse_rclone_sections()
    remotes_info = []
    for name, props in sections.items():
        remotes_info.append({
            "name": name,
            "type": props.get("type", "unknown"),
            "user": props.get("user", "")
        })
    return {
        "status": "success",
        "remotes": list(sections.keys()),
        "remotes_info": remotes_info
    }


@app.post("/api/rclone/remote")
def add_rclone_remote(model: RcloneRemoteModel):
    """Add or update an rclone remote in rclone.conf."""
    try:
        upsert_rclone_block(
            name=model.name,
            service_type=model.service_type.lower(),
            user=model.user,
            password=model.password
        )
        return {
            "status": "success",
            "message": f"Remote [{model.name}] successfully configured.",
            "remote_name": model.name
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save remote: {str(e)}")


@app.delete("/api/rclone/remote/{remote_name}")
def delete_rclone_remote(remote_name: str):
    """Delete a remote from rclone.conf."""
    conf_file = RCLONE_CONF_PATH
    if not conf_file.is_file():
        raise HTTPException(status_code=404, detail="rclone.conf not found")
    
    with open(conf_file, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    new_lines = []
    skip = False
    for line in lines:
        if re.match(rf"^\[{re.escape(remote_name)}\]\s*$", line.strip()):
            skip = True
            continue
        if skip and line.strip().startswith("["):
            skip = False
        if not skip:
            new_lines.append(line)

    with open(conf_file, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    return {"status": "success", "message": f"Remote [{remote_name}] deleted"}


@app.post("/api/rclone/test")
def test_rclone_connection(model: RcloneTestModel):
    """Test remote connection via rclone lsd."""
    remote = model.remote_name.strip()
    try:
        conf_arg = f"--config={str(RCLONE_CONF_PATH)}" if RCLONE_CONF_PATH.is_file() else ""
        cmd = ["rclone"]
        if conf_arg:
            cmd.append(conf_arg)
        cmd.extend(["lsd", f"{remote}:"])

        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            return {
                "status": "success",
                "connected": True,
                "message": f"Connection to remote '{remote}:' successful!",
                "output": res.stdout.strip()
            }
        else:
            return {
                "status": "warning",
                "connected": False,
                "message": f"Connection test failed: {res.stderr.strip() or res.stdout.strip()}"
            }
    except Exception as e:
        return {
            "status": "error",
            "connected": False,
            "message": f"Error running test: {str(e)}"
        }


@app.get("/api/rclone/raw")
def get_raw_rclone_conf():
    """Get raw rclone.conf content."""
    conf_file = RCLONE_CONF_PATH if RCLONE_CONF_PATH.is_file() else RCLONE_CONF_EXAMPLE_PATH
    if not conf_file.is_file():
        return {"status": "success", "content": ""}
    with open(conf_file, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return {"status": "success", "content": content}


@app.post("/api/rclone/raw")
def save_raw_rclone_conf(model: RcloneRawModel):
    """Save raw rclone.conf content."""
    try:
        ENV_DIR_PATH.mkdir(parents=True, exist_ok=True)
        conf_file = RCLONE_CONF_PATH
        if conf_file.is_file():
            ts = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup_path = ENV_DIR_PATH / f"rclone.conf.bak.{ts}"
            shutil.copyfile(conf_file, backup_path)

        with open(conf_file, "w", encoding="utf-8") as f:
            f.write(model.content)
        return {"status": "success", "message": "rclone.conf successfully updated."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update rclone.conf: {str(e)}")


# ─── Config API Endpoints ────────────────────────────────────────────────────

@app.get("/api/config")
def get_config():
    """Read existing .env or fallback to .env-example and return config object."""
    has_custom_env = ENV_FILE_PATH.is_file()
    source_file = ENV_FILE_PATH if has_custom_env else ENV_EXAMPLE_PATH
    
    parsed = parse_env_file(source_file)
    remotes = parse_rclone_remotes()

    # Extract Rclone remote service name from RESTIC_REPOSITORY or MUTEX_REMOTE_DIR
    rclone_service = "mega"
    if "RESTIC_REPOSITORY" in parsed:
        m = re.search(r"rclone:([^:]+):", parsed["RESTIC_REPOSITORY"])
        if m:
            rclone_service = m.group(1)
    elif "MUTEX_REMOTE_DIR" in parsed:
        m = re.search(r"^([^:]+):", parsed["MUTEX_REMOTE_DIR"])
        if m:
            rclone_service = m.group(1)
    elif remotes:
        rclone_service = remotes[0]

    # Convert numeric fields safely
    def to_int(val: Optional[str], default: int) -> int:
        if val is None:
            return default
        try:
            return int(val)
        except ValueError:
            return default

    config_data = {
        "name": parsed.get("MC_CONTAINER_NAME", "minecraft-server"),
        "version": parsed.get("VERSION", "1.21.1"),
        "server_type": parsed.get("TYPE", "FORGE"),
        "ip_server": parsed.get("IP_SERVER", "127.0.0.1"),
        "ip_fallbacks": parsed.get("IP_FALLBACKS", ""),
        "forge_version": parsed.get("FORGE_VERSION", ""),
        "neoforge_version": parsed.get("NEOFORGE_VERSION", ""),
        "fabric_launcher_version": parsed.get("FABRIC_LAUNCHER_VERSION", ""),
        "fabric_loader_version": parsed.get("FABRIC_LOADER_VERSION", ""),
        "init_memory": parsed.get("INIT_MEMORY", "2G"),
        "memory": parsed.get("MEMORY", "6G"),
        "max_players": to_int(parsed.get("MAX_PLAYERS"), 8),
        "motd": parsed.get("MOTD", ""),
        "seed": parsed.get("SEED", ""),
        "operators": parsed.get("OPERATORS", parsed.get("OPS", "")),
        "view_distance": to_int(parsed.get("VIEW_DISTANCE"), 10),
        "simulation_distance": to_int(parsed.get("SIMULATION_DISTANCE"), 5),
        "eula": parsed.get("EULA", "TRUE"),
        "online_mode": parsed.get("ONLINE_MODE", "FALSE"),
        "rclone_service": rclone_service,
        "rclone_config": parsed.get("RCLONE_CONFIG", "/etc/rclone/rclone.conf"),
        "rclone_conf_host": parsed.get("RCLONE_CONF_HOST", "./env/rclone.conf"),
        "ddns_provider": parsed.get("DDNS_PROVIDER", "duckdns"),
        "ddns_domain": parsed.get("DDNS_DOMAIN", ""),
        "ddns_token": parsed.get("DDNS_TOKEN", ""),
        "ddns_skip": (OVERRIDES_DIR_PATH / "ddns.skip").exists() if OVERRIDES_DIR_PATH.exists() else False,
        "restic_hostname": parsed.get("RESTIC_HOSTNAME", "MinecraftServer"),
        "restic_password": parsed.get("RESTIC_PASSWORD", "minecraft"),
        "restic_keep_last": to_int(parsed.get("RESTIC_KEEP_LAST"), 10),
        "restic_image": parsed.get("RESTIC_IMAGE", "docker.io/tofran/restic-rclone:0.17.0_1.68.2"),
        "rcon_password": parsed.get("RCON_PASSWORD", "minecraft"),
        "backup_enabled": parsed.get("BACKUP", "true"),
        "enable_autostop": parsed.get("ENABLE_AUTOSTOP", ""),
        "autostop_timeout_est": to_int(parsed.get("AUTOSTOP_TIMEOUT_EST"), 3600),
        "autostop_timeout_init": to_int(parsed.get("AUTOSTOP_TIMEOUT_INIT"), 1800),
        "enable_autopause": parsed.get("ENABLE_AUTOPAUSE", ""),
        "max_tick_time": to_int(parsed.get("MAX_TICK_TIME"), -1),
        "pause_when_empty_seconds": to_int(parsed.get("PAUSE_WHEN_EMPTY_SECONDS"), 300),
    }

    sections = parse_rclone_sections()
    remotes_info = [
        {"name": n, "type": p.get("type", "unknown"), "user": p.get("user", "")}
        for n, p in sections.items()
    ]

    return {
        "status": "success",
        "has_custom_env": has_custom_env,
        "config": config_data,
        "available_remotes": remotes,
        "remotes_info": remotes_info,
        "env_path": str(ENV_FILE_PATH)
    }


@app.post("/api/config/preview")
def preview_config(config: ServerConfigModel):
    """Generate and return rendered .env text without saving."""
    content = render_env_content(config)
    return {
        "status": "success",
        "rendered_env": content
    }


@app.post("/api/config")
def save_config(config: ServerConfigModel):
    """Validate, backup, and save new configuration to env/.env."""
    try:
        ENV_DIR_PATH.mkdir(parents=True, exist_ok=True)
        rendered_content = render_env_content(config)

        # Create backup if .env already exists
        if ENV_FILE_PATH.is_file():
            backup_path = ENV_DIR_PATH / ".env.bak"
            shutil.copyfile(ENV_FILE_PATH, backup_path)

        # Write out new .env
        with open(ENV_FILE_PATH, "w", encoding="utf-8") as f:
            f.write(rendered_content)

        # Handle ddns.skip
        if OVERRIDES_DIR_PATH.exists():
            skip_file = OVERRIDES_DIR_PATH / "ddns.skip"
            rename_file = OVERRIDES_DIR_PATH / "ddns.skip-renameme"
            if config.ddns_skip:
                if rename_file.exists():
                    rename_file.rename(skip_file)
            else:
                if skip_file.exists():
                    skip_file.rename(rename_file)

        return {
            "status": "success",
            "message": "Configuration successfully saved to .env",
            "container_name": slugify(config.name),
            "restic_repository": f"rclone:{config.rclone_service}:/{slugify(config.name)}",
            "ddns_provider_name": derive_ddns_provider_name(config.ddns_provider or "")
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save configuration: {str(e)}")


# ─── CurseForge Modpack API Endpoints ───────────────────────────────────────

@app.post("/api/curseforge/info")
def get_curseforge_modpack_info(req: CurseForgeInfoRequest):
    """Fetches metadata and preview information for a CurseForge modpack."""
    if not cf_installer:
        raise HTTPException(status_code=500, detail="CurseForge installer module not available.")

    target = req.url_or_id.strip()
    if not target:
        raise HTTPException(status_code=400, detail="Modpack URL or ID cannot be empty.")

    try:
        info = cf_installer.inspect_modpack(target)
        return {
            "status": "success",
            "modpack": info
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Errore durante l'ispezione del modpack: {str(e)}")


@app.post("/api/curseforge/install")
def start_curseforge_installation(req: CurseForgeInstallRequest):
    """Starts asynchronous modpack installation into server_modpacks/<slug>."""
    if not cf_installer:
        raise HTTPException(status_code=500, detail="CurseForge installer module not available.")

    target = req.url_or_id.strip()
    if not target:
        raise HTTPException(status_code=400, detail="Modpack URL or ID cannot be empty.")

    task_id = str(uuid.uuid4())
    MODPACK_TASKS[task_id] = {
        "id": task_id,
        "target": target,
        "status": "pending",
        "progress": 0,
        "current_step": "Inizializzazione task...",
        "logs": [],
        "created_at": datetime.now().isoformat(),
        "result": None,
        "error": None,
    }

    def run_worker():
        task = MODPACK_TASKS[task_id]
        task["status"] = "running"

        def log_cb(msg: str):
            clean_msg = str(msg).strip()
            if clean_msg:
                task["logs"].append({
                    "time": datetime.now().strftime("%H:%M:%S"),
                    "text": clean_msg
                })

        def progress_cb(pct: int, text: str = ""):
            task["progress"] = max(0, min(100, pct))
            if text:
                task["current_step"] = text

        try:
            target_dir = None
            if req.server_dir_name:
                clean_name = slugify(req.server_dir_name)
                target_dir = MODPACKS_DIR_PATH / clean_name
            else:
                cf_installer.DEFAULT_SERVER_DIR = MODPACKS_DIR_PATH

            res = cf_installer.install_modpack_task(
                target=target,
                server_dir=target_dir,
                log_callback=log_cb,
                progress_callback=progress_cb
            )
            task["status"] = "completed"
            task["progress"] = 100
            task["current_step"] = "Completato con successo!"
            task["result"] = res
        except Exception as exc:
            task["status"] = "failed"
            task["error"] = str(exc)
            task["current_step"] = f"Errore: {str(exc)}"
            log_cb(f"ERRORE FATALE: {exc}")

    t = threading.Thread(target=run_worker, daemon=True)
    t.start()

    return {
        "status": "success",
        "task_id": task_id,
        "message": "Installazione avviata in background."
    }


@app.get("/api/curseforge/tasks/{task_id}")
def get_curseforge_task_status(task_id: str):
    """Get the current progress and logs of a modpack installation task."""
    task = MODPACK_TASKS.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task non trovato.")
    return {
        "status": "success",
        "task": task
    }


@app.get("/api/curseforge/installed")
def list_installed_modpacks():
    """List all installed modpacks found in server_modpacks/ directory."""
    MODPACKS_DIR_PATH.mkdir(parents=True, exist_ok=True)
    modpacks = []

    for p in sorted(MODPACKS_DIR_PATH.iterdir()):
        if p.is_dir() and not p.name.startswith("."):
            # Check modpack_metadata.json first
            metadata_file = p / "modpack_metadata.json"
            manifest_file = p / "manifest.json"
            mods_dir = p / "mods"
            mods_count = len(list(mods_dir.glob("*.jar"))) if mods_dir.is_dir() else 0

            mc_ver = "1.20.1"
            loader = "FORGE"
            loader_ver = ""
            name = p.name

            if metadata_file.is_file():
                try:
                    meta = json.loads(metadata_file.read_text(encoding="utf-8"))
                    name = meta.get("name", name)
                    mc_ver = meta.get("mc_version", mc_ver)
                    loader = (meta.get("server_type") or loader).upper()
                    loader_ver = meta.get("loader_version", loader_ver)
                except Exception:
                    pass
            elif manifest_file.is_file():
                try:
                    data = json.loads(manifest_file.read_text(encoding="utf-8"))
                    name = data.get("name", p.name)
                    mc_data = data.get("minecraft", {})
                    mc_ver = mc_data.get("version", mc_ver)
                    loaders = mc_data.get("modLoaders", [])
                    if loaders:
                        primary = next((l for l in loaders if l.get("primary")), loaders[0])
                        loader_id = str(primary.get("id", ""))
                        l_name, _, l_ver = loader_id.partition("-")
                        loader = l_name.upper()
                        loader_ver = l_ver
                except Exception:
                    pass

            total_size_bytes = 0
            try:
                for f in p.rglob("*"):
                    if f.is_file():
                        total_size_bytes += f.stat().st_size
            except Exception:
                pass

            size_mb = round(total_size_bytes / (1024 * 1024), 1)

            modpacks.append({
                "slug": p.name,
                "name": name,
                "path": str(p.resolve()),
                "mc_version": mc_ver,
                "server_type": loader,
                "loader_version": loader_ver,
                "mods_count": mods_count,
                "size_mb": size_mb,
                "has_eula": (p / "eula.txt").is_file(),
            })

    return {
        "status": "success",
        "modpacks_dir": str(MODPACKS_DIR_PATH),
        "modpacks": modpacks
    }


@app.delete("/api/curseforge/installed/{slug}")
def delete_installed_modpack(slug: str):
    """Safely delete an installed modpack folder."""
    clean_slug = slugify(slug)
    target_dir = (MODPACKS_DIR_PATH / clean_slug).resolve()

    # Strict sandboxing boundary check
    if not str(target_dir).startswith(str(MODPACKS_DIR_PATH.resolve()) + os.sep):
        raise HTTPException(status_code=400, detail="Accesso al percorso non consentito.")

    if not target_dir.exists():
        raise HTTPException(status_code=404, detail="Cartella modpack non trovata.")

    try:
        shutil.rmtree(target_dir)
        return {
            "status": "success",
            "message": f"Modpack '{clean_slug}' eliminato con successo."
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Errore durante l'eliminazione: {str(e)}")


@app.post("/api/curseforge/activate")
def activate_modpack(req: CurseForgeActivateRequest):
    """Copies all modpack files from server_modpacks/<slug> into data/ and applies configuration."""
    clean_slug = slugify(req.slug)
    src_dir = (MODPACKS_DIR_PATH / clean_slug).resolve()

    if not str(src_dir).startswith(str(MODPACKS_DIR_PATH.resolve()) + os.sep):
        raise HTTPException(status_code=400, detail="Percorso non valido.")

    if not src_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Modpack 'server_modpacks/{clean_slug}' non trovato.")

    DATA_DIR_PATH.mkdir(parents=True, exist_ok=True)

    # 1. Clean the entire data/ directory to prevent any conflicts between different modpacks/versions
    if req.clean_all_data:
        if DATA_DIR_PATH.exists():
            for item in list(DATA_DIR_PATH.iterdir()):
                try:
                    if item.is_file() or item.is_symlink():
                        item.unlink()
                    elif item.is_dir():
                        shutil.rmtree(item)
                except OSError:
                    pass

    # 2. Copy contents from server_modpacks/<slug> into data/
    copied_files_count = 0
    for item in src_dir.iterdir():
        dest_item = DATA_DIR_PATH / item.name
        if item.is_dir():
            dest_item.mkdir(parents=True, exist_ok=True)
            for sub_file in item.rglob("*"):
                if sub_file.is_file():
                    rel = sub_file.relative_to(item)
                    target_file = dest_item / rel
                    target_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(sub_file, target_file)
                    copied_files_count += 1
        elif item.is_file():
            shutil.copy2(item, dest_item)
            copied_files_count += 1

    # Ensure required base folders exist
    (DATA_DIR_PATH / "world").mkdir(parents=True, exist_ok=True)
    (DATA_DIR_PATH / "mods").mkdir(parents=True, exist_ok=True)
    (DATA_DIR_PATH / "config").mkdir(parents=True, exist_ok=True)

    # 3. Read metadata / manifest to extract MC version, loader, etc. and update env/.env
    metadata_file = src_dir / "modpack_metadata.json"
    manifest_file = src_dir / "manifest.json"
    name = clean_slug
    mc_ver = "1.20.1"
    loader = "FORGE"
    loader_ver = ""

    if metadata_file.is_file():
        try:
            meta = json.loads(metadata_file.read_text(encoding="utf-8"))
            name = meta.get("name", name)
            mc_ver = meta.get("mc_version", mc_ver)
            loader = (meta.get("server_type") or loader).upper()
            loader_ver = meta.get("loader_version", loader_ver)
        except Exception:
            pass
    elif manifest_file.is_file():
        try:
            data = json.loads(manifest_file.read_text(encoding="utf-8"))
            name = data.get("name", clean_slug)
            mc_data = data.get("minecraft", {})
            mc_ver = mc_data.get("version", mc_ver)
            loaders = mc_data.get("modLoaders", [])
            if loaders:
                primary = next((l for l in loaders if l.get("primary")), loaders[0])
                loader_id = str(primary.get("id", ""))
                l_name, _, l_ver = loader_id.partition("-")
                loader = l_name.upper()
                loader_ver = l_ver
        except Exception:
            pass

    # Read current .env to preserve network/backup settings
    source_env = ENV_FILE_PATH if ENV_FILE_PATH.is_file() else ENV_EXAMPLE_PATH
    current_env = parse_env_file(source_env)

    # Build ServerConfigModel and save
    try:
        cfg = ServerConfigModel(
            name=clean_slug,
            version=mc_ver,
            server_type=loader,
            forge_version=loader_ver if loader == "FORGE" else "",
            neoforge_version=loader_ver if loader == "NEOFORGE" else "",
            fabric_loader_version=loader_ver if loader == "FABRIC" else "",
            motd=f"§6{name} §7| §b{loader} {mc_ver}",
            ip_server=current_env.get("IP_SERVER", "127.0.0.1"),
            ip_fallbacks=current_env.get("IP_FALLBACKS", ""),
            rclone_service=current_env.get("MUTEX_REMOTE_DIR", "mega:/aura").split(":")[0],
            ddns_provider=current_env.get("DDNS_PROVIDER", "duckdns"),
            ddns_domain=current_env.get("DDNS_DOMAIN", ""),
            ddns_token=current_env.get("DDNS_TOKEN", ""),
        )
        save_config(cfg)
    except Exception:
        pass

    return {
        "status": "success",
        "message": f"Modpack '{name}' attivato con successo! Copiati {copied_files_count} file in ./data e aggiornato env/.env.",
        "slug": clean_slug,
        "name": name,
        "mc_version": mc_ver,
        "server_type": loader,
        "loader_version": loader_ver,
        "copied_files": copied_files_count,
        "data_path": str(DATA_DIR_PATH.resolve())
    }

# ─── Server Control Endpoints ───────────────────────────────────────────────
@app.post("/api/server/start")
def start_server():
    """Tells the host agent to start the game server."""
    try:
        with open("/project/logs/action.log", "w") as f:
            f.write("start")
        return {"status": "success", "message": "Server start initiated."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to initiate start: {str(e)}")

@app.post("/api/server/stop")
def stop_server():
    """Tells the host agent to stop the game server."""
    try:
        with open("/project/logs/action.log", "w") as f:
            f.write("stop")
        return {"status": "success", "message": "Server stop initiated."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to initiate stop: {str(e)}")

@app.get("/api/server/logs")
def get_logs():
    """Fetches the latest server logs."""
    logs = []
    try:
        startup = subprocess.check_output(["tail", "-n", "20", "/project/logs/startup.log"], text=True)
        logs.append("--- STARTUP SCRIPT LOGS ---")
        logs.append(startup.strip())
    except Exception:
        pass
        
    try:
        container_name = os.environ.get("MC_CONTAINER_NAME", "minecraft-server")
        mc = subprocess.check_output(["docker", "logs", "--tail", "50", container_name], text=True, stderr=subprocess.STDOUT)
        logs.append("\n--- MINECRAFT SERVER LOGS ---")
        logs.append(mc.strip())
    except Exception:
        pass

    return {"status": "success", "logs": "\n".join(logs)}

# ─── Modpack Management Endpoints ───────────────────────────────────────────
@app.get("/api/modpacks")
def list_modpacks():
    """Lists available modpacks and the currently active one."""
    try:
        active = os.environ.get("MC_CONTAINER_NAME", "minecraft-server")
        available = []
        servers_dir = "/project/servers_played"
        if os.path.isdir(servers_dir):
            for item in os.listdir(servers_dir):
                if os.path.isdir(os.path.join(servers_dir, item)):
                    available.append(item)
        if active not in available:
            available.append(active)
        return {"status": "success", "active": active, "available": sorted(list(set(available)))}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to list modpacks: {str(e)}")

class SwapRequest(BaseModel):
    modpack: str

@app.post("/api/modpacks/swap")
def swap_modpack(req: SwapRequest):
    """Tells the host agent to swap the active modpack."""
    try:
        modpack_name = req.modpack.strip()
        if not modpack_name or "/" in modpack_name or "\\" in modpack_name:
             raise HTTPException(status_code=400, detail="Invalid modpack name")
             
        with open("/project/logs/action.log", "w") as f:
            f.write(f"swap {modpack_name}")
        return {"status": "success", "message": f"Swap to {modpack_name} initiated."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to initiate swap: {str(e)}")

# ─── Tools Execution Endpoints ──────────────────────────────────────────────
class ToolRequest(BaseModel):
    category: str
    action: str
    arg: Optional[str] = None

@app.post("/api/tools/execute")
def execute_tool(req: ToolRequest):
    """Executes utility scripts like restic-tools.sh and rclone-mutex.sh."""
    try:
        script_path = None
        cmd = []
        
        if req.category == "restic":
            script_path = "/project/utils/restic-tools.sh"
            cmd = ["bash", script_path, req.action]
        elif req.category == "mutex":
            script_path = "/project/utils/rclone-mutex.sh"
            cmd = ["bash", script_path, req.action]
        elif req.category == "utils":
            if req.action == "disablemods":
                script_path = "/project/utils/disablemods.sh"
                cmd = ["bash", script_path]
            elif req.action == "sync":
                script_path = "/project/utils/cloud-sync.sh"
                cmd = ["bash", script_path]
                
        if not script_path or not os.path.exists(script_path):
            raise HTTPException(status_code=400, detail="Invalid tool category or action")
            
        if req.arg:
            cmd.append(req.arg)

        # Run the command and capture output
        # Using timeout to prevent hanging endpoints
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            cwd="/project"
        )
        
        return {
            "status": "success" if result.returncode == 0 else "error",
            "message": "Execution finished",
            "returncode": result.returncode,
            "output": result.stdout + "\n" + result.stderr
        }
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Tool execution timed out")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Execution failed: {str(e)}")
