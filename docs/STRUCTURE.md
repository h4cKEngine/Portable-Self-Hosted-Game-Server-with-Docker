# Distributed Technical Documentation

This document explains the internal details of how the distributed server works, useful for debugging or advanced maintenance.

## 1. Startup and Override Architecture
The startup system in `run-server.sh` uses a Docker Compose "conditional override" mechanism to manage backup restoration.
This file serves to manage **conditional startup dependencies**. Docker Compose allows merging multiple configuration files together.

### The Mechanism
The `run-server.sh` script dynamically decides which files to pass to Docker:

1.  **Standard Startup (with Restore)**
    Command: `docker compose -f docker-compose.yml -f docker-compose.restore-overrides.yml up`
    
    *   **Pre-Restore Sync**: Before starting Docker, `run-server.sh` executes `utils/cloud-sync.sh restore`. This downloads any missing or updated files (excluding `world/`) from the Cloud Storage `server-data` folder to the local `./data` directory.
    *   **Mod List Update**: The script checks `./data/mods` and generates/updates `mods_list.txt` in the root folder, preserving unmodified timestamps.
    *   Docker loads the base configuration (`docker-compose.yml`).
    *   Then overwrites/adds configurations from the second file (`override`).
    *   **Result**: The `mc` service receives the `depends_on: restore-backup` instruction. Therefore it **waits** for the restore to finish successfully before starting.

2.  **Fast Startup (without Restore)**
    Command: `docker compose -f docker-compose.yml up` (without the second file)
    
    *   Docker uses only the base configuration.
    *   In `docker-compose.yml`, the `mc` service **does not have** the dependency.
    *   **Result**: The server starts immediately, in parallel with other containers.

### Why was it done this way?
By leaving only `depends_on` in the main file, one would have to wait for the backup check at every single startup (even for simple test restarts). By separating the logic into an extra file, restore was made **optional** but active by default for safety.

### Detached Mode (`-d`)
When running with `./run-server.sh -d`:
- The script executes `docker compose up -d`.
- Output is redirected to `logs/compose-up.log`.
- Next, the script exits directly (monitor daemons `auto-op` and `auto-fml` do **not** run).
- The Backup/Restore lifecycle remains managed by the containers themselves (restore-backup on start, restic on stop via `java-start.sh` trap).

---

## 2. Distributed Mutex (Cloud Lock)
To prevent two people from starting the server simultaneously on different PCs (corrupting the world), we use a **Cloud Mutex** managed by `utils/rclone-mutex.sh`.

### Operation (CAS - Compare And Swap)
The system relies on a remote file (e.g. `mega:/modpack/mutex.txt`) acting as a semaphore.
- **0**: Server free/stopped.
- **1**: Server running.

When you start the server, the script attempts a "CAS" operation (simulated):
1.  Reads the remote file.
2.  If it is `0`, it overwrites it with `1`.
3.  If it is already `1`, it waits and retries (or fails if the timeout expires).

### Keepalive
Once the lock (1) is acquired, the `mc` container starts a background process that rewrites "1" every 60 seconds. This serves to:
- Keep the connection "warm".
- (Optional, future) Allow detection of anomalous crashes by checking the file timestamp.

---

## 3. Backup and Restic
Backup is managed by **Restic** via the wrapper `utils/restic-tools.sh`.

### Containerization
Restic does not run directly on the host, but in an ephemeral container (`tofran/restic-rclone`) to ensure that library versions are identical for all users.

### Lifecycle
1.  **Pre-Startup**: The `restore-backup` container downloads the latest snapshot marked with tags defined in `.env` (e.g. `modisland_backups`) into the `/data` folder.
2.  **Shutdown**: The `java-start.sh` script (entrypoint of the MC container) intercepts the stop signal (`SIGTERM`), stops Minecraft gracefully, and then immediately launches a `restic backup`.

### Useful commands
You can use `utils/restic-tools.sh` to manually interact with the repo:
- `./utils/restic-tools.sh snapshots`: List backups.
- `./utils/restic-tools.sh unlock`: Removes "stale" Restic locks (not to be confused with the Server Mutex).
- `./utils/restic-tools.sh restore <id>`: Restore a specific backup while offline.

---

## 4. Folder Structure
- **/env**: Contains secrets (`.env`, `rclone.conf`). **NEVER commit these files.**
- **/images**: Custom Dockerfiles.
  - `minecraft-server`: Custom base itzg image with our startup scripts.
  - `restic-rclone`: Helper image for backups.
- **/utils**: Service scripts (mutex, installation, restic management, mod disabling).
  - `disablemods.sh`: Utility to temporarily disable specific mods.
