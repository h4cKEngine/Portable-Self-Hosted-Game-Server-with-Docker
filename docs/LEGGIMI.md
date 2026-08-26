# Portable Self-Hosted Minecraft Server con Docker

Hosting locale di server di gioco (Minecraft Java Vanilla o con mod loader Forge/Fabric) containerizzato (Docker), con backup periodici e sincronizzazione via Cloud Storage (Restic + Rclone).

#### Vincolo: evitare che due host facciano girare lo stesso server contemporaneamente -> mutex su cloud storage
---

> [Read this document in English](../README.md) 🇬🇧

## Cosa sono Restic e Rclone?
Restic gestisce *cosa* e *come* fare il backup, Rclone gestisce *dove* memorizzarlo.

- **Restic** è uno strumento di backup incrementale e deduplicated. Crea snapshot compatti dei dati, conservando la cronologia e permettendo il ripristino selettivo di file o intere cartelle da qualsiasi punto nel tempo.

- **Rclone** è un gestore di sincronizzazione verso cloud storage (MEGA, Google Drive, Dropbox, ecc.). In questo progetto, Restic utilizza Rclone come backend per archiviare i backup nel cloud, garantendo ridondanza e accesso remoto.

### Docker image utilizzata

Viene utilizzata un'immagine Docker personalizzata basata su [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server), modificata per supportare Java8 e Java17 e aggiornare il DDNS. Per ulteriori informazioni sui parametri di configurazione consultare [itzg_Docs](https://docker-minecraft-server.readthedocs.io/).


## Prerequisiti
- **Sistema Operativo**: Linux o Windows con WSL2 (Ubuntu raccomandato).
- **Container Engine**: Docker Engine & Docker Compose (plugin o standalone).
- **Utility**: `unzip`, `curl` (solitamente preinstallati o installati da `requirements.sh`).

## Installazione

### Installazione Rapida per Windows (Consigliata)
Se utilizzi Windows con WSL, il modo più semplice per installare il server è tramite il nostro installer automatico:
1. Vai nella pagina [Releases](https://github.com/h4cKEngine/Portable-Self-Hosted-Game-Server-with-Docker/releases) di questo progetto su GitHub.
2. Scarica il file `Install.bat` dagli assets dell'ultima release.
3. Fai doppio clic sul file scaricato. Lo script si occuperà di scaricare automaticamente il progetto nell'ambiente Linux (WSL) ottimizzato e creerà una comoda icona sul tuo Desktop per avviare il server.

### Installazione Manuale (Linux o Utenti Esperti)
Clona la repository se non l'hai già fatto.

#### 1. Configurazione Wizard
Avviare il configuratore automatico da terminale.
```bash
./utils/install_and_configure.sh
```

```bash
# Oppure con il flag --full per opzioni avanzate (RAM, Versioni Forge/Fabric, View Distance, DuckDNS, ecc.)
./utils/install_and_configure.sh --full
```

#### Web Dashboard di Configurazione (Alternativa)
Puoi anche usare l'interfaccia grafica Web per configurare e gestire il tuo server in modo semplice.
Basta fare doppio clic su `StartDashboard.bat` (Windows) oppure eseguire `./StartDashboard.bash` (Linux/Mac).
Questo aprirà un pannello nel tuo browser dal quale potrai impostare i parametri e avviare il server.

### 2. Autenticazione Cloud Storage
Collegare l'account (o altro cloud supportato da [RCLONE](https://rclone.org/overview/)).
```bash
./utils/rclone-manager.sh
# Seguire le istruzioni a video
```

### 3. Avvio Server
```bash
./run-server.sh
```
> **Nota**: Al primo avvio, il server eseguirà il **RESTORE** (in automatico) dell'ultimo backup prima di avviarsi.
> **Nota**: `run-server.sh` esegue anche un **Pre-Restore Sync** della cartella `./data` dal cloud (escluso `world/`) per garantire che i file di configurazione siano aggiornati.

### 4. Accesso alla Web Dashboard
Una volta che il server è avviato, è disponibile una Web Dashboard per monitorare e gestire il tuo server.
Puoi accedervi aprendo il browser all'indirizzo:
- `http://localhost` (se eseguito localmente)
- `http://<ip-del-server>` (se eseguito su una macchina remota)
- `https://<tuo-dominio-ddns>` (se DDNS e HTTPS sono configurati)

La dashboard è servita da **Caddy**, che funge sia da web server per l'interfaccia utente, sia da reverse proxy per le API backend in Python (accessibili su `/api/`).

---

### Inizializzazione Manuale
Se si preferisce il setup manuale, è necessario:
- Installare i requirements.sh
- Configurare rclone
- Inizializzare la restic repo nel cloud storage

1. Installazione dele dipendenze:
```bash
bash utils/requirements.sh
```

2. Configurare Rclone:
```bash
bash utils/rclone-manager.sh
```

3. Inizializzare la restic repo nel cloud storage:
```bash
bash utils/restic-tools.sh init
```

---

## Gestione Modpack e File (`./data`)
Il progetto usa la cartella **`./data`** locale per iniettare file personalizzati nel server.

- **Come funziona**: Qualsiasi file messo in `./data` verrà copiato (non è un classico volume docker) nel container, nella directory `/data`, ad ogni avvio **sovrascrivendo** i file di default.
- **Uso comune**: 
  - Configurazioni mod (`./data/config/my-mod.cfg`)
  - Script (`./data/scripts/tweaks.zs`)
  - `server.properties` personalizzato.
- **Lista Mod Automatica**: Ad ogni avvio del server, viene generato o aggiornato un file `mods_list.txt` nella directory principale contenente l'elenco delle mod attualmente installate (preservando la data di modifica se non ci sono variazioni).

> **Importante**: Mantenere la stessa struttura delle cartelle del server (es. `config`, `mods`, ecc.).

---


## Comandi principali
| Azione | Comando |
| :--- | :--- |
| **Avvia il server** | `./run-server.sh` |
| Nel terminale con i log di esecuzione, la combinazione di tasti 'Ctrl+C' | Interrompe il server e esegue il **Backup con Restic su Cloud Storage** (in automatico, non in detached) |
| **Avvio Detached** | `./run-server.sh -d` (Esegue in background, log su `logs/compose-up.log`) |

> **Nota**: L'interruzione del container in modalità detached, caricherà comunque il backup su cloud storage.

## Comandi Utili
| Azione | Comando |
| :--- | :--- |
| **Lista Snapshot** | `bash utils/restic-tools.sh exec snapshots` |
| **Backup Manuale** | `bash utils/restic-tools.sh backup` (richiede server fermo) |
| **Restic Unlock** | `bash utils/restic-tools.sh unlock` |
| **Restore da Snapshot** | `bash utils/restic-tools.sh restore <snapshot-id>` |
| **Sblocco Mutex** | `./utils/rclone-mutex.sh set 0` (In caso di crash del server) |
| **Status Mutex** | `./utils/rclone-mutex.sh status` |
| **Diagnostica** | `./utils/rclone-mutex.sh diag` |
| **Start senza Restore dalla Repo**| `./run-server.sh restoreoff` |
| **Start con Restore dalla Repo** | `./run-server.sh restoreon` (comportamento di default) |
| **Caricamento del 'world/' corrente locale alla Repo** | `./run-server.sh loadcurrworld` (Senza sync dati server) |
| **Caricamento del 'world/' + 'data/' locale alla Repo** | `./run-server.sh loadcurrserver` |
| **Start senza Backup** | `./run-server.sh backupoff` (Disabilita backup automatici durante lo stop, può essere usato in combinazione con restoreoff) |
| **Disabilita Mod** | `./utils/disablemods.sh on` (Disabilita le mod problematiche definite nello script) |
| **Abilita Mod** | `./utils/disablemods.sh off` (Riabilita le mod problematiche) |


> **Nota** l'IP_SERVER inserito nel file env/.env può utilizzare anche IP di servizi VPN come [ZeroTier](https://www.zerotier.com/), [Radmin VPN](https://www.radmin-vpn.com/) o [LogMeIn Hamachi](https://www.vpn.net/) per semplificare la configurazione e migliorare la sicurezza, attraverso l'uso di whitelist degli ip dei membri.
Una comoda alternativa è effettuare port forwarding sulla porta TCP/UDP 25565 nel proprio router, e impostare IP_SERVER con il proprio IP pubblico (meno sicuro)

> **Dynamic DNS**: per rendere più facilmente accessibile l'accesso lato client, è possibile impostare un indirizzo utilizzando servizi ddns. Se non si vuole utilizzare il DDNS, è necessario rinominare il file `ddns.skip-renameme` in `ddns.skip`.

# Free DDNS domains

Di seguito sono elencate le migliori alternative DDNS gratuite, valutate in base alla velocità di aggiornamento dei record (TTL), all'affidabilità del servizio (QoS) e alle limitazioni del piano free.

| Servizio | Link | Velocità (TTL) | QoS (Affidabilità) | Punteggio | Note Critiche |
| --- | --- | --- | --- | --- | --- |
| **Desec.io** | [desec.io](https://desec.io) | **Molto Alta** (~60s) | **Eccellente** (Anycast) | **9.5/10** | Focus su sicurezza e API. No GUI user-friendly. |
| **Dynu** | [dynu.com](https://www.dynu.com) | **Alta** | **Ottimo** | **9/10** | Miglior bilanciamento generale. Nessuna scadenza. |
| **YDNS** | [ydns.io](https://ydns.io) | **Alta** | **Molto Buono** | **8.5/10** | Hosting EU. Pulito, senza pubblicità. |
| **DuckDNS** | [duckdns.org](https://www.duckdns.org) | **Molto Alta** | **Variabile** | **8/10** | (Baseline) Semplice, ma soffre di occasionali downtime. |
| **FreeDNS** | [afraid.org](https://freedns.afraid.org) | **Media** | **Buono** | **7.5/10** | Rischio blacklist su alcuni domini condivisi. |
| **No-IP** | [noip.com](https://noip.com) | **Media** | **Eccellente** | **6/10** | **Richiede conferma manuale ogni 30gg**. |
| **Dynu** | [dynu.com](https://www.dynu.com/) | **Alta** | **Eccellente** | **8/10** | Il piano gratuito limita a un solo dominio. |

---

## !!! Troubleshooting !!!

- **Il server non parte e nei log riporta "Mutex locked"?**
  - Probabilmente un altro dispositivo ha già avviato il server da un'altra posizione o il server non si è chiuso correttamente.
  - Verifica con `./utils/rclone-mutex.sh get` oppure con `./utils/rclone-mutex.sh status`.
  - Se nessun altro ha il server avviato, sblocca con `./utils/rclone-mutex.sh set 0`.

- **Dettagli Tecnici**: Vedi [STRUTTURA.md](STRUTTURA.md) per info su come funziona il sistema sotto la scocca.

### Cambio Server (Modpack)
Puoi mantenere più istanze di server isolate (es. modpack diversi) e passare da una all'altra facilmente.

Per cambiare server, esegui:
```bash
./utils/swap-server.sh <nuovo_nome_server>
```

- Questo script sposterà in modo sicuro l'attuale cartella `./data` e copierà la configurazione `./env` in `servers_played/<nome_server_attuale>/`.
- Successivamente caricherà il server specificato in `./data` e `./env`.
- I vecchi container rimangono spenti ma intatti, permettendoti di riprendere esattamente da dove avevi lasciato.
- Se `<nuovo_nome_server>` non esiste, verrà inizializzata una nuova installazione pulita.
