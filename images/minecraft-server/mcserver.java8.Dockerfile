FROM docker.io/tofran/restic-rclone:0.17.0_1.68.2 AS restic_src

FROM itzg/minecraft-server:java8

# Sostituiamo apt-get con apk.
# - curl: serve per scaricare lo script di rclone
# - bind-tools: è il pacchetto Alpine equivalente a dnsutils (fornisce nslookup, dig, ecc.)
# - bash: Alpine utilizza 'ash' di default, ma bash è strettamente necessario per la pipe 'curl | bash' successiva
# Aggiungiamo libc6-compat per supportare i binari nativi Forge/Java8
RUN apt-get update && apt-get install curl dnsutils -y && rm -rf /var/lib/apt/lists/*

# rclone ufficiale (serve per mutex/backup nel container MC)
RUN curl https://rclone.org/install.sh | bash

# restic 0.17.0 (allineato al container restore-backup)
COPY --from=restic_src /usr/bin/restic /usr/local/bin/restic
RUN chmod +x /usr/local/bin/restic

# Wrapper + start-finalExec
COPY --chown=root:root start-finalExec /start-finalExec
COPY --chown=root:root java-start.sh /java-start.sh

RUN chmod 777 -R /start-finalExec
RUN chmod 777 -R /java-start.sh

# Assicuriamo che la directory esista prima di applicare i permessi, 
# per evitare errori di build se il base image non l'ha ancora creata.
RUN mkdir -p /data/ && chmod 777 -R /data/

# Avvia sempre il wrapper: esso chiamerà /start come processo figlio
ENTRYPOINT ["/java-start.sh"]