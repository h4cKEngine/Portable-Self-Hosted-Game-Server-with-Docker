// State
let currentConfig = {};
let availableRemotes = [];
let currentDDNSProvider = 'duckdns';

const MINECRAFT_COLORS = {
    '§0': '#000000',
    '§1': '#0000aa',
    '§2': '#00aa00',
    '§3': '#00aaaa',
    '§4': '#aa0000',
    '§5': '#aa00aa',
    '§6': '#ffaa00',
    '§7': '#aaaaaa',
    '§8': '#555555',
    '§9': '#5555ff',
    '§a': '#55ff55',
    '§b': '#55ffff',
    '§c': '#ff5555',
    '§d': '#ff55ff',
    '§e': '#ffff55',
    '§f': '#ffffff',
};

const DDNS_HINTS = {
    en: {
        'duckdns': 'DuckDNS: Domain is usually "name.duckdns.org". Token is your DuckDNS Token.',
        'desec': 'DeSEC.io: Domain is your desec domain. Token is your API token.',
        'dynu': 'Dynu: Domain is your dynu domain. Token is your API Password/Hash.',
        'ydns': 'YDNS: Domain is your ydns domain. Token is "username:password" or API key.',
        'afraid': 'FreeDNS (afraid.org): Domain is chosen domain. Token is your Direct URL hash.',
        'noip': 'No-IP: Domain is your no-ip domain. Token is "username:password" or auth token.',
        '': 'DDNS is disabled. The server will rely only on direct IP addresses.',
    },
    it: {
        'duckdns': 'DuckDNS: Il dominio è solitamente "nome.duckdns.org". Il token si trova su duckdns.org.',
        'desec': 'DeSEC.io: Il dominio è il tuo dominio desec. Il token è la tua API token.',
        'dynu': 'Dynu: Il dominio è il tuo dominio dynu. Il token è la password API.',
        'ydns': 'YDNS: Il dominio è il tuo dominio ydns. Il token è "username:password" o API key.',
        'afraid': 'FreeDNS (afraid.org): Il dominio è il dominio scelto. Il token è l\'hash Direct URL.',
        'noip': 'No-IP: Il dominio è il tuo dominio no-ip. Il token è "username:password" o token auth.',
        '': 'DDNS disabilitato. Il server utilizzerà esclusivamente gli indirizzi IP diretti.',
    }
};

// ─── Initialization ──────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
    initEventListeners();
    fetchConfig();
    loadInstalledModpacks();
    loadAvailableModpacks();

    try {
        const savedTab = localStorage.getItem('active_config_tab');
        if (savedTab && document.getElementById(savedTab)) {
            switchConfigTab(savedTab);
        }
    } catch (e) { }
});

// ─── Tab Switching ─────────────────────────────────────────────────────────

function switchConfigTab(tabId) {
    const validTabs = ['tab-server', 'tab-modpacks', 'tab-cloud', 'tab-advanced'];
    if (!validTabs.includes(tabId)) {
        tabId = 'tab-server';
    }

    document.querySelectorAll('.config-tabs-nav .tab-btn').forEach(btn => {
        const isMatch = btn.getAttribute('data-tab') === tabId;
        btn.classList.toggle('active', isMatch);
    });

    document.querySelectorAll('.tab-pane').forEach(pane => {
        const isMatch = pane.id === tabId;
        pane.classList.toggle('active', isMatch);
        pane.style.display = isMatch ? 'flex' : 'none';
    });

    try {
        localStorage.setItem('active_config_tab', tabId);
    } catch (e) { }
}

function initEventListeners() {
    // CurseForge Enter key
    const cfInput = document.getElementById('input-cf-url');
    if (cfInput) {
        cfInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                inspectCurseForgeModpack();
            }
        });
    }

    // Name slugification & live previews
    const nameInput = document.getElementById('input-name');
    nameInput.addEventListener('input', () => {
        updateDerivedPreviews();
    });

    // Version input
    const versionInput = document.getElementById('input-version');
    versionInput.addEventListener('input', () => {
        updateDerivedPreviews();
    });

    // MOTD input
    const motdInput = document.getElementById('input-motd');
    motdInput.addEventListener('input', () => {
        renderMotdPreview(motdInput.value);
    });

    // Color tags click
    document.querySelectorAll('.color-tag').forEach(tag => {
        tag.addEventListener('click', () => {
            const code = tag.getAttribute('data-code');
            insertAtCursor(motdInput, code);
            renderMotdPreview(motdInput.value);
        });
    });

    // Type buttons
    document.querySelectorAll('.type-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const type = btn.getAttribute('data-type');
            selectServerType(type);
        });
    });

    // Range slider sync
    syncSliderAndNumber('slider-view-distance', 'input-view-distance');
    syncSliderAndNumber('slider-sim-distance', 'input-sim-distance');

    // Rclone service live update
    const rcloneInput = document.getElementById('input-rclone-service');
    rcloneInput.addEventListener('input', () => {
        updateDerivedPreviews();
    });

    // DDNS provider input
    const ddnsInput = document.getElementById('input-ddns-provider');
    ddnsInput.addEventListener('input', () => {
        updateDDNSPluginPreview(ddnsInput.value);
    });

    // Online mode toggle
    const onlineModeToggle = document.getElementById('input-online-mode');
    onlineModeToggle.addEventListener('change', () => {
        const hint = document.getElementById('online-mode-hint');
        hint.textContent = onlineModeToggle.checked ?
            'ON (Enforces Mojang official account validation)' :
            'OFF (Allows offline & direct connects)';
    });
}

function syncSliderAndNumber(sliderId, numberId) {
    const slider = document.getElementById(sliderId);
    const num = document.getElementById(numberId);
    if (!slider || !num) return;

    slider.addEventListener('input', () => {
        num.value = slider.value;
    });
    num.addEventListener('input', () => {
        slider.value = num.value;
    });
}

function insertAtCursor(input, text) {
    const start = input.selectionStart || 0;
    const end = input.selectionEnd || 0;
    const val = input.value;
    input.value = val.substring(0, start) + text + val.substring(end);
    input.focus();
    input.setSelectionRange(start + text.length, start + text.length);
}

// ─── API Fetch & Populate ────────────────────────────────────────────────────

async function fetchConfig() {
    const statusPill = document.getElementById('status-pill');
    try {
        const res = await fetch('/api/config');
        if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
        const data = await res.json();

        currentConfig = data.config || {};
        availableRemotes = data.available_remotes || [];

        populateForm(currentConfig);
        populateRemotes(availableRemotes, data.remotes_info || []);

        statusPill.replaceChildren();
        if (data.has_custom_env) {
            statusPill.className = 'status-pill success';
            statusPill.textContent = '✅ Loaded active .env';
        } else {
            statusPill.className = 'status-pill warning';
            statusPill.textContent = '⚠️ Using .env-example defaults';
        }

        const worldZipInput = document.getElementById('input-world-zip');
        const worldUploadBtn = document.getElementById('btn-world-upload');
        const worldUploadSection = document.getElementById('world-upload-section');
        const worldUploadStatus = document.getElementById('world-upload-status-text');
        
        if (worldZipInput && worldUploadBtn && worldUploadSection) {
            if (data.is_pack_loaded) {
                worldZipInput.disabled = false;
                worldUploadBtn.disabled = false;
                worldUploadSection.style.opacity = '1';
                worldUploadStatus.style.display = 'none';
            } else {
                worldZipInput.disabled = true;
                worldUploadBtn.disabled = true;
                worldUploadSection.style.opacity = '0.5';
                worldUploadStatus.style.display = 'inline-block';
            }
        }

        const envPathBadge = document.getElementById('env-path-display');
        envPathBadge.textContent = data.env_path || 'env/.env';
    } catch (e) {
        console.error('Failed to load config:', e);
        statusPill.className = 'status-pill warning';
        statusPill.textContent = '❌ Could not load config';
        showToast('Could not load configuration from server.', 'error');
    }
}

function toggleAdvancedSettings() {
    const content = document.getElementById('advanced-settings-content');
    const btn = document.querySelector('.accordion-toggle');
    const isHidden = content.style.display === 'none';
    content.style.display = isHidden ? 'block' : 'none';
    if (btn) {
        btn.classList.toggle('active', isHidden);
    }
}

function populateForm(cfg) {
    // 1. Server & Modpack
    document.getElementById('input-name').value = cfg.name || 'minecraft-server';
    document.getElementById('input-version').value = cfg.version || '1.21.1';

    // Server IPs (from server_ips.env)
    const normEl = document.getElementById('input-ip-normal');
    const v1El = document.getElementById('input-ip-vpn1');
    const v2El = document.getElementById('input-ip-vpn2');
    if (normEl) normEl.value = cfg.ip_server || '127.0.0.1';
    if (v1El) v1El.value = cfg.ip_vpn1 || '';
    if (v2El) v2El.value = cfg.ip_vpn2 || '';

    selectServerType(cfg.server_type || 'FORGE');

    document.getElementById('input-forge-version').value = cfg.forge_version || '';
    document.getElementById('input-neoforge-version').value = cfg.neoforge_version || '';
    document.getElementById('input-fabric-launcher').value = cfg.fabric_launcher_version || '';
    document.getElementById('input-fabric-loader').value = cfg.fabric_loader_version || '';

    // 2. Performance
    document.getElementById('input-init-memory').value = cfg.init_memory || '2G';
    document.getElementById('input-max-memory').value = cfg.memory || '6G';

    const viewDist = cfg.view_distance || 10;
    const sliderView = document.getElementById('slider-view-distance');
    const inputView = document.getElementById('input-view-distance');
    if (sliderView) sliderView.value = viewDist;
    if (inputView) inputView.value = viewDist;

    const simDist = cfg.simulation_distance || 5;
    const sliderSim = document.getElementById('slider-sim-distance');
    const inputSim = document.getElementById('input-sim-distance');
    if (sliderSim) sliderSim.value = simDist;
    if (inputSim) inputSim.value = simDist;

    // 3. Properties & MOTD
    document.getElementById('input-motd').value = cfg.motd || '';
    renderMotdPreview(cfg.motd || '');

    document.getElementById('input-max-players').value = cfg.max_players || 8;
    document.getElementById('input-seed').value = cfg.seed || '';
    document.getElementById('input-ops').value = cfg.operators || '';
    document.getElementById('input-rcon-password').value = cfg.rcon_password || 'minecraft';

    const onlineCheck = document.getElementById('input-online-mode');
    if (onlineCheck) {
        onlineCheck.checked = (cfg.online_mode || '').toUpperCase() === 'TRUE';
        onlineCheck.dispatchEvent(new Event('change'));
    }

    // 4. Cloud & Rclone
    document.getElementById('input-rclone-service').value = cfg.rclone_service || 'mega';
    document.getElementById('input-rclone-config').value = cfg.rclone_config || '/etc/rclone/rclone.conf';
    document.getElementById('input-rclone-host').value = cfg.rclone_conf_host || './env/rclone.conf';

    // 5. DDNS
    const ddnsProv = cfg.ddns_provider !== undefined ? cfg.ddns_provider : 'duckdns';
    selectDDNSProvider(ddnsProv);
    document.getElementById('input-ddns-domain').value = cfg.ddns_domain || '';
    document.getElementById('input-ddns-token').value = cfg.ddns_token || '';
    if (document.getElementById('input-ddns-skip')) {
        document.getElementById('input-ddns-skip').checked = cfg.ddns_skip === true;
    }
    if (document.getElementById('input-rclone-skip')) {
        document.getElementById('input-rclone-skip').checked = cfg.rclone_skip === true;
    }

    // 6. Restic
    document.getElementById('input-restic-hostname').value = cfg.restic_hostname || 'MinecraftServer';
    document.getElementById('input-restic-password').value = cfg.restic_password || 'minecraft';
    document.getElementById('input-restic-keep').value = cfg.restic_keep_last || 10;
    document.getElementById('input-restic-image').value = cfg.restic_image || 'docker.io/tofran/restic-rclone:0.17.0_1.68.2';

    // 7. AutoStop / Pause
    const pauseEmpty = document.getElementById('input-pause-empty');
    if (pauseEmpty) pauseEmpty.value = cfg.pause_when_empty_seconds !== undefined ? cfg.pause_when_empty_seconds : 300;

    const autoStop = document.getElementById('input-enable-autostop');
    if (autoStop) autoStop.checked = (cfg.enable_autostop || '').toUpperCase() === 'TRUE';

    const autoPause = document.getElementById('input-enable-autopause');
    if (autoPause) autoPause.checked = (cfg.enable_autopause || '').toUpperCase() === 'TRUE';

    updateDerivedPreviews();
}

function populateRemotes(remotes, remotesInfo = []) {
    const sel = document.getElementById('select-detected-remotes');
    sel.replaceChildren();

    const defOpt = document.createElement('option');
    defOpt.value = '';
    defOpt.textContent = remotes.length ? 'Detected Remotes in rclone.conf...' : '(No remotes found in rclone.conf)';
    sel.appendChild(defOpt);

    remotes.forEach(remote => {
        const opt = document.createElement('option');
        opt.value = remote;
        opt.textContent = `📁 ${remote}`;
        sel.appendChild(opt);
    });

    renderRemotesList(remotesInfo);
}

function renderRemotesList(remotesInfo) {
    const container = document.getElementById('remotes-list-container');
    container.replaceChildren();

    if (!remotesInfo || !remotesInfo.length) {
        const emptyMsg = document.createElement('div');
        emptyMsg.className = 'form-hint';
        emptyMsg.textContent = 'No remotes configured yet. Click "+ Add Remote" to add a cloud storage account (e.g. MEGA).';
        container.appendChild(emptyMsg);
        return;
    }

    remotesInfo.forEach(rem => {
        const item = document.createElement('div');
        item.className = 'remote-item';

        const left = document.createElement('div');
        left.className = 'remote-item-left';

        const nameSpan = document.createElement('span');
        nameSpan.className = 'remote-name';
        nameSpan.textContent = `[${rem.name}]`;

        const typeBadge = document.createElement('span');
        typeBadge.className = 'remote-type-badge';
        typeBadge.textContent = rem.type;

        left.appendChild(nameSpan);
        left.appendChild(typeBadge);

        if (rem.user) {
            const userSpan = document.createElement('span');
            userSpan.className = 'remote-user';
            userSpan.textContent = `(${rem.user})`;
            left.appendChild(userSpan);
        }

        const actions = document.createElement('div');
        actions.className = 'remote-actions';

        const selectBtn = document.createElement('button');
        selectBtn.type = 'button';
        selectBtn.className = 'btn btn-secondary btn-sm';
        selectBtn.textContent = 'Use as Active';
        selectBtn.onclick = () => {
            document.getElementById('input-rclone-service').value = rem.name;
            updateDerivedPreviews();
            showToast(`Selected [${rem.name}] as active remote`, 'info');
        };

        const testBtn = document.createElement('button');
        testBtn.type = 'button';
        testBtn.className = 'btn btn-secondary btn-sm';
        testBtn.textContent = '🧪 Test';
        testBtn.onclick = () => testRemoteConnection(rem.name, testBtn);

        const delBtn = document.createElement('button');
        delBtn.type = 'button';
        delBtn.className = 'btn btn-secondary btn-sm';
        delBtn.textContent = '🗑️';
        delBtn.title = 'Delete remote';
        delBtn.onclick = () => deleteRemote(rem.name);

        actions.appendChild(selectBtn);
        actions.appendChild(testBtn);
        actions.appendChild(delBtn);

        item.appendChild(left);
        item.appendChild(actions);
        container.appendChild(item);
    });
}

async function refreshRcloneRemotes() {
    try {
        const res = await fetch('/api/rclone/remotes');
        if (!res.ok) return;
        const data = await res.json();
        availableRemotes = data.remotes || [];
        populateRemotes(availableRemotes, data.remotes_info || []);
    } catch (e) {
        console.error('Error fetching remotes:', e);
    }
}

function applyDetectedRemote(remoteName) {
    if (!remoteName) return;
    document.getElementById('input-rclone-service').value = remoteName;
    updateDerivedPreviews();
}

// ─── Rclone Modals & Actions ────────────────────────────────────────────────

function openAddRemoteModal() {
    document.getElementById('remote-input-name').value = '';
    document.getElementById('remote-input-user').value = '';
    document.getElementById('remote-input-pass').value = '';
    document.getElementById('add-remote-modal').style.display = 'flex';
}

function closeAddRemoteModal() {
    document.getElementById('add-remote-modal').style.display = 'none';
}

async function saveRcloneRemote() {
    const name = document.getElementById('remote-input-name').value.trim();
    const serviceType = document.getElementById('remote-select-type').value;
    const user = document.getElementById('remote-input-user').value.trim();
    const password = document.getElementById('remote-input-pass').value;

    if (!name) {
        showToast('Remote name is required', 'error');
        return;
    }
    if (!user || !password) {
        showToast('Username/Email and Password are required', 'error');
        return;
    }

    const btn = document.getElementById('btn-save-remote');
    btn.disabled = true;
    btn.textContent = '⏳ Saving...';

    try {
        const res = await fetch('/api/rclone/remote', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                name: name,
                service_type: serviceType,
                user: user,
                password: password
            })
        });

        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Failed to save remote');

        closeAddRemoteModal();
        showToast(data.message || `Configured remote [${name}]`, 'success');
        document.getElementById('input-rclone-service').value = name;
        updateDerivedPreviews();
        await refreshRcloneRemotes();
    } catch (e) {
        showToast(`Save error: ${e.message}`, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = '💾 Save Remote';
    }
}

async function testRemoteConnection(remoteName, btn) {
    const orig = btn.textContent;
    btn.disabled = true;
    btn.textContent = '⏳ Testing...';

    try {
        const res = await fetch('/api/rclone/test', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ remote_name: remoteName })
        });
        const data = await res.json();
        if (data.connected) {
            showToast(`✅ [${remoteName}] connection successful!`, 'success');
        } else {
            showToast(`⚠️ [${remoteName}]: ${data.message}`, 'error');
        }
    } catch (e) {
        showToast(`Test error: ${e.message}`, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = orig;
    }
}

async function deleteRemote(remoteName) {
    if (!confirm(`Are you sure you want to delete remote [${remoteName}] from rclone.conf?`)) {
        return;
    }

    try {
        const res = await fetch(`/api/rclone/remote/${encodeURIComponent(remoteName)}`, {
            method: 'DELETE'
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Delete failed');

        showToast(`Remote [${remoteName}] removed`, 'success');
        await refreshRcloneRemotes();
    } catch (e) {
        showToast(`Delete error: ${e.message}`, 'error');
    }
}

async function openRawRcloneModal() {
    const textarea = document.getElementById('raw-rclone-textarea');
    textarea.value = 'Loading env/rclone.conf...';
    document.getElementById('raw-rclone-modal').style.display = 'flex';

    try {
        const res = await fetch('/api/rclone/raw');
        const data = await res.json();
        textarea.value = data.content || '';
    } catch (e) {
        textarea.value = `Error loading rclone.conf: ${e.message}`;
    }
}

function closeRawRcloneModal() {
    document.getElementById('raw-rclone-modal').style.display = 'none';
}

async function saveRawRcloneConf() {
    const content = document.getElementById('raw-rclone-textarea').value;
    const btn = document.getElementById('btn-save-raw-rclone');
    btn.disabled = true;
    btn.textContent = '⏳ Saving...';

    try {
        const res = await fetch('/api/rclone/raw', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ content: content })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Save failed');

        closeRawRcloneModal();
        showToast('rclone.conf successfully saved!', 'success');
        await refreshRcloneRemotes();
    } catch (e) {
        showToast(`Save failed: ${e.message}`, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = '💾 Save rclone.conf';
    }
}

// ─── Type & Provider Selectors ───────────────────────────────────────────────

function selectServerType(type) {
    type = type ? type.toUpperCase() : 'FORGE';
    document.getElementById('input-type').value = type;

    document.querySelectorAll('.type-btn').forEach(btn => {
        if (btn.getAttribute('data-type') === type) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });

    // Toggle conditional boxes
    document.getElementById('engine-forge-box').style.display = (type === 'FORGE') ? 'block' : 'none';
    document.getElementById('engine-neoforge-box').style.display = (type === 'NEOFORGE') ? 'block' : 'none';
    document.getElementById('engine-fabric-box').style.display = (type === 'FABRIC') ? 'block' : 'none';

    updateDerivedPreviews();
}

function selectDDNSProvider(provider) {
    currentDDNSProvider = provider ? provider.toLowerCase() : '';
    const provInput = document.getElementById('input-ddns-provider');
    provInput.value = currentDDNSProvider;

    document.querySelectorAll('.provider-card').forEach(card => {
        const p = card.getAttribute('data-provider');
        if (p === currentDDNSProvider) {
            card.classList.add('active');
        } else {
            card.classList.remove('active');
        }
    });

    const hintText = document.getElementById('ddns-hint-text');
    const lang = (typeof currentLang !== 'undefined' && currentLang === 'it') ? 'it' : 'en';
    const dict = DDNS_HINTS[lang] || DDNS_HINTS.en;
    const firstPart = currentDDNSProvider.split('.')[0];
    if (hintText) {
        hintText.textContent = dict[firstPart] || dict[''] || (lang === 'it' ? 'Inserisci dominio e token del provider.' : 'Enter provider domain and authentication token.');
    }

    updateDDNSPluginPreview(currentDDNSProvider);
}

document.addEventListener('languageChanged', () => {
    selectDDNSProvider(currentDDNSProvider);
});

function formatFullDomain(domain, provider) {
    if (!domain || !domain.trim()) return '';
    const d = domain.trim();
    if (d.includes('.')) return d;
    const p = (provider || 'duckdns').toLowerCase().trim();
    if (p === 'duckdns' || p === 'duckdns.org') {
        return `${d}.duckdns.org`;
    }
    if (p === 'desec' || p === 'desec.io') {
        return `${d}.dedyn.io`;
    }
    return d;
}

function updateDDNSPluginPreview(provider) {
    const pluginPreview = document.getElementById('preview-ddns-plugin');
    if (!provider) {
        pluginPreview.textContent = '(none)';
        return;
    }
    const norm = provider.trim().toLowerCase();
    const firstPart = norm.split('.')[0];
    const mapping = {
        'duckdns': 'duckdns',
        'desec': 'desec',
        'dynu': 'dynu',
        'ydns': 'ydns',
        'afraid': 'freedns',
        'freedns': 'freedns',
        'noip': 'noip'
    };
    pluginPreview.textContent = mapping[firstPart] || firstPart;
}

// ─── Preset Helpers ──────────────────────────────────────────────────────────

function setInitMemory(val) {
    document.getElementById('input-init-memory').value = val;
}

function setMaxMemory(val) {
    document.getElementById('input-max-memory').value = val;
}

function togglePasswordVisibility(inputId, btn) {
    const input = document.getElementById(inputId);
    if (!input) return;
    if (input.type === 'password') {
        input.type = 'text';
        btn.textContent = '🔒';
    } else {
        input.type = 'password';
        btn.textContent = '👁️';
    }
}

// ─── Real-time Derived Previews & MOTD ───────────────────────────────────────

function slugify(text) {
    if (!text) return 'minecraft-server';
    const cleaned = text.toLowerCase().replace(/[^a-z0-9_-]/g, '').replace(/^[-_]+|[-_]+$/g, '');
    return cleaned || 'minecraft-server';
}

function updateDerivedPreviews() {
    const rawName = document.getElementById('input-name').value;
    const cleanName = slugify(rawName);

    // Update slug preview
    const slugEl = document.getElementById('preview-slug');
    if (slugEl) slugEl.textContent = cleanName;

    // Mutex path
    const rcloneService = document.getElementById('input-rclone-service').value.trim() || 'mega';
    const mutexPath = `${rcloneService}:/${cleanName}`;
    const mutexEl = document.getElementById('preview-mutex-path');
    if (mutexEl) mutexEl.textContent = mutexPath;

    // Restic Repo & Tag
    const resticRepoEl = document.getElementById('preview-restic-repo');
    const resticTagEl = document.getElementById('preview-restic-tag');
    if (resticRepoEl) resticRepoEl.textContent = `rclone:${rcloneService}:/${cleanName}`;
    if (resticTagEl) resticTagEl.textContent = `${cleanName}_backups`;

    // Refresh MOTD preview if custom motd is empty
    const motdVal = document.getElementById('input-motd').value;
    renderMotdPreview(motdVal);
}

function renderMotdPreview(motd) {
    const box = document.getElementById('motd-render-box');
    box.replaceChildren();

    const rawName = document.getElementById('input-name').value;
    const cleanName = slugify(rawName);
    const sType = document.getElementById('input-type').value || 'FORGE';
    const sVer = document.getElementById('input-version').value || '1.21.1';

    let textToRender = motd && motd.trim() ? motd : `§6${cleanName} §7| §b${sType} ${sVer}`;

    // Parse Minecraft formatting codes safely via DOM nodes
    const segments = parseMinecraftText(textToRender);
    segments.forEach(seg => {
        const span = document.createElement('span');
        span.textContent = seg.text;
        if (seg.color) span.style.color = seg.color;
        if (seg.bold) span.style.fontWeight = 'bold';
        if (seg.italic) span.style.fontStyle = 'italic';
        if (seg.underline) span.style.textDecoration = 'underline';
        box.appendChild(span);
    });
}

function parseMinecraftText(input) {
    const segments = [];
    let currentColor = '#ffffff';
    let isBold = false;
    let isItalic = false;
    let isUnderline = false;

    let buffer = '';

    for (let i = 0; i < input.length; i++) {
        if (input[i] === '§' && i + 1 < input.length) {
            if (buffer.length > 0) {
                segments.push({
                    text: buffer,
                    color: currentColor,
                    bold: isBold,
                    italic: isItalic,
                    underline: isUnderline
                });
                buffer = '';
            }

            const code = '§' + input[i + 1].toLowerCase();
            if (MINECRAFT_COLORS[code]) {
                currentColor = MINECRAFT_COLORS[code];
                isBold = false;
                isItalic = false;
                isUnderline = false;
            } else if (code === '§l') {
                isBold = true;
            } else if (code === '§o') {
                isItalic = true;
            } else if (code === '§n') {
                isUnderline = true;
            } else if (code === '§r') {
                currentColor = '#ffffff';
                isBold = false;
                isItalic = false;
                isUnderline = false;
            }
            i++; // skip code char
        } else {
            buffer += input[i];
        }
    }

    if (buffer.length > 0) {
        segments.push({
            text: buffer,
            color: currentColor,
            bold: isBold,
            italic: isItalic,
            underline: isUnderline
        });
    }

    return segments;
}

// ─── Payload Gathering & Validation ──────────────────────────────────────────

function gatherPayload() {
    const rawName = document.getElementById('input-name').value;
    const name = slugify(rawName);

    const ipNormal = (document.getElementById('input-ip-normal')?.value || '127.0.0.1').trim() || '127.0.0.1';
    const ipVpn1 = (document.getElementById('input-ip-vpn1')?.value || '').trim();
    const ipVpn2 = (document.getElementById('input-ip-vpn2')?.value || '').trim();

    return {
        name: name,
        version: document.getElementById('input-version').value.trim() || '1.21.1',
        server_type: document.getElementById('input-type').value || 'FORGE',
        ip_server: ipNormal,
        ip_vpn1: ipVpn1,
        ip_vpn2: ipVpn2,
        forge_version: document.getElementById('input-forge-version')?.value.trim() || '',
        neoforge_version: document.getElementById('input-neoforge-version')?.value.trim() || '',
        fabric_launcher_version: document.getElementById('input-fabric-launcher')?.value.trim() || '',
        fabric_loader_version: document.getElementById('input-fabric-loader')?.value.trim() || '',
        init_memory: document.getElementById('input-init-memory')?.value.trim().toUpperCase() || '2G',
        memory: document.getElementById('input-max-memory')?.value.trim().toUpperCase() || '6G',
        max_players: parseInt(document.getElementById('input-max-players')?.value, 10) || 8,
        motd: document.getElementById('input-motd')?.value.trim() || '',
        seed: document.getElementById('input-seed')?.value.trim() || '',
        operators: document.getElementById('input-ops')?.value.trim() || '',
        view_distance: parseInt(document.getElementById('input-view-distance')?.value, 10) || 10,
        simulation_distance: parseInt(document.getElementById('input-sim-distance')?.value, 10) || 5,
        eula: 'TRUE',
        online_mode: document.getElementById('input-online-mode')?.checked ? 'TRUE' : 'FALSE',
        rclone_service: document.getElementById('input-rclone-service')?.value.trim() || 'mega',
        rclone_config: document.getElementById('input-rclone-config')?.value.trim() || '/etc/rclone/rclone.conf',
        rclone_conf_host: document.getElementById('input-rclone-host')?.value.trim() || './env/rclone.conf',
        rclone_skip: document.getElementById('input-rclone-skip')?.checked || false,
        ddns_provider: document.getElementById('input-ddns-provider')?.value.trim() || '',
        ddns_domain: document.getElementById('input-ddns-domain')?.value.trim() || '',
        ddns_token: document.getElementById('input-ddns-token')?.value.trim() || '',
        ddns_skip: document.getElementById('input-ddns-skip')?.checked || false,
        restic_hostname: document.getElementById('input-restic-hostname')?.value.trim() || 'MinecraftServer',
        restic_password: document.getElementById('input-restic-password')?.value.trim() || 'minecraft',
        restic_keep_last: parseInt(document.getElementById('input-restic-keep')?.value, 10) || 10,
        restic_image: document.getElementById('input-restic-image')?.value.trim() || 'docker.io/tofran/restic-rclone:0.17.0_1.68.2',
        rcon_password: document.getElementById('input-rcon-password')?.value.trim() || 'minecraft',
        backup_enabled: 'true',
        enable_autostop: document.getElementById('input-enable-autostop')?.checked ? 'TRUE' : '',
        autostop_timeout_est: 3600,
        autostop_timeout_init: 1800,
        enable_autopause: document.getElementById('input-enable-autopause')?.checked ? 'TRUE' : '',
        max_tick_time: -1,
        pause_when_empty_seconds: parseInt(document.getElementById('input-pause-empty')?.value, 10) || 300,
    };
}

// ─── Modal & Actions ─────────────────────────────────────────────────────────

function openConfirmModal() {
    const payload = gatherPayload();
    const list = document.getElementById('confirm-summary-list');
    list.replaceChildren();

    const isEn = (typeof currentLang !== 'undefined' ? currentLang === 'en' : true);
    const summaryItems = [
        { label: isEn ? 'Container / Modpack Name' : 'Nome Container / Modpack', val: payload.name },
        { label: isEn ? 'Minecraft Engine & Version' : 'Motore & Versione Minecraft', val: `${payload.server_type} ${payload.version}` },
        { label: isEn ? 'Standard IP (server_ips.env)' : 'IP Normale (server_ips.env)', val: payload.ip_server },
        { label: isEn ? 'VPN 1 IP (server_ips.env)' : 'IP VPN 1 (server_ips.env)', val: payload.ip_vpn1 || (isEn ? '(none)' : '(nessuno)') },
        { label: isEn ? 'VPN 2 IP (server_ips.env)' : 'IP VPN 2 (server_ips.env)', val: payload.ip_vpn2 || (isEn ? '(none)' : '(nessuno)') },
        { label: isEn ? 'Rclone Remote' : 'Remoto Rclone', val: payload.rclone_service },
        { label: isEn ? 'DDNS Domain' : 'Dominio DDNS', val: payload.ddns_domain ? formatFullDomain(payload.ddns_domain, payload.ddns_provider) : (isEn ? '(disabled)' : '(disabilitato)') },
        { label: isEn ? 'Allocated RAM' : 'RAM Allocata', val: `${payload.init_memory} - ${payload.memory}` },
    ];

    summaryItems.forEach(item => {
        const row = document.createElement('div');
        row.className = 'summary-item';

        const k = document.createElement('span');
        k.className = 'summary-item-key';
        k.textContent = item.label;

        const v = document.createElement('span');
        v.className = 'summary-item-val';
        v.textContent = item.val;

        row.appendChild(k);
        row.appendChild(v);
        list.appendChild(row);
    });

    document.getElementById('confirm-modal').style.display = 'flex';
}

function closeConfirmModal() {
    document.getElementById('confirm-modal').style.display = 'none';
}

async function executeSave() {
    const btn = document.getElementById('btn-modal-confirm-save');
    const prevText = btn.textContent;
    btn.disabled = true;
    btn.textContent = '⏳ Saving...';

    const payload = gatherPayload();

    try {
        // 1. Save .env
        const res = await fetch('/api/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        const data = await res.json();
        if (!res.ok) {
            throw new Error(data.detail || `Save failed with status ${res.status}`);
        }

        // 2. Save server_ips.env
        await fetch('/api/server-ips', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ip_server: payload.ip_server,
                ip_vpn1: payload.ip_vpn1,
                ip_vpn2: payload.ip_vpn2
            })
        });

        closeConfirmModal();
        showToast('Configurazione salvata con successo in env/.env e env/server_ips.env!', 'success');
        fetchConfig();
    } catch (e) {
        console.error('Save error:', e);
        showToast(`Save failed: ${e.message}`, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = prevText;
    }
}

async function openRawModal() {
    const payload = gatherPayload();
    const codeBlock = document.getElementById('raw-code-block');
    codeBlock.textContent = 'Loading generated .env preview...';

    document.getElementById('raw-modal').style.display = 'flex';

    try {
        const res = await fetch('/api/config/preview', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Preview generation failed');
        codeBlock.textContent = data.rendered_env || '';
    } catch (e) {
        codeBlock.textContent = `Error rendering preview: ${e.message}`;
    }
}

function closeRawModal() {
    document.getElementById('raw-modal').style.display = 'none';
}

function copyRawEnv() {
    const text = document.getElementById('raw-code-block').textContent;
    navigator.clipboard.writeText(text).then(() => {
        const btn = document.getElementById('btn-copy-raw');
        btn.textContent = '✅ Copied!';
        setTimeout(() => btn.textContent = '📋 Copy to Clipboard', 1800);
    });
}

async function downloadEnvFile() {
    const payload = gatherPayload();
    try {
        const res = await fetch('/api/config/preview', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        const content = data.rendered_env || '';

        const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = '.env';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        showToast('Downloaded .env file!', 'success');
    } catch (e) {
        showToast(`Download failed: ${e.message}`, 'error');
    }
}

function reloadConfig() {
    fetchConfig();
    showToast('Configuration reloaded from disk', 'success');
}

// ─── Toast Notifications ─────────────────────────────────────────────────────

function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    const icon = document.createElement('span');
    icon.textContent = type === 'success' ? '✅' : (type === 'error' ? '❌' : 'ℹ️');

    const msg = document.createElement('span');
    msg.textContent = message;

    toast.appendChild(icon);
    toast.appendChild(msg);
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(-10px)';
        toast.style.transition = 'all 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 3500);
}


// ─── CurseForge Modpack Management ──────────────────────────────────────────

let currentInspectedModpack = null;
let activeTaskInterval = null;

async function inspectCurseForgeModpack() {
    const input = document.getElementById('input-cf-url');
    const target = input ? input.value.trim() : '';
    if (!target) {
        showToast('Inserisci un URL o ID di un modpack CurseForge', 'warning');
        return;
    }

    const btn = document.getElementById('btn-cf-inspect');
    const prevText = btn.textContent;
    btn.disabled = true;
    btn.textContent = '⏳ Ricerca...';

    const previewContainer = document.getElementById('cf-preview-container');

    try {
        const urlOrId = input.value.trim();
        const provider = document.getElementById('select-cf-provider').value;
        const res = await fetch('/api/curseforge/info', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ url_or_id: urlOrId, provider: provider })
        });

        const data = await res.json();
        if (!res.ok || data.status !== 'success') {
            throw new Error(data.detail || 'Impossibile recuperare le informazioni del modpack');
        }

        currentInspectedModpack = data.modpack;
        renderModpackPreview(currentInspectedModpack);
        showToast(`Modpack trovato: ${currentInspectedModpack.name}`, 'success');
    } catch (err) {
        showToast(`Errore: ${err.message}`, 'error');
        if (previewContainer) previewContainer.style.display = 'none';
    } finally {
        btn.disabled = false;
        btn.textContent = prevText;
    }
}

function renderModpackPreview(modpack) {
    const container = document.getElementById('cf-preview-container');
    if (!container || !modpack) return;

    const logo = document.getElementById('cf-preview-logo');
    if (modpack.icon_url) {
        logo.src = modpack.icon_url;
        logo.style.display = 'block';
    } else {
        logo.src = '';
        logo.style.display = 'none';
    }

    document.getElementById('cf-preview-title').textContent = modpack.name || 'Modpack Sconosciuto';
    document.getElementById('cf-preview-summary').textContent = modpack.summary || 'Nessuna descrizione disponibile.';

    const loaderBadge = document.getElementById('cf-preview-loader');
    const loaderType = (modpack.server_type || 'FORGE').toUpperCase();
    loaderBadge.textContent = loaderType;
    loaderBadge.className = `badge badge-loader badge-${loaderType.toLowerCase()}`;

    document.getElementById('cf-preview-version').textContent = `MC ${modpack.mc_version || '1.20.1'}`;
    document.getElementById('cf-preview-filename').textContent = modpack.latest_file_name || '-';

    const downloads = modpack.download_count ? Number(modpack.download_count).toLocaleString() : '-';
    document.getElementById('cf-preview-downloads').textContent = downloads;

    const dateStr = modpack.file_date ? new Date(modpack.file_date).toLocaleDateString() : '-';
    document.getElementById('cf-preview-date').textContent = dateStr;

    container.style.display = 'block';
    container.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function applyPreviewToForm() {
    if (!currentInspectedModpack) {
        showToast('Nessun modpack ispezionato da applicare.', 'warning');
        return;
    }
    applyModpackToConfig(currentInspectedModpack);
}

function applyModpackToConfig(modpack) {
    if (!modpack) return;

    const cleanSlug = (modpack.slug || modpack.name || 'modpack').toLowerCase().replace(/[^a-z0-9_-]/g, '-');

    const nameInput = document.getElementById('input-name');
    if (nameInput) nameInput.value = cleanSlug;

    const verInput = document.getElementById('input-version');
    if (verInput && modpack.mc_version && modpack.mc_version !== "Unknown (Custom Pack)") {
        verInput.value = modpack.mc_version;
    }

    const sType = (modpack.server_type || 'FORGE').toUpperCase();
    if (sType !== 'CUSTOM') {
        selectServerType(sType);
    }

    if (sType === 'FORGE' && modpack.loader_version) {
        const fInput = document.getElementById('input-forge-version');
        if (fInput) fInput.value = modpack.loader_version;
    } else if (sType === 'NEOFORGE' && modpack.loader_version) {
        const neoInput = document.getElementById('input-neoforge-version');
        if (neoInput) neoInput.value = modpack.loader_version;
    } else if (sType === 'FABRIC' && modpack.loader_version) {
        const fabInput = document.getElementById('input-fabric-loader-version');
        if (fabInput) fabInput.value = modpack.loader_version;
    }

    const motdInput = document.getElementById('input-motd');
    if (motdInput) {
        const displayType = sType === 'CUSTOM' ? 'Custom' : sType;
        const displayVer = modpack.mc_version === "Unknown (Custom Pack)" ? '' : (modpack.mc_version || '');
        motdInput.value = `§6${modpack.name || cleanSlug} §7| §b${displayType} ${displayVer}`.trim();
        renderMotdPreview(motdInput.value);
    }

    updateDerivedPreviews();
    switchConfigTab('tab-server');
    
    let toastMessage = `Configurazione aggiornata per ${modpack.name || cleanSlug}!`;
    if (sType === 'CUSTOM') {
        toastMessage += ' Ricordati di impostare manualmente Versione ed Engine per questo pacchetto personalizzato.';
        showToast(toastMessage, 'warning');
    } else {
        showToast(toastMessage, 'success');
    }
}

async function startModpackDownload() {
    const input = document.getElementById('input-cf-url');
    const target = input ? input.value.trim() : '';
    if (!target) {
        showToast('Inserisci un URL o ID di un modpack CurseForge', 'warning');
        return;
    }

    const btnInstall = document.getElementById('btn-cf-install');
    btnInstall.disabled = true;
    btnInstall.textContent = '⏳ Avvio download...';

    const progressContainer = document.getElementById('cf-progress-container');
    if (progressContainer) progressContainer.style.display = 'block';

    clearConsoleLog();
    appendConsoleLog('[INFO] Invio richiesta di installazione all\'API...');

    try {
        const urlOrId = input.value.trim();
        const provider = document.getElementById('select-cf-provider').value;
        const res = await fetch('/api/curseforge/install', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ url_or_id: urlOrId, provider: provider })
        });

        const data = await res.json();
        if (!res.ok || data.status !== 'success') {
            throw new Error(data.detail || 'Impossibile avviare il task di installazione');
        }

        const taskId = data.task_id;
        appendConsoleLog(`[OK] Task registrato (ID: ${taskId}). Monitoraggio progresso...`);
        showToast('Download del modpack avviato in background!', 'info');

        pollCurseForgeTask(taskId);
    } catch (err) {
        appendConsoleLog(`[ERRORE] ${err.message}`);
        showToast(`Errore: ${err.message}`, 'error');
        btnInstall.disabled = false;
        btnInstall.textContent = '⬇️ Scarica & Installa in server_modpacks/';
    }
}

function pollCurseForgeTask(taskId) {
    if (activeTaskInterval) clearInterval(activeTaskInterval);

    const btnInstall = document.getElementById('btn-cf-install');
    const progressBar = document.getElementById('cf-progress-bar');
    const progressStep = document.getElementById('cf-progress-step');
    const progressPct = document.getElementById('cf-progress-pct');

    let lastLogIndex = 0;

    activeTaskInterval = setInterval(async () => {
        try {
            const res = await fetch(`/api/curseforge/tasks/${taskId}`);
            if (!res.ok) throw new Error('Task lookup failed');
            const data = await res.json();
            const task = data.task;

            if (!task) return;

            // Update Progress
            const pct = task.progress || 0;
            if (progressBar) progressBar.style.width = `${pct}%`;
            if (progressPct) progressPct.textContent = `${pct}%`;
            if (progressStep) progressStep.textContent = task.current_step || 'Elaborazione in corso...';

            // Append new logs safely
            const logs = task.logs || [];
            if (logs.length > lastLogIndex) {
                for (let i = lastLogIndex; i < logs.length; i++) {
                    const l = logs[i];
                    appendConsoleLog(`[${l.time}] ${l.text}`);
                }
                lastLogIndex = logs.length;
            }

            if (task.status === 'completed') {
                clearInterval(activeTaskInterval);
                activeTaskInterval = null;
                btnInstall.disabled = false;
                btnInstall.textContent = '✅ Installazione Completata';
                showToast('Modpack installato con successo in server_modpacks/!', 'success');
                loadInstalledModpacks();
                if (task.result) {
                    applyModpackToConfig(task.result);
                }
            } else if (task.status === 'failed') {
                clearInterval(activeTaskInterval);
                activeTaskInterval = null;
                btnInstall.disabled = false;
                btnInstall.textContent = '❌ Riprova Installazione';
                showToast(`Installazione fallita: ${task.error || 'Errore sconosciuto'}`, 'error');
            }
        } catch (err) {
            console.error('Polling error:', err);
        }
    }, 1500);
}

function appendConsoleLog(text) {
    const consoleEl = document.getElementById('cf-console-log');
    if (!consoleEl) return;
    if (consoleEl.textContent === 'In attesa dell\'avvio...') {
        consoleEl.textContent = '';
    }
    consoleEl.textContent += text + '\n';
    consoleEl.scrollTop = consoleEl.scrollHeight;
}

function clearConsoleLog() {
    const consoleEl = document.getElementById('cf-console-log');
    if (consoleEl) consoleEl.textContent = '';
}

async function loadInstalledModpacks() {
    const listContainer = document.getElementById('cf-installed-list');
    if (!listContainer) return;

    try {
        const res = await fetch('/api/curseforge/installed');
        if (!res.ok) throw new Error('Impossibile caricare i modpack installati');
        const data = await res.json();
        const modpacks = data.modpacks || [];

        listContainer.replaceChildren();

        if (modpacks.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'cf-empty-notice';
            empty.textContent = 'Nessun modpack attualmente presente in server_modpacks/. Inserisci un link sopra per scaricarne uno!';
            listContainer.appendChild(empty);
            return;
        }

        modpacks.forEach(mp => {
            const item = document.createElement('div');
            item.className = 'cf-installed-item';

            const iconDiv = document.createElement('div');
            iconDiv.className = 'cf-item-icon';
            iconDiv.textContent = '📦';

            const details = document.createElement('div');
            details.className = 'cf-item-details';

            const titleRow = document.createElement('div');
            titleRow.className = 'cf-item-title-row';

            const title = document.createElement('strong');
            title.className = 'cf-item-name';
            title.textContent = mp.name || mp.slug;

            const loaderBadge = document.createElement('span');
            const loaderType = (mp.server_type || 'FORGE').toUpperCase();
            loaderBadge.className = `badge badge-sm badge-loader badge-${loaderType.toLowerCase()}`;
            loaderBadge.textContent = loaderType;

            const verBadge = document.createElement('span');
            verBadge.className = 'badge badge-sm badge-version';
            verBadge.textContent = `MC ${mp.mc_version || '1.20.1'}`;

            const newBadge = document.createElement('span');
            newBadge.className = 'badge badge-sm badge-warning';
            newBadge.style.background = 'rgba(234, 179, 8, 0.15)';
            newBadge.style.color = '#fde047';
            newBadge.style.border = '1px solid rgba(234, 179, 8, 0.3)';
            newBadge.textContent = '📦 Nuovo (Senza Mondo)';

            titleRow.appendChild(title);
            titleRow.appendChild(newBadge);
            titleRow.appendChild(loaderBadge);
            titleRow.appendChild(verBadge);

            const metaRow = document.createElement('div');
            metaRow.className = 'cf-item-meta';
            metaRow.textContent = `📁 server_modpacks/${mp.slug} • ${mp.mods_count} mod • ${mp.size_mb} MB`;

            details.appendChild(titleRow);
            details.appendChild(metaRow);

            const actions = document.createElement('div');
            actions.className = 'cf-item-actions';

            const activateBtn = document.createElement('button');
            activateBtn.type = 'button';
            activateBtn.className = 'btn btn-sm btn-primary';
            activateBtn.textContent = '🚀 Attiva nel Server (Nuovo Mondo)';
            activateBtn.title = 'Attiva questo modpack pulito in ./data e crea un nuovo mondo';
            activateBtn.onclick = () => activateModpack(mp.slug);

            const applyBtn = document.createElement('button');
            applyBtn.type = 'button';
            applyBtn.className = 'btn btn-sm btn-secondary';
            applyBtn.textContent = '⚙️ Applica Modpack Config';
            applyBtn.title = 'Applica la configurazione del modpack';
            applyBtn.onclick = () => applyModpackToConfig(mp);

            const delBtn = document.createElement('button');
            delBtn.type = 'button';
            delBtn.className = 'btn btn-sm btn-danger';
            delBtn.textContent = '🗑️';
            delBtn.title = 'Elimina cartella modpack';
            delBtn.onclick = () => deleteInstalledModpack(mp.slug);

            actions.appendChild(activateBtn);
            actions.appendChild(applyBtn);
            actions.appendChild(delBtn);

            item.appendChild(iconDiv);
            item.appendChild(details);
            item.appendChild(actions);

            listContainer.appendChild(item);
        });
    } catch (err) {
        listContainer.replaceChildren();
        const empty = document.createElement('div');
        empty.className = 'cf-empty-notice';
        empty.textContent = '0 Modpack installati (Nessun modpack attualmente presente in server_modpacks/). Inserisci un link o carica uno zip per aggiungerne uno.';
        listContainer.appendChild(empty);
    }
}

async function activateModpack(slug) {
    if (!confirm(`Vuoi attivare il modpack '${slug}' nel server?\n\nATTENZIONE: L'intera cartella ./data verrà svuotata e sostituita con i file del nuovo modpack (mods, config, overrides, ecc.) per evitare qualsiasi conflitto tra versioni diverse di Minecraft e loader.`)) {
        return;
    }

    showToast(`Attivazione e pulizia data/ in corso per '${slug}'...`, 'info');

    try {
        const res = await fetch('/api/curseforge/activate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slug: slug, clean_all_data: true })
        });
        const data = await res.json();
        if (!res.ok || data.status !== 'success') {
            throw new Error(data.detail || 'Attivazione non riuscita');
        }

        showToast(data.message || 'Modpack attivato con successo in ./data!', 'success');
        fetchConfig();
        loadAvailableModpacks();
        loadInstalledModpacks();
    } catch (err) {
        showToast(`Errore: ${err.message}`, 'error');
    }
}

async function deleteInstalledModpack(slug) {
    if (!confirm(`Sei sicuro di voler eliminare definitivamente la cartella 'server_modpacks/${slug}'?`)) {
        return;
    }

    try {
        const res = await fetch(`/api/curseforge/installed/${encodeURIComponent(slug)}`, {
            method: 'DELETE'
        });
        const data = await res.json();
        if (!res.ok || data.status !== 'success') {
            throw new Error(data.detail || 'Eliminazione non riuscita');
        }
        showToast(`Modpack '${slug}' eliminato con successo.`, 'success');
        loadInstalledModpacks();
    } catch (err) {
        showToast(`Errore: ${err.message}`, 'error');
    }
}


// ─── Custom Modpack Upload ───────────────────────────────────────────────────

function uploadCustomModpack() {
    const slugInput = document.getElementById('input-custom-slug');
    const fileInput = document.getElementById('input-custom-zip');

    const slug = slugInput.value.trim();
    const file = fileInput.files[0];

    if (!slug) {
        showToast('Devi specificare un nome (slug) per il modpack.', 'warning');
        return;
    }
    if (!/^[a-zA-Z0-9_-]+$/.test(slug)) {
        showToast('Lo slug può contenere solo lettere, numeri, trattini e underscore.', 'warning');
        return;
    }
    if (!file) {
        showToast('Devi selezionare un file archivio da caricare.', 'warning');
        return;
    }
    const validExtensions = ['.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tgz', '.bz2', '.xz'];
    const fileName = file.name.toLowerCase();
    if (!validExtensions.some(ext => fileName.endsWith(ext))) {
        showToast('Il file deve essere un archivio supportato (.zip, .rar, .7z, .tar.gz, etc.)', 'warning');
        return;
    }

    const btn = document.getElementById('btn-custom-upload');
    const progressContainer = document.getElementById('upload-progress-container');
    const progressBar = document.getElementById('upload-progress-bar');
    const progressPct = document.getElementById('upload-progress-pct');
    const progressStep = document.getElementById('upload-progress-step');

    btn.disabled = true;
    progressContainer.style.display = 'block';
    progressBar.style.width = '0%';
    progressPct.innerText = '0%';
    progressStep.innerText = 'Uploading...';

    const formData = new FormData();
    formData.append('file', file);
    formData.append('slug', slug);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/curseforge/upload', true);

    xhr.upload.onprogress = function (e) {
        if (e.lengthComputable) {
            const percentComplete = Math.round((e.loaded / e.total) * 100);
            progressBar.style.width = percentComplete + '%';
            progressPct.innerText = percentComplete + '%';
            if (percentComplete === 100) {
                progressStep.innerText = 'Processing server files... Please wait.';
            }
        }
    };

    xhr.onload = function () {
        btn.disabled = false;
        try {
            const data = JSON.parse(xhr.responseText);
            if (xhr.status === 200 && data.status === 'success') {
                showToast(`Modpack '${slug}' caricato e installato con successo!`, 'success');
                progressStep.innerText = 'Upload complete.';
                loadInstalledModpacks();
                fileInput.value = '';
                slugInput.value = '';
                setTimeout(() => { progressContainer.style.display = 'none'; }, 3000);
            } else {
                throw new Error(data.detail || 'Errore sconosciuto durante l\'upload');
            }
        } catch (e) {
            showToast(`Errore: ${e.message}`, 'error');
            progressStep.innerText = 'Upload failed.';
            progressBar.style.backgroundColor = '#ef4444'; // red
        }
    };

    xhr.onerror = function () {
        btn.disabled = false;
        showToast('Errore di rete durante l\'upload del file.', 'error');
        progressStep.innerText = 'Upload failed.';
        progressBar.style.backgroundColor = '#ef4444';
    };

    xhr.send(formData);
}

// ─── Custom World Upload ─────────────────────────────────────────────────────

function uploadCustomWorld() {
    const fileInput = document.getElementById('input-world-zip');
    const file = fileInput.files[0];

    if (!file) {
        showToast('Devi selezionare un file archivio da caricare.', 'warning');
        return;
    }
    const validExtensions = ['.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tgz', '.bz2', '.xz'];
    const fileName = file.name.toLowerCase();
    if (!validExtensions.some(ext => fileName.endsWith(ext))) {
        showToast('Il file deve essere un archivio supportato (.zip, .rar, .7z, .tar.gz, etc.)', 'warning');
        return;
    }

    const btn = document.getElementById('btn-world-upload');
    const progressContainer = document.getElementById('world-progress-container');
    const progressBar = document.getElementById('world-progress-bar');
    const progressPct = document.getElementById('world-progress-pct');
    const progressStep = document.getElementById('world-progress-step');

    btn.disabled = true;
    progressContainer.style.display = 'block';
    progressBar.style.width = '0%';
    progressPct.innerText = '0%';
    progressStep.innerText = 'Uploading...';

    const formData = new FormData();
    formData.append('file', file);

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/world/upload', true);

    xhr.upload.onprogress = function (e) {
        if (e.lengthComputable) {
            const percentComplete = Math.round((e.loaded / e.total) * 100);
            progressBar.style.width = percentComplete + '%';
            progressPct.innerText = percentComplete + '%';
            if (percentComplete === 100) {
                progressStep.innerText = 'Extracting world... Please wait.';
            }
        }
    };

    xhr.onload = function () {
        btn.disabled = false;
        try {
            const data = JSON.parse(xhr.responseText);
            if (xhr.status === 200 && data.status === 'success') {
                showToast(`Mondo caricato ed estratto con successo!`, 'success');
                progressStep.innerText = 'Upload complete.';
                fileInput.value = '';
                setTimeout(() => { progressContainer.style.display = 'none'; }, 3000);
            } else {
                throw new Error(data.detail || 'Errore sconosciuto durante l\'upload del mondo');
            }
        } catch (e) {
            showToast(`Errore: ${e.message}`, 'error');
            progressStep.innerText = 'Upload failed.';
            progressBar.style.backgroundColor = '#ef4444'; // red
        }
    };

    xhr.onerror = function () {
        btn.disabled = false;
        showToast('Errore di rete durante l\'upload del file.', 'error');
        progressStep.innerText = 'Upload failed.';
        progressBar.style.backgroundColor = '#ef4444';
    };

    xhr.send(formData);
}

// ─── Modpack Management (Swap) ───────────────────────────────────────────────

async function loadAvailableModpacks() {
    const select = document.getElementById('select-modpack');
    const activeDisplay = document.getElementById('active-server-name');
    const playedListContainer = document.getElementById('played-servers-list');
    const swapBtn = document.getElementById('btn-swap-modpack');

    try {
        const res = await fetch('/api/modpacks');
        if (!res.ok) throw new Error("Failed to fetch modpacks");

        const data = await res.json();
        const { active, available, played_servers } = data;

        if (activeDisplay) {
            activeDisplay.textContent = active || 'Nessuno';
        }

        if (select) {
            select.innerHTML = '';
        }
        if (playedListContainer) {
            playedListContainer.replaceChildren();
        }

        const servers = available || [];
        const details = played_servers || [];

        if (servers.length === 0) {
            if (select) {
                const opt = document.createElement('option');
                opt.value = "";
                opt.textContent = "Nessun server giocato in servers_played/";
                select.appendChild(opt);
                select.disabled = true;
            }
            if (swapBtn) {
                swapBtn.disabled = true;
            }
            if (playedListContainer) {
                const empty = document.createElement('div');
                empty.className = 'cf-empty-notice';
                empty.innerHTML = '📂 Nessun server giocato salvato in <code>servers_played/</code>.<br><small style="color: var(--muted); margin-top: 4px; display: block;">I server giocati appariranno qui automaticamente quando effettui uno Swap o archivi una sessione.</small>';
                playedListContainer.appendChild(empty);
            }
            return;
        }

        if (select) {
            select.disabled = false;
            servers.forEach(mp => {
                const opt = document.createElement('option');
                opt.value = mp;
                opt.textContent = mp === active ? `${mp} (Attualmente Attivo)` : mp;
                if (mp === active) {
                    opt.disabled = true;
                }
                select.appendChild(opt);
            });
        }

        if (swapBtn) {
            swapBtn.disabled = false;
        }

        if (playedListContainer) {
            details.forEach(srv => {
                const item = document.createElement('div');
                item.className = 'cf-installed-item';

                const iconDiv = document.createElement('div');
                iconDiv.className = 'cf-item-icon';
                iconDiv.textContent = '💾';

                const itemDetails = document.createElement('div');
                itemDetails.className = 'cf-item-details';

                const titleRow = document.createElement('div');
                titleRow.className = 'cf-item-title-row';

                const title = document.createElement('strong');
                title.className = 'cf-item-name';
                title.textContent = srv.name;

                const worldBadge = document.createElement('span');
                worldBadge.className = 'badge badge-sm badge-success';
                worldBadge.textContent = '🌍 Mondo Salvato';

                const loaderBadge = document.createElement('span');
                const loaderType = (srv.server_type || 'VANILLA').toUpperCase();
                loaderBadge.className = `badge badge-sm badge-loader badge-${loaderType.toLowerCase()}`;
                loaderBadge.textContent = loaderType;

                const verBadge = document.createElement('span');
                verBadge.className = 'badge badge-sm badge-version';
                verBadge.textContent = `MC ${srv.mc_version || '1.21.1'}`;

                titleRow.appendChild(title);
                titleRow.appendChild(worldBadge);
                titleRow.appendChild(loaderBadge);
                titleRow.appendChild(verBadge);

                const metaRow = document.createElement('div');
                metaRow.className = 'cf-item-meta';
                metaRow.textContent = `📁 servers_played/${srv.name} • Configurazione e mondo salvati`;

                itemDetails.appendChild(titleRow);
                itemDetails.appendChild(metaRow);

                const actions = document.createElement('div');
                actions.className = 'cf-item-actions';

                if (srv.name !== active) {
                    const swapToBtn = document.createElement('button');
                    swapToBtn.type = 'button';
                    swapToBtn.className = 'btn btn-sm btn-primary';
                    swapToBtn.textContent = '🔄 Carica Server';
                    swapToBtn.title = `Carica questo server salvato nel server attivo`;
                    swapToBtn.onclick = () => swapToModpack(srv.name);
                    actions.appendChild(swapToBtn);
                } else {
                    const activeBadge = document.createElement('span');
                    activeBadge.className = 'badge badge-sm badge-success';
                    activeBadge.textContent = '✅ In Esecuzione';
                    actions.appendChild(activeBadge);
                }

                item.appendChild(iconDiv);
                item.appendChild(itemDetails);
                item.appendChild(actions);

                playedListContainer.appendChild(item);
            });
        }

    } catch (err) {
        console.error("Error loading modpacks:", err);
        if (select) {
            select.innerHTML = '<option value="">Errore nel caricamento</option>';
        }
    }
}

async function swapToModpack(target) {
    if (!target) return;
    if (!confirm(`Sei sicuro di voler attivare il server '${target}'?\n\nQuesto fermerà il server attuale, salverà i dati correnti in servers_played/ e caricherà il mondo di '${target}'.`)) {
        return;
    }

    showToast(`Swap verso '${target}' avviato...`, 'info');

    try {
        const res = await fetch('/api/modpacks/swap', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ modpack: target })
        });

        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.detail || 'Failed to initiate swap');
        }

        showToast("Swap iniziato! Ricaricamento pagina tra 3 secondi...", 'success');
        setTimeout(() => {
            window.location.reload();
        }, 3000);

    } catch (err) {
        console.error("Error swapping modpacks:", err);
        showToast("Errore durante lo swap: " + err.message, 'error');
    }
}

async function swapModpack() {
    const select = document.getElementById('select-modpack');
    if (!select) return;

    const target = select.value;
    if (!target) {
        alert("Seleziona un server giocato valido per lo swap.");
        return;
    }

    await swapToModpack(target);
}
