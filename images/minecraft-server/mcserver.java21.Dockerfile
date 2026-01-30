FROM docker.io/tofran/restic-rclone:0.17.0_1.68.2 AS restic_src

FROM itzg/minecraft-server:java21-alpine

# Install dependencies (curl, bind-tools for nslookup, rclone, bash)
RUN apk add --no-cache curl bind-tools rclone bash

# Official rclone (needed for mutex/backup in MC container)
# RUN curl https://rclone.org/install.sh | bash
# (Installed via apk above, line removed)

# restic 0.17.0 (aligned with restore-backup container)
COPY --from=restic_src /usr/bin/restic /usr/local/bin/restic
RUN chmod +x /usr/local/bin/restic

# Wrapper + start-finalExec
COPY --chown=root:root start-finalExec /start-finalExec
COPY --chown=root:root java-start.sh /java-start.sh

RUN chmod 777 -R /start-finalExec
RUN chmod 777 -R /java-start.sh
RUN chmod 777 -R /data/

# Always start the wrapper: it will call /start as a child process
ENTRYPOINT ["/java-start.sh"]
