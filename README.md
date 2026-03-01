# Portable Self-Hosted Game Server with Docker

Local hosting of game servers (Minecraft Java Vanilla or Forge/Fabric) containerized (Docker), with periodic backups and synchronization via Cloud Storage (Restic + Rclone).

#### Constraint: prevent two hosts from running the same server simultaneously -> mutex on cloud storage
---

> [Leggi questo documento in Italiano](LEGGIMI.md) 🇮🇹

## What are Restic and Rclone?
Restic manages *what* and *how* to backup, Rclone manages *where* to store it.

- **Restic** is an incremental and deduplicated backup tool. It creates compact snapshots of data, preserving history and allowing selective restore of files or entire folders from any point in time.

- **Rclone** is a synchronization manager for cloud storage (MEGA, Google Drive, Dropbox, etc.). In this project, Restic uses Rclone as a backend to store backups in the cloud, ensuring redundancy and remote access.

### Docker image used

A custom Docker image based on [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) is used, modified to support Java8 and Java17 and update DDNS. For further information on configuration parameters, consult the [itzg_Docs](https://docker-minecraft-server.readthedocs.io/).


## Prerequisites
- **Operating System**: Linux or Windows with WSL2 (Ubuntu recommended).
- **Container Engine**: Docker Engine & Docker Compose (plugin or standalone).
- **Utilities**: `unzip`, `curl` (usually pre-installed or installed by `requirements.sh`).

## Installation

### 1. Configuration Wizard
Start the automatic configurator.
```bash
./install_and_configure.sh
```

```bash
# Or with the --full flag for advanced options (RAM, Forge/Fabric Versions, View Distance, DuckDNS, etc.)
./install_and_configure.sh --full
```

### 2. Cloud Storage Authentication
Link the account (or other cloud supported by [RCLONE](https://rclone.org/overview/)).
```bash
./utils/rclone-manager.sh
# Follow the on-screen instructions
```

### 3. Server Start
```bash
./run-server.sh
```
> **Note**: On first launch, the server will perform a **RESTORE** (automatically) of the latest backup before starting.
> **Note**: `run-server.sh` also performs a **Pre-Restore Sync** of the `./data` folder from the cloud (excluding `world/`) to ensure configuration files are up to date.

---

### Manual Initialization
If manual setup is preferred, it is necessary to:
- Install requirements.sh
- Configure rclone
- Initialize the restic repo in cloud storage

1. Dependency installation:
```bash
bash utils/requirements.sh
```

2. Configure Rclone:
```bash
bash utils/rclone-manager.sh
```

3. Initialize the restic repo in cloud storage:
```bash
bash utils/restic-tools.sh init
```

---

## Modpack and File Management (`./data`)
The project uses the local **`./data`** folder to inject custom files into the server.

- **How it works**: Any file placed in `./data` will be copied (it is not a classic docker volume) into the container, in the `/data` directory, at each startup **overwriting** default files.
- **Common usage**: 
  - Mod configurations (`./data/config/my-mod.cfg`)
  - Scripts (`./data/scripts/tweaks.zs`)
  - Custom `server.properties`
- **Automatic Mod List**: Every time the server starts, a `mods_list.txt` file is updated in the project root with the list of currently installed mods (timestamps are preserved if no changes occurred).

> **Important**: Maintain the same folder structure as the server (e.g. `config`, `mods`, etc.).

---


## Main Commands
| Action | Command |
| :--- | :--- |
| **Start the server** | `./run-server.sh` |
| In the terminal with execution logs, the key combination 'Ctrl+C' | Stops the server and runs **Backup with Restic to Cloud Storage** (automatically, unless in detached mode) |
| **Start Detached** | `./run-server.sh -d` (Runs in background, logs to `logs/compose-up.log`) |

> **Note**: Stopping the container in detached mode will still upload the backup to cloud storage.

## Useful Commands
| Action | Command |
| :--- | :--- |
| **Snapshot List** | `bash utils/restic-tools.sh exec snapshots` |
| **Manual Backup** | `bash utils/restic-tools.sh backup` (requires stopped server) |
| **Restic Unlock** | `bash utils/restic-tools.sh unlock` |
| **Restore from Snapshot** | `bash utils/restic-tools.sh restore <snapshot-id>` |
| **Unlock Mutex Cloud Storage** | `./utils/rclone-mutex.sh set 0` (In case of server crash) |
| **Mutex Status** | `./utils/rclone-mutex.sh status` |
| **Diagnostics** | `./utils/rclone-mutex.sh diag` |
| **Start without Restore from Repo**| `./run-server.sh restoreoff` |
| **Start with Restore from Repo** | `./run-server.sh restoreon` (default behavior) |
| **Upload local current 'world/' to Repo** | `./run-server.sh loadcurrworld` (No server data sync) |
| **Upload local current 'world/' + 'data/' to Repo** | `./run-server.sh loadcurrserver` |
| **Start without Backup** | `./run-server.sh backupoff` (Disable automatic backups on stop, can be used with restoreoff) |
| **Disable Mods** | `./utils/disablemods.sh on` (Disables problematic mods defined in the script) |
| **Enable Mods** | `./utils/disablemods.sh off` (Re-enables problematic mods) |


> **Note** the IP_SERVER in the env/.env file can also use IP addresses from VPN services like [ZeroTier](https://www.zerotier.com/), [Radmin VPN](https://www.radmin-vpn.com/) or [LogMeIn Hamachi](https://www.vpn.net/) to simplify configuration and improve security, through the use of member IP whitelists.
A convenient alternative is to port forward TCP/UDP port 25565 on your router, and set IP_SERVER with your public IP (less secure).

> **Dynamic DNS**: to make client-side access easily accessible, it is possible to set an address using ddns services. To disable DDNS, rename `ddns.skip-renameme` to `ddns.skip`.

# Free DDNS domains

Below are the best free DDNS alternatives, evaluated based on record update speed (TTL), service reliability (QoS), and free plan limitations.

| Service | Link | Speed (TTL) | QoS (Reliability) | Score | Critical Notes |
| --- | --- | --- | --- | --- | --- |
| **Desec.io** | [desec.io](https://desec.io) | **Very High** (~60s) | **Excellent** (Anycast) | **9.5/10** | Focus on security and API. No user-friendly GUI. |
| **Dynu** | [dynu.com](https://www.dynu.com) | **High** | **Great** | **9/10** | Best overall balance. No expiration. |
| **YDNS** | [ydns.io](https://ydns.io) | **High** | **Very Good** | **8.5/10** | EU Hosting. Clean, ad-free. |
| **DuckDNS** | [duckdns.org](https://www.duckdns.org) | **Very High** | **Variable** | **8/10** | (Baseline) Simple, but suffers erratic downtime. |
| **FreeDNS** | [afraid.org](https://freedns.afraid.org) | **Medium** | **Good** | **7.5/10** | Risk of blacklist on some shared domains. |
| **No-IP** | [noip.com](https://noip.com) | **Medium** | **Excellent** | **6/10** | **Requires manual confirmation every 30 days**. |
| **Dynu** | [dynu.com](https://www.dynu.com/) | **High** | **Excellent** | **8/10** | Free plan limited to 1 zone. |

---

## !!! Troubleshooting !!!

- **The server does not start and logs report "Mutex locked"?**
  - Another device has probably already started the server from another location or the server was not closed correctly.
  - Verify with `./utils/rclone-mutex.sh get` or `./utils/rclone-mutex.sh status`.
  - If no one else has the server running, unlock with `./utils/rclone-mutex.sh set 0`.

- **Technical Details**: See [images/STRUCTURE.md](images/STRUCTURE.md) for info on how the system works under the hood.
