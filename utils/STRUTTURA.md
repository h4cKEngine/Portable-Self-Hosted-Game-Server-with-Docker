# Documentazione Tecnica Distribuita

Questo documento spiega i dettagli interni del funzionamento del server distribuito, utile per debug o manutenzione avanzata.

## 1. Architettura di Avvio e Override
Il sistema di avvio in `run-server.sh` utilizza un meccanismo di "override condizionale" di Docker Compose per gestire il ripristino dei backup.
Questo file serve a gestire le **dipendenze di avvio condizionali**. Docker Compose permette di unire ("merge") più file di configurazione insieme.

### Il Meccanismo
Lo script `run-server.sh` decide dinamicamente quali file passare a Docker:

1.  **Avvio Standard (con Restore)**
    Comando: `docker compose -f docker-compose.yml -f docker-compose.restore-overrides.yml up`
    
    *   Docker carica la configurazione base (`docker-compose.yml`).
    *   Poi sovrascrive/aggiunge le configurazioni del secondo file (`override`).
    *   **Risultato**: Il servizio `mc` riceve l'istruzione `depends_on: restore-backup`. Quindi **aspetta** che il restore finisca con successo prima di avviarsi.

2.  **Avvio Rapido (senza Restore)**
    Comando: `docker compose -f docker-compose.yml up` (senza il secondo file)
    
    *   Docker usa solo la configurazione base.
    *   In `docker-compose.yml`, il servizio `mc` **non ha** la dipendenza.
    *   **Risultato**: Il server parte immediatamente, in parallelo agli altri container.

### Perché è stato fatto così?
Lasciando solo il `depends_on` nel file principale, si sarebbe dovuto aspettare il controllo del backup ad ogni singolo avvio (anche per semplici riavvii di test). Separando la logica in un file extra, si è reso il restore **opzionale** ma attivo di default per sicurezza.

---

## 2. Il Mutex Distribuito (Cloud Lock)
Per evitare che due persone avviino il server contemporaneamente su PC diversi (corrompendo il mondo), utilizziamo un **Mutex su Cloud** gestito da `utils/rclone-mutex.sh`.

### Funzionamento (CAS - Compare And Swap)
Il sistema si basa su un file remoto (es. `mega:/modpack/mutex.txt`) che funge da semaforo.
- **0**: Server libero/spento.
- **1**: Server in esecuzione.

Quando avvii il server, lo script tenta una operazione "CAS" (simulata):
1.  Legge il file remoto.
2.  Se è `0`, lo sovrascrive con `1`.
3.  Se è già `1`, attende e riprova (o fallisce se il timeout scade).

### Keepalive
Una volta acquisito il lock (1), il container `mc` avvia un processo in background che riscrive "1" ogni 60 secondi. Questo serve per:
- Mantenere "calda" la connessione.
- (Opzionale, futuro) Permettere di rilevare crash anomali controllando il timestamp del file.

---

## 3. Backup e Restic
Il backup è gestito da **Restic** tramite il wrapper `utils/restic-tools.sh`.

### Containerizzazione
Restic non gira direttamente sull'host, ma in un container effimero (`tofran/restic-rclone`) per garantire che le versioni delle librerie siano identiche per tutti gli utenti.

### Lifecycle
1.  **Pre-Avvio**: Il container `restore-backup` scarica l'ultimo snapshot marcato con i tag definiti in `.env` (es. `modisland_backups`) nella cartella `/data`.
2.  **Spegnimento**: Lo script `java-start.sh` (entrypoint del container MC) intercetta il segnale di stop (`SIGTERM`), ferma Minecraft gracefully, e poi lancia immediatamente un `restic backup`.

### Comandi utili
Puoi usare `utils/restic-tools.sh` per interagire manualmente col repo:
- `./utils/restic-tools.sh snapshots`: Lista i backup.
- `./utils/restic-tools.sh unlock`: Rimuove lock "stantii" di Restic (da non confondere col Mutex del server).
- `./utils/restic-tools.sh restore <id>`: Ripristina un backup specifico stando offline.

---

## 4. Struttura delle Cartelle
- **/env**: Contiene i segreti (`.env`, `rclone.conf`). **NON committare mai questi file.**
- **/images**: Dockerfile personalizzati.
  - `minecraft-server`: Immagine base itzg personalizzata con i nostri script di avvio.
  - `restic-rclone`: Immagine helper per i backup.
- **/utils**: Script di servizio (mutex, installazione, gestione restic).
