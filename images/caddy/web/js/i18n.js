// Internationalization (i18n) Engine for MC Server Web Interface
// Supports English (ENG - Default) and Italian (ITA)

const I18N_TRANSLATIONS = {
    en: {
        // Navbar
        nav_status: "📊 Status Dashboard",
        nav_config: "⚙️ Server Configurator",
        nav_tools: "🛠️ Server Tools",
        nav_back_dashboard: "Back to Dashboard",
        lang_btn_title: "Click to switch to Italian (ITA)",

        // Dashboard (index.html)
        dash_title: "Minecraft Server",
        dash_subtitle: "Server Status Dashboard",
        dash_autostop_title: "Server in Inactivity Standby (Auto-Stop)",
        dash_autostop_desc: "The server has been stopped automatically to save resources. Click ▶ Start Server to reactivate it.",
        dash_btn_restart_standby: "▶ Reactivate Server",
        dash_checking: "Checking...",
        dash_online: "ONLINE",
        dash_offline: "OFFLINE",
        dash_address: "🌐 Address",
        dash_ip: "📡 IP",
        dash_players: "👥 Players",
        dash_version: "🗺️ Version",
        dash_connect_with: "Connect with:",
        dash_tab_normal: "🌐 Standard IP",
        dash_tab_vpn1: "🔒 VPN 1",
        dash_tab_vpn2: "🛡️ VPN 2",
        dash_tab_ddns: "⚡ Domain",
        dash_btn_copy: "📋 Copy",
        dash_btn_copied: "✅ Copied!",
        dash_btn_start: "▶ Start Server",
        dash_btn_stop: "⏹ Stop Server",
        dash_btn_restart: "🔄 Restart Server",
        dash_btn_logs: "📜 View Logs",
        dash_btn_config: "⚙️ Configurator",
        dash_logs_title: "Server Logs",
        dash_logs_loading: "Loading logs...",
        dash_ip_manager_title: "🌐 Server IP Configuration (server_ips.env)",
        dash_ip_manager_sub: "Manage Standard IP, VPN 1 and VPN 2",
        dash_ip_manager_desc: "Specify up to 3 IP addresses for the server (Standard/LAN IP, ZeroTier VPN 1, Radmin/Hamachi/WireGuard VPN 2). Saved in env/server_ips.env.",
        dash_ip_normal_label: "🌐 Standard / LAN IP",
        dash_ip_normal_ph: "e.g. 127.0.0.1 or 192.168.1.100",
        dash_ip_vpn1_label: "🔒 VPN 1 IP (e.g. ZeroTier)",
        dash_ip_vpn1_ph: "e.g. 10.147.19.45",
        dash_ip_vpn2_label: "🛡️ VPN 2 IP (e.g. Radmin / Hamachi)",
        dash_ip_vpn2_ph: "e.g. 26.15.20.10",
        dash_btn_save_ips: "💾 Save to server_ips.env",
        dash_members_title: "🌐 ZeroTier Members",
        dash_last_updated: "Last updated:",
        dash_btn_refresh: "↻ Refresh",

        // Configurator (config.html)
        cfg_header_title: "Server Environment Configurator",
        cfg_header_subtitle: "Quick setup for server addresses, engine, cloud storage, and domain",
        cfg_status_loading: "⏳ Loading configuration...",
        cfg_status_active: "Active configuration: env/.env",
        cfg_status_example: "⚠️ Using .env-example defaults",
        cfg_status_error: "❌ Could not load config",

        // Tabs
        tab_server_title: "1. Server & Network",
        tab_server_sub: "Name, Engine, IP Addresses",
        tab_modpacks_title: "2. Modpacks & Saves",
        tab_modpacks_sub: "Played Servers, CurseForge",
        tab_cloud_title: "3. Cloud & Domain",
        tab_cloud_sub: "DDNS, Rclone Account",
        tab_advanced_title: "4. Performance & Advanced",
        tab_advanced_sub: "RAM, Restic, Autostop",

        // Config Tab 1: Server & Network
        sec_name_title: "Server Name & Description",
        sec_name_desc: "Server identifier and Message of the Day (MOTD)",
        label_server_name: "Server / Container Name",
        hint_slug: "Generated slug:",
        ph_server_name: "e.g. minecraft-server, all-the-mods",
        label_motd: "Description / Message of the Day (MOTD)",
        opt_motd_colors: "(Supports color codes §a, §6, §b, etc.)",
        ph_motd: "e.g. §6Main Server §7| §bForge 1.21.1",
        label_motd_preview: "In-game MOTD preview:",

        sec_engine_title: "Minecraft Framework & Version",
        sec_engine_desc: "Choose game engine and Minecraft version",
        label_engine: "Framework / Engine",
        label_mc_version: "Minecraft Version",
        hint_mc_version: "e.g. 1.21.1, 1.20.1, 1.12.2",
        label_forge_version: "Forge Version",
        opt_forge_version: "(Optional - leave empty for auto-detection)",
        label_neoforge_version: "NeoForge Version",
        opt_neoforge_version: "(Optional - leave empty for auto)",
        hint_neoforge_notice: "⚡ Note: NeoForge is available only for Minecraft 1.20.2+ (for older versions like 1.19.2 select Forge).",
        label_fabric_launcher: "Fabric Launcher Version",
        label_fabric_loader: "Fabric Loader Version",
        opt_optional: "(Optional)",

        sec_ips_title: "Server IP Addresses (server_ips.env)",
        sec_ips_desc: "Specify 3 IP addresses for the server (Standard/LAN, ZeroTier VPN 1, Radmin/Hamachi VPN 2). Saved in env/server_ips.env.",
        label_ip_normal: "🌐 Standard / LAN IP",
        hint_ip_normal: "Primary or local IP",
        label_ip_vpn1: "🔒 VPN 1 IP (e.g. ZeroTier)",
        hint_ip_vpn1: "ZeroTier / primary VPN address",
        label_ip_vpn2: "🛡️ VPN 2 IP (e.g. Radmin / Hamachi / WireGuard)",
        hint_ip_vpn2: "Secondary VPN or alternative IP",

        // Config Tab 2: Modpacks & Saves
        sec_played_title: "Played Servers (World Saves in servers_played/)",
        sec_played_desc: "Select existing server worlds with player progress to load into active server.",
        status_active_server: "🎮 Currently Active Server:",
        badge_active_data: "Active in ./data",
        label_select_played: "Select Played Server to Load:",
        btn_swap_modpack: "🔄 Swap Server",
        empty_played_servers: "No played servers found in servers_played/.",

        sec_cf_title: "CurseForge Modpack Downloader",
        sec_cf_desc_prefix: "Download clean modpacks from ",
        sec_cf_desc_suffix: " into server_modpacks/ folder (without world).",
        ph_cf_input: "Paste CurseForge link (e.g. https://www.curseforge.com/minecraft/modpacks/better-mc-forge-bmc4) or slug",
        btn_cf_search: "🔍 Search Modpack",
        hint_cf_support: "Supports full CurseForge URLs, slugs (e.g. all-the-mods-9) or numeric IDs.",
        meta_file: "📁 File:",
        meta_downloads: "📥 Downloads:",
        meta_updated: "📅 Updated:",
        btn_cf_install: "⬇️ Download & Install in server_modpacks/",
        btn_cf_apply: "⚡ Apply Modpack to Config",
        console_cf_header: "📟 Installation Console Log",
        btn_console_clear: "Clear",
        cf_installed_title: "📂 Downloaded Modpacks (Ready to activate in server_modpacks/)",
        cf_installed_sub: "Clean files without world. Click \"Activate on Server\" to start a fresh playthrough.",
        btn_refresh_list: "🔄 Refresh List",
        cf_empty_notice: "No modpacks currently downloaded in server_modpacks/.",

        // Config Tab 3: Cloud & Domain
        sec_ddns_title: "Dynamic DNS Account (DDNS)",
        sec_ddns_desc: "Assign a dynamic hostname to the server so friends can connect without remembering numeric IPs",
        provider_duckdns: "🦆 DuckDNS",
        provider_duckdns_sub: "Recommended & Simple",
        provider_desec: "🔒 DeSEC.io",
        provider_desec_sub: "Secure & Modern API",
        provider_dynu: "🌍 Dynu",
        provider_dynu_sub: "No expiration",
        provider_ydns: "🇪🇺 YDNS",
        provider_ydns_sub: "European hosting",
        provider_freedns: "🆓 FreeDNS",
        provider_freedns_sub: "afraid.org",
        provider_noip: "⚡ No-IP",
        provider_noip_sub: "Standard hostname",
        provider_disabled: "🚫 Disabled",
        provider_disabled_sub: "Direct IP only",
        label_ddns_provider: "DDNS Provider",
        hint_caddy_plugin: "Caddy Plugin:",
        label_ddns_domain: "DDNS Domain Name",
        label_ddns_token: "DDNS Token / Password",
        ph_ddns_token: "Enter provider token or password",
        chk_skip_ddns: "Skip DDNS updates (disables container DDNS script, useful if using static IP or router DDNS)",

        sec_rclone_title: "Rclone Account & Cloud Storage",
        sec_rclone_desc: "Configure and manage cloud accounts (MEGA, Google Drive, etc.) for Restic backups and Mutex lock",
        btn_add_cloud_acc: "➕ Add Cloud Account",
        btn_edit_rclone_conf: "✏️ Edit rclone.conf",
        label_remotes_configured: "Configured accounts in env/rclone.conf:",
        label_active_rclone: "Active Rclone Account for Server",
        hint_mutex_path: "The selected remote will be used for backups and cloud lock:",
        chk_skip_rclone: "Skip Rclone Cloud operations (disables cloud mutex lock and remote backup upload)",

        // Config Tab 4: Performance & Advanced
        sec_ram_title: "Performance & RAM Memory",
        sec_ram_desc: "Allocate memory resources for the Minecraft server process",
        label_init_ram: "Initial RAM (Min)",
        label_max_ram: "Maximum RAM (Max)",

        sec_game_title: "Game Options & Rules",
        sec_game_desc: "Configure player limits, world seed, administrators and render chunk distances",
        label_max_players: "Max Players",
        label_seed: "World Seed",
        ph_seed: "Leave empty for random seed",
        label_ops: "Operators / Admins (comma separated)",
        ph_ops: "player1,player2",
        label_rcon_pass: "RCON Password",
        label_view_dist: "View Distance (Chunks)",
        label_sim_dist: "Simulation Distance (Chunks)",
        label_online_mode: "Online Mode (Mojang Authentication)",
        hint_online_off: "OFF (Allows offline/cracked connections)",
        hint_online_on: "ON (Requires official Mojang accounts)",

        sec_restic_title: "Restic Backups & Container Maintenance",
        sec_restic_desc: "Encrypted snapshot configuration and automated container suspension",
        label_restic_host: "Restic Hostname",
        label_restic_pass: "Restic Encryption Password",
        label_restic_keep: "Number of Snapshots to Keep",
        label_pause_empty: "Pause if Empty (Seconds)",
        label_autostop: "AutoStop Container when inactive",

        // Floating Action Bar
        dock_reload: "🔄 Reload",
        dock_view_env: "👁️ View .env",
        dock_download_env: "📥 Download .env",
        dock_save_cfg: "💾 Save Configuration",

        // Modals
        modal_confirm_title: "💾 Confirm Configuration Save",
        modal_confirm_desc: "The following settings will be saved to env/.env (a backup will be created as .env.bak):",
        modal_btn_cancel: "Cancel",
        modal_btn_confirm_save: "✅ Save to env/.env",
        modal_raw_env_title: "📄 Preview env/.env",
        modal_btn_copy: "📋 Copy",
        modal_btn_close: "Close",
        modal_add_remote_title: "☁️ Add Cloud Storage Account",
        modal_remote_name: "Remote Account Name",
        modal_remote_name_hint: "Unique short name (e.g. mega)",
        modal_cloud_service: "Cloud Service",
        modal_remote_user: "Email / Username",
        modal_remote_pass: "Password / API Key",
        modal_remote_pass_hint: "Password will be automatically obfuscated via rclone",
        modal_btn_save_remote: "💾 Save Account",
        modal_edit_rclone_title: "📄 Edit env/rclone.conf",
        modal_btn_save_rclone: "💾 Save rclone.conf",

        // Tools (tools.html)
        tools_title: "Server Tools & Utilities",
        tools_subtitle: "Execute maintenance scripts like Restic and Rclone directly from the web UI",
        tools_restic_title: "Restic Backups (restic-tools.sh)",
        tools_restic_desc: "Manage encrypted backups of your world and server data.",
        tools_btn_doctor: "🏥 Doctor (Check Repo)",
        tools_btn_unlock: "🔓 Unlock Repo",
        tools_btn_backup_offline: "💾 Backup Offline",
        tools_mutex_title: "Cloud Mutex (rclone-mutex.sh)",
        tools_mutex_desc: "Manage the cloud lock to prevent multiple servers from starting simultaneously.",
        tools_btn_mutex_get: "🔍 Get Mutex Status",
        tools_btn_mutex_lock: "🔴 Lock (Set 1)",
        tools_btn_mutex_unlock: "🟢 Unlock (Set 0)",
        tools_utils_title: "Other Utilities",
        tools_utils_desc: "Miscellaneous helpful scripts for maintenance.",
        tools_btn_disable_mods: "🚫 Disable Client Mods",
        tools_btn_cloud_sync: "☁️ Cloud Sync (pull)",

        // General messages
        toast_config_loaded: "Configuration loaded successfully!",
        toast_config_saved: "Configuration saved successfully in env/.env and env/server_ips.env!",
        toast_copied: "Copied to clipboard!",
    },
    it: {
        // Navbar
        nav_status: "📊 Status Dashboard",
        nav_config: "⚙️ Server Configurator",
        nav_tools: "🛠️ Server Tools",
        nav_back_dashboard: "Torna alla Dashboard",
        lang_btn_title: "Clicca per passare all'Inglese (ENG)",

        // Dashboard (index.html)
        dash_title: "Minecraft Server",
        dash_subtitle: "Server Status Dashboard",
        dash_autostop_title: "Server in Standby per Inattività (Auto-Stop)",
        dash_autostop_desc: "Il server è stato spento automaticamente per risparmiare risorse. Clicca su ▶ Start Server per riaccenderlo.",
        dash_btn_restart_standby: "▶ Riattiva Server",
        dash_checking: "Controllo in corso...",
        dash_online: "ONLINE",
        dash_offline: "OFFLINE",
        dash_address: "🌐 Indirizzo",
        dash_ip: "📡 IP",
        dash_players: "👥 Giocatori",
        dash_version: "🗺️ Versione",
        dash_connect_with: "Connettiti con:",
        dash_tab_normal: "🌐 IP Normale",
        dash_tab_vpn1: "🔒 VPN 1",
        dash_tab_vpn2: "🛡️ VPN 2",
        dash_tab_ddns: "⚡ Dominio",
        dash_btn_copy: "📋 Copia",
        dash_btn_copied: "✅ Copiato!",
        dash_btn_start: "▶ Start Server",
        dash_btn_stop: "⏹ Stop Server",
        dash_btn_restart: "🔄 Restart Server",
        dash_btn_logs: "📜 Log Server",
        dash_btn_config: "⚙️ Configuratore",
        dash_logs_title: "Log del Server",
        dash_logs_loading: "Caricamento log...",
        dash_ip_manager_title: "🌐 Configurazione Indirizzi IP (server_ips.env)",
        dash_ip_manager_sub: "Gestisci IP Normale, VPN 1 e VPN 2",
        dash_ip_manager_desc: "Specifica fino a 3 indirizzi IP per il server (IP Normale/LAN, VPN 1 ZeroTier, VPN 2 Radmin/Hamachi/WireGuard). Vengono salvati in env/server_ips.env.",
        dash_ip_normal_label: "🌐 IP Normale / LAN",
        dash_ip_normal_ph: "es. 127.0.0.1 o 192.168.1.100",
        dash_ip_vpn1_label: "🔒 IP VPN 1 (es. ZeroTier)",
        dash_ip_vpn1_ph: "es. 10.147.19.45",
        dash_ip_vpn2_label: "🛡️ IP VPN 2 (es. Radmin / Hamachi)",
        dash_ip_vpn2_ph: "es. 26.15.20.10",
        dash_btn_save_ips: "💾 Salva in server_ips.env",
        dash_members_title: "🌐 Membri ZeroTier",
        dash_last_updated: "Ultimo aggiornamento:",
        dash_btn_refresh: "↻ Aggiorna",

        // Configurator (config.html)
        cfg_header_title: "Configuratore Server",
        cfg_header_subtitle: "Configurazione rapida per indirizzi, motore, cloud storage e dominio",
        cfg_status_loading: "⏳ Caricamento configurazione...",
        cfg_status_active: "Configurazione attiva: env/.env",
        cfg_status_example: "⚠️ Utilizzo valori predefiniti da .env-example",
        cfg_status_error: "❌ Impossibile caricare la configurazione",

        // Tabs
        tab_server_title: "1. Server & Rete",
        tab_server_sub: "Nome, Engine, Indirizzi IP",
        tab_modpacks_title: "2. Modpack & Salvataggi",
        tab_modpacks_sub: "Server Giocati, CurseForge",
        tab_cloud_title: "3. Cloud & Dominio",
        tab_cloud_sub: "DDNS, Account Rclone",
        tab_advanced_title: "4. Avanzate",
        tab_advanced_sub: "RAM, Restic, Autostop",

        // Config Tab 1: Server & Network
        sec_name_title: "Nome Server & Descrizione",
        sec_name_desc: "Identificatore del server e messaggio di benvenuto (MOTD)",
        label_server_name: "Nome Server / Container",
        hint_slug: "Slug generato:",
        ph_server_name: "es. minecraft-server, all-the-mods",
        label_motd: "Descrizione / Message of the Day (MOTD)",
        opt_motd_colors: "(Supporta i codici colore §a, §6, §b, ecc.)",
        ph_motd: "es. §6Server Principale §7| §bForge 1.21.1",
        label_motd_preview: "Anteprima MOTD in gioco:",

        sec_engine_title: "Framework & Versione Minecraft",
        sec_engine_desc: "Scegli il motore di gioco e la versione di Minecraft",
        label_engine: "Framework / Engine",
        label_mc_version: "Versione Minecraft",
        hint_mc_version: "es. 1.21.1, 1.20.1, 1.12.2",
        label_forge_version: "Versione Forge",
        opt_forge_version: "(Opzionale - lascia vuoto per rilevamento automatico)",
        label_neoforge_version: "Versione NeoForge",
        opt_neoforge_version: "(Opzionale - lascia vuoto per auto)",
        hint_neoforge_notice: "⚡ Nota: NeoForge è disponibile solo da Minecraft 1.20.2 in poi (per versioni precedenti come 1.19.2 seleziona Forge).",
        label_fabric_launcher: "Fabric Launcher Version",
        label_fabric_loader: "Fabric Loader Version",
        opt_optional: "(Opzionale)",

        sec_ips_title: "Indirizzi IP Server (server_ips.env)",
        sec_ips_desc: "Specifica i 3 indirizzi IP per il server (IP Normale/LAN, VPN 1 ZeroTier, VPN 2 Radmin/Hamachi). Salvati in env/server_ips.env.",
        label_ip_normal: "🌐 IP Normale / LAN",
        hint_ip_normal: "IP principale o locale",
        label_ip_vpn1: "🔒 IP VPN 1 (es. ZeroTier)",
        hint_ip_vpn1: "Indirizzo ZeroTier / VPN primaria",
        label_ip_vpn2: "🛡️ IP VPN 2 (es. Radmin / Hamachi / WireGuard)",
        hint_ip_vpn2: "Seconda VPN o IP alternativo",

        // Config Tab 2: Modpacks & Saves
        sec_played_title: "Server Giocati (Salvataggi Mondo in servers_played/)",
        sec_played_desc: "Scegli tra i server con progressi e mondo salvato per caricarli come server attivo.",
        status_active_server: "🎮 Server Attualmente Attivo:",
        badge_active_data: "Attivo in ./data",
        label_select_played: "Seleziona Server Giocato da Caricare:",
        btn_swap_modpack: "🔄 Swap Server",
        empty_played_servers: "Nessun server giocato trovato in servers_played/.",

        sec_cf_title: "Downloader Modpack CurseForge",
        sec_cf_desc_prefix: "Scarica nuovi modpack puliti da ",
        sec_cf_desc_suffix: " nella cartella server_modpacks/ (senza mondo).",
        ph_cf_input: "Incolla link CurseForge (es. https://www.curseforge.com/minecraft/modpacks/better-mc-forge-bmc4) o slug",
        btn_cf_search: "🔍 Cerca Modpack",
        hint_cf_support: "Supporta URL completi di CurseForge, slug (es. all-the-mods-9) o ID numerici.",
        meta_file: "📁 File:",
        meta_downloads: "📥 Download:",
        meta_updated: "📅 Aggiornato:",
        btn_cf_install: "⬇️ Scarica & Installa in server_modpacks/",
        btn_cf_apply: "⚡ Compila Configurazione con questo Modpack",
        console_cf_header: "📟 Log di Installazione Console",
        btn_console_clear: "Pulisci",
        cf_installed_title: "📂 Modpack Scaricati (Pronti per l'Attivazione in server_modpacks/)",
        cf_installed_sub: "File puliti senza mondo. Clicca su \"Attiva nel Server\" per avviare una nuova partita.",
        btn_refresh_list: "🔄 Aggiorna Lista",
        cf_empty_notice: "Nessun modpack attualmente scaricato in server_modpacks/.",

        // Config Tab 3: Cloud & Domain
        sec_ddns_title: "Account Dynamic DNS (DDNS)",
        sec_ddns_desc: "Assegna un dominio dinamico al server per connettersi senza ricordare l'indirizzo IP",
        provider_duckdns: "🦆 DuckDNS",
        provider_duckdns_sub: "Consigliato & Semplice",
        provider_desec: "🔒 DeSEC.io",
        provider_desec_sub: "Sicuro & API",
        provider_dynu: "🌍 Dynu",
        provider_dynu_sub: "Nessuna scadenza",
        provider_ydns: "🇪🇺 YDNS",
        provider_ydns_sub: "Hosting europeo",
        provider_freedns: "🆓 FreeDNS",
        provider_freedns_sub: "afraid.org",
        provider_noip: "⚡ No-IP",
        provider_noip_sub: "Dominio standard",
        provider_disabled: "🚫 Disabilitato",
        provider_disabled_sub: "Solo IP diretto",
        label_ddns_provider: "Provider DDNS",
        hint_caddy_plugin: "Plugin Caddy:",
        label_ddns_domain: "Nome Dominio DDNS",
        label_ddns_token: "Token / Password DDNS",
        ph_ddns_token: "Inserisci il token o la password del provider",
        chk_skip_ddns: "Ignora aggiornamento DDNS (disabilita script DDNS nel container, utile se hai IP statico o lo gestisci sul router)",

        sec_rclone_title: "Account Rclone & Cloud Storage",
        sec_rclone_desc: "Configura e gestisci gli account cloud (MEGA, Google Drive, ecc.) per i backup Restic e il blocco Mutex",
        btn_add_cloud_acc: "➕ Aggiungi Account Cloud",
        btn_edit_rclone_conf: "✏️ Modifica rclone.conf",
        label_remotes_configured: "Account configurati in env/rclone.conf:",
        label_active_rclone: "Account Rclone Attivo per il Server",
        hint_mutex_path: "Il remoto selezionato verrà usato per i backup e il cloud lock:",
        chk_skip_rclone: "Ignora operazioni Cloud Rclone (disabilita lock mutex e upload backup cloud)",

        // Config Tab 4: Performance & Advanced
        sec_ram_title: "Prestazioni",
        sec_ram_desc: "Alloca le risorse di memoria RAM per il server Minecraft",
        label_init_ram: "RAM Iniziale (Min)",
        label_max_ram: "RAM Massima (Max)",

        sec_game_title: "Opzioni di Gioco & Regole",
        sec_game_desc: "Configura limiti giocatori, seed del mondo, amministratori e rendering chunks",
        label_max_players: "Giocatori Max",
        label_seed: "Seed del Mondo",
        ph_seed: "Lascia vuoto per seed casuale",
        label_ops: "Operatori / Admin (separati da virgola)",
        ph_ops: "player1,player2",
        label_rcon_pass: "Password RCON",
        label_view_dist: "View Distance (Chunks)",
        label_sim_dist: "Simulation Distance (Chunks)",
        label_online_mode: "Online Mode (Autenticazione Mojang)",
        hint_online_off: "OFF (Permette connessioni offline)",
        hint_online_on: "ON (Richiede account ufficiali Mojang)",

        sec_restic_title: "Backup Restic & Manutenzione Container",
        sec_restic_desc: "Configurazione snapshot crittografati e gestione sospensione container",
        label_restic_host: "Restic Hostname",
        label_restic_pass: "Password Crittografia Restic",
        label_restic_keep: "Numero Snapshot da Mantenere",
        label_pause_empty: "Pausa se Vuoto (Secondi)",
        label_autostop: "AutoStop Container quando inattivo",

        // Floating Action Bar
        dock_reload: "🔄 Ricarica",
        dock_view_env: "👁️ Visualizza .env",
        dock_download_env: "📥 Scarica .env",
        dock_save_cfg: "💾 Salva Configurazione",

        // Modals
        modal_confirm_title: "💾 Conferma Salvataggio",
        modal_confirm_desc: "Le seguenti impostazioni verranno salvate in env/.env (un backup sarà salvato come .env.bak):",
        modal_btn_cancel: "Annulla",
        modal_btn_confirm_save: "✅ Salva in env/.env",
        modal_raw_env_title: "📄 Anteprima env/.env",
        modal_btn_copy: "📋 Copia",
        modal_btn_close: "Chiudi",
        modal_add_remote_title: "☁️ Aggiungi Account Cloud Storage",
        modal_remote_name: "Nome Account Remoto",
        modal_remote_name_hint: "Nome breve univoco (es. mega)",
        modal_cloud_service: "Servizio Cloud",
        modal_remote_user: "Email / Username",
        modal_remote_pass: "Password / Chiave API",
        modal_remote_pass_hint: "La password verrà offuscata automaticamente con rclone",
        modal_btn_save_remote: "💾 Salva Account",
        modal_edit_rclone_title: "📄 Modifica env/rclone.conf",
        modal_btn_save_rclone: "💾 Salva rclone.conf",

        // Tools (tools.html)
        tools_title: "Strumenti Server & Utilità",
        tools_subtitle: "Esegui script di manutenzione come Restic e Rclone direttamente dall'interfaccia web",
        tools_restic_title: "Backup Restic (restic-tools.sh)",
        tools_restic_desc: "Gestisci i backup crittografati del tuo mondo e dei dati del server.",
        tools_btn_doctor: "🏥 Doctor (Controlla Repo)",
        tools_btn_unlock: "🔓 Sblocca Repo",
        tools_btn_backup_offline: "💾 Backup Offline",
        tools_mutex_title: "Cloud Mutex (rclone-mutex.sh)",
        tools_mutex_desc: "Gestisci il blocco cloud per evitare che più server partano contemporaneamente.",
        tools_btn_mutex_get: "🔍 Stato Mutex",
        tools_btn_mutex_lock: "🔴 Blocca (Set 1)",
        tools_btn_mutex_unlock: "🟢 Sblocca (Set 0)",
        tools_utils_title: "Altre Utilità",
        tools_utils_desc: "Script utili per la manutenzione generale.",
        tools_btn_disable_mods: "🚫 Disabilita Mod Client",
        tools_btn_cloud_sync: "☁️ Sincronizzazione Cloud (pull)",

        // General messages
        toast_config_loaded: "Configurazione caricata con successo!",
        toast_config_saved: "Configurazione salvata con successo in env/.env e env/server_ips.env!",
        toast_copied: "Copiato negli appunti!",
    }
};

let currentLang = 'en';

function setCookie(name, value, days) {
    let expires = "";
    if (days) {
        const date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + (value || "") + expires + "; path=/; SameSite=Lax";
}

function getCookie(name) {
    const nameEQ = name + "=";
    const ca = document.cookie.split(';');
    for (let i = 0; i < ca.length; i++) {
        let c = ca[i];
        while (c.charAt(0) == ' ') c = c.substring(1, c.length);
        if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length, c.length);
    }
    return null;
}

function getLanguage() {
    try {
        let saved = getCookie('preferred_language');
        if (!saved) {
            saved = localStorage.getItem('preferred_language');
            if (saved) setCookie('preferred_language', saved, 365);
        }
        if (saved && (saved === 'en' || saved === 'it')) {
            return saved;
        }
    } catch (e) { }
    return 'en';
}

function setLanguage(lang) {
    if (lang !== 'en' && lang !== 'it') {
        lang = 'en';
    }
    currentLang = lang;

    try {
        setCookie('preferred_language', lang, 365);
        localStorage.setItem('preferred_language', lang);
    } catch (e) { }

    document.documentElement.lang = lang;

    // Update button display
    const flagEl = document.getElementById('lang-flag');
    const codeEl = document.getElementById('lang-code');
    const btnEl = document.getElementById('lang-dropdown-btn') || document.getElementById('lang-toggle-btn');

    if (flagEl) flagEl.textContent = lang === 'en' ? '🇬🇧' : '🇮🇹';
    if (codeEl) codeEl.textContent = lang === 'en' ? 'ENG' : 'ITA';
    if (btnEl) {
        btnEl.title = lang === 'en' ? 'Select Language (ENG)' : 'Seleziona Lingua (ITA)';
        btnEl.setAttribute('aria-label', lang === 'en' ? 'Select Language' : 'Seleziona Lingua');
    }

    // Update active class on dropdown options
    document.querySelectorAll('.lang-option').forEach(opt => {
        const optLang = opt.getAttribute('data-lang');
        if (optLang === lang) {
            opt.classList.add('active');
        } else {
            opt.classList.remove('active');
        }
    });

    // Apply translations to all DOM elements with data-i18n
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        const translated = t(key);
        if (translated) {
            el.innerHTML = translated;
        }
    });

    // Apply translations to placeholders
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        const translated = t(key);
        if (translated) {
            el.placeholder = translated;
        }
    });

    // Apply translations to titles
    document.querySelectorAll('[data-i18n-title]').forEach(el => {
        const key = el.getAttribute('data-i18n-title');
        const translated = t(key);
        if (translated) {
            el.title = translated;
        }
    });

    // Dispatch global event for other scripts
    document.dispatchEvent(new CustomEvent('languageChanged', { detail: { language: lang } }));
}

function toggleLangDropdown(event) {
    if (event) {
        event.stopPropagation();
    }
    const wrapper = document.getElementById('lang-dropdown-wrapper');
    const btn = document.getElementById('lang-dropdown-btn');
    if (!wrapper) return;

    const isOpen = wrapper.classList.toggle('open');
    if (btn) {
        btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    }
}

function closeLangDropdown() {
    const wrapper = document.getElementById('lang-dropdown-wrapper');
    const btn = document.getElementById('lang-dropdown-btn');
    if (wrapper) {
        wrapper.classList.remove('open');
    }
    if (btn) {
        btn.setAttribute('aria-expanded', 'false');
    }
}

function selectLanguage(lang) {
    setLanguage(lang);
    closeLangDropdown();
}

function toggleLanguage() {
    const nextLang = currentLang === 'en' ? 'it' : 'en';
    setLanguage(nextLang);
}

function t(key, fallback = '') {
    const dict = I18N_TRANSLATIONS[currentLang] || I18N_TRANSLATIONS['en'];
    if (dict && dict[key] !== undefined) {
        return dict[key];
    }
    const defaultDict = I18N_TRANSLATIONS['en'];
    if (defaultDict && defaultDict[key] !== undefined) {
        return defaultDict[key];
    }
    return fallback || key;
}

// Auto-initialize on page load and register click outside listener
document.addEventListener('DOMContentLoaded', () => {
    const initialLang = getLanguage();
    setLanguage(initialLang);

    document.addEventListener('click', (e) => {
        const wrapper = document.getElementById('lang-dropdown-wrapper');
        if (wrapper && !wrapper.contains(e.target)) {
            closeLangDropdown();
        }
    });
});
