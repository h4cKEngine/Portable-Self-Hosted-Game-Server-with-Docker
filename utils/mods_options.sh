#!/bin/bash
# ==============================================================================
# MODS OPTIONS SCRIPT
# Contains functions specific to particular Minecraft mods
# ==============================================================================


# ==============================================================================
# 1. Auto-OP Users
# ==============================================================================
# Automatically grants OP status to users specified in the .env file
# Monitors server logs for "joined the game" events.
auto_op_users() {
  # Disable exit-on-error for this background function to prevent silent crashes
  set +e
  log "Auto-OP: Starting event-driven monitor (PID $$)..."
  
  # Wait for RCON readiness
  local retries=0
  log "Auto-OP: Entering RCON wait loop..."
  
  while ! docker exec "${MC_CONTAINER_NAME}" rcon-cli list >/dev/null 2>&1; do
      sleep 2
      ((retries++))
      # Log every 10 seconds (every 5 retries)
      if ((retries % 5 == 0)); then
          log "Auto-OP: Waiting for server RCON... ($((retries*2))s elapsed)"
      fi
      if ((retries > 900)); then
          warn "Auto-OP: RCON wait timed out after 30 minutes. Proceeding to monitor logs anyway..."
          break
      fi
  done
  log "Auto-OP: RCON is ready. Monitoring logs for joins..."

  IFS=',' read -ra ADKINS <<< "${OPERATORS:-}"
  log "Auto-OP: Monitoring joins for users: ${OPERATORS}"

  # Tail logs (last 100 lines to catch joins during startup) and process
  # Use stdbuf if available to prevent buffering, otherwise rely on docker's stream
  cmd="docker logs -f --tail 100 ${MC_CONTAINER_NAME}"
  
  $cmd 2>&1 | while read -r line; do
     # Check for join message
     if [[ "$line" == *" joined the game"* ]]; then
         # Debug log mainly to confirm loop is running (comment out if too noisy, but good for now)
         # log "DEBUG: Log line match: $line"
         
         # Extract username using sed
         player_name=$(echo "$line" | sed -n 's/.*: \(.*\) joined the game/\1/p' | tr -d '\r')
         
         if [[ -n "$player_name" ]]; then
             player_name=$(echo "$player_name" | xargs)
             
             # Check if this player is in our OPS list
             for op_user in "${ADKINS[@]}"; do
                 op_user=$(echo "$op_user" | xargs)
                 if [[ "${op_user,,}" == "${player_name,,}" ]]; then
                      log "Auto-OP: Detected join: $player_name. Granting OP..."
                      
                      if out=$(docker exec "${MC_CONTAINER_NAME}" rcon-cli op "$player_name" 2>&1); then
                          log "Auto-OP: RCON result: $out"
                      else
                          warn "Auto-OP: Failed to execute op command for $player_name. Output: $out"
                      fi
                 fi
             done
         fi
     fi
  done
  log "Auto-OP: Monitor loop exited surprisingly."
}

# ==============================================================================
# 2. Update Mods List
# ==============================================================================
# Updates mods_list.txt if there were changes to jar files in mods folder
update_mods_list() {
  local target="./logs/mods_list.txt"
  local temp_file
  temp_file=$(mktemp)

  if [[ -d "./data/mods" ]]; then
    find ./data/mods/ -maxdepth 1 -name "*.jar" -exec basename {} \; | sort > "$temp_file"
  else
    > "$temp_file"
  fi

  if [[ ! -f "$target" ]]; then
    mv "$temp_file" "$target"
    log "Created $target"
  else
    if cmp -s "$temp_file" "$target"; then
      rm "$temp_file"
    else
      mv "$temp_file" "$target"
      log "Updated $target"
    fi
  fi
}

# ==============================================================================
# 3. Optimize Mod Data
# ==============================================================================
# Function to clean up heavy unused data from mods before backups
# Customize the paths and exact find logic based on your needs.
optimize_mod_data() {
    log "Optimizing Mod Data..."
    
    # 1. Clean out excessive old crash reports in ./data
    if [ -d "./data/crash-reports" ]; then
        log "Cleaning up old crash-reports..."
        # Keep only the 5 most recent crash reports
        # shellcheck disable=SC2012
        ls -t ./data/crash-reports/crash-*.txt 2>/dev/null | tail -n +6 | xargs -r rm --
    fi
    
    # 2. Clean out excessive old logs in ./data/logs
    # Minecraft usually automatically gzips logs, but they can still accumulate
    if [ -d "./data/logs" ]; then
        log "Cleaning up old server logs..."
        # Keep logs only from the last 14 days
        find ./data/logs/ -name "*.log.gz" -type f -mtime +14 -delete 2>/dev/null
    fi

    # 3. Add any other specific mod cleanups here
    # Example: Delete old Bluemap/Dynmap high-res renders if they take too much space
    # if [ -d "./data/world/bluemap" ]; then
    #     log "Purging old Bluemap cache..."
    #     find ./data/world/bluemap/web/maps -type f -mtime +30 -delete 2>/dev/null
    # fi
    
    log "Mod optimization complete."
}

# ==============================================================================
# 4. Dungeons Mod: Auto Clean Souls
# ==============================================================================
# The 'dungeons' mod might spawn too many soul entities, causing lag.
# This function sends a kill command via RCON every 5 minutes.
auto_clean_souls() {
    # Disable exit-on-error for this background function to prevent crashes
    set +e
    
    echo "Auto-Clean Souls: Waiting for RCON..."
    local retries=0
    while ! docker exec "${MC_CONTAINER_NAME}" rcon-cli list >/dev/null 2>&1; do
        sleep 5
        ((retries++))
        if ((retries > 180)); then
            echo "Auto-Clean Souls: RCON wait timed out. Proceeding anyway..."
            break
        fi
    done

    while true; do
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] Starting Dungeons mod entity cleanup..."
        # Use docker exec with the correct container name variable
        # Note: if "duneons" was a typo in the mod, you might want to change it to "dungeons"
        docker exec "${MC_CONTAINER_NAME}" rcon-cli "kill @e[type=duneons:soul]"
        echo "[$timestamp] Command sent. Waiting 5 minutes."
        sleep 300
    done
}
