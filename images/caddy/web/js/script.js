const LOCAL_STATUS_API = '/api/status';

let serverInfo = { ip: null, domain: null, name: null };

async function loadMembers() {
    const list = document.getElementById('members-list');
    let members = [];

    try {
        const res = await fetch('/members.json');
        members = await res.json();
    } catch (e) {
        list.innerHTML = '<li class="member-placeholder">Could not load members.json.</li>';
        return;
    }

    if (!members.length) {
        list.innerHTML = '<li class="member-placeholder">No members configured.</li>';
        return;
    }

    // Highlight member whose IP matches the Server IP
    const host = members.find(m => m.ip === serverInfo.ip);
    const greetEl = document.getElementById('visitor-greeting');
    if (host && greetEl) {
        greetEl.textContent = `👑 Server Host: ${host.name}`;
        greetEl.style.display = 'inline-block';
    }

    list.innerHTML = members.map(m => {
        const isHost = m.ip === serverInfo.ip;
        return `
        <li class="member-item${isHost ? ' member-host' : ''}">
            <span class="member-name">
                ${m.name}${isHost ? ' <span class="host-badge">👑 Host</span>' : ''}
            </span>
            <span class="member-ip">${m.ip}</span>
        </li>`;
    }).join('');
}

let serverIpsData = { ip_server: '127.0.0.1', ip_vpn1: '', ip_vpn2: '' };
let currentIpTab = 'normal';

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

function updateConnectAddress() {
    const fullDomain = formatFullDomain(serverInfo.domain, serverInfo.provider);
    let target = '—';

    const notConfigured = (typeof currentLang !== 'undefined' && currentLang === 'it') ? '— (Non configurato)' : '— (Not configured)';

    if (currentIpTab === 'normal') {
        target = serverIpsData.ip_server || serverInfo.ip || '127.0.0.1';
    } else if (currentIpTab === 'vpn1') {
        target = serverIpsData.ip_vpn1 || notConfigured;
    } else if (currentIpTab === 'vpn2') {
        target = serverIpsData.ip_vpn2 || notConfigured;
    } else if (currentIpTab === 'ddns') {
        target = fullDomain || notConfigured;
    }

    const connectEl = document.getElementById('connect-address');
    if (connectEl) connectEl.textContent = target;
}

function selectConnectIp(tab) {
    currentIpTab = tab;
    ['normal', 'vpn1', 'vpn2', 'ddns'].forEach(t => {
        const btn = document.getElementById(`tab-${t}`);
        if (btn) {
            btn.classList.toggle('active', t === tab);
        }
    });
    updateConnectAddress();
}

async function loadServerIps() {
    try {
        const res = await fetch('/api/server-ips');
        const json = await res.json();
        if (json.status === 'success' && json.data) {
            serverIpsData = json.data;
            const sInput = document.getElementById('ip-server-input');
            const v1Input = document.getElementById('ip-vpn1-input');
            const v2Input = document.getElementById('ip-vpn2-input');
            if (sInput) sInput.value = serverIpsData.ip_server || '127.0.0.1';
            if (v1Input) v1Input.value = serverIpsData.ip_vpn1 || '';
            if (v2Input) v2Input.value = serverIpsData.ip_vpn2 || '';
            updateConnectAddress();
        }
    } catch (e) {
        console.warn('Could not fetch /api/server-ips:', e);
    }
}

function toggleIpManager() {
    const body = document.getElementById('ip-manager-body');
    const btn = document.getElementById('ip-toggle-btn');
    if (!body) return;
    const isHidden = body.style.display === 'none';
    body.style.display = isHidden ? 'block' : 'none';
    if (btn) btn.textContent = isHidden ? '▲' : '▼';
}

async function saveServerIps() {
    const statusEl = document.getElementById('ip-save-status');
    const sInput = document.getElementById('ip-server-input');
    const v1Input = document.getElementById('ip-vpn1-input');
    const v2Input = document.getElementById('ip-vpn2-input');
    const isIt = (typeof currentLang !== 'undefined' && currentLang === 'it');
    
    if (statusEl) {
        statusEl.textContent = isIt ? '⏳ Salvataggio...' : '⏳ Saving...';
        statusEl.style.color = '#38bdf8';
    }

    const payload = {
        ip_server: sInput ? sInput.value.trim() : '127.0.0.1',
        ip_vpn1: v1Input ? v1Input.value.trim() : '',
        ip_vpn2: v2Input ? v2Input.value.trim() : ''
    };

    try {
        const res = await fetch('/api/server-ips', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();

        if (res.ok && data.status === 'success') {
            serverIpsData = data.data;
            if (statusEl) {
                statusEl.textContent = isIt ? '✅ Salvato con successo in env/server_ips.env!' : '✅ Saved successfully to env/server_ips.env!';
                statusEl.style.color = '#4ade80';
                setTimeout(() => { statusEl.textContent = ''; }, 4000);
            }
            updateConnectAddress();
            document.getElementById('server-ip').textContent = serverIpsData.ip_server || '—';
        } else {
            if (statusEl) {
                statusEl.textContent = isIt ? `❌ Errore: ${data.detail || data.message || 'Salvataggio fallito'}` : `❌ Error: ${data.detail || data.message || 'Save failed'}`;
                statusEl.style.color = '#ef4444';
            }
        }
    } catch (e) {
        if (statusEl) {
            statusEl.textContent = isIt ? `❌ Errore di rete: ${e.message}` : `❌ Network error: ${e.message}`;
            statusEl.style.color = '#ef4444';
        }
    }
}

async function loadServerInfo() {
    try {
        const res = await fetch('/server-info.json');
        serverInfo = await res.json();
        if (serverInfo.ips) {
            serverIpsData = serverInfo.ips;
        }
    } catch (e) {
        console.warn('Could not fetch server-info.json:', e);
    }

    const fullDomain = formatFullDomain(serverInfo.domain, serverInfo.provider);

    // Fill static fields immediately
    document.getElementById('server-name').textContent =
        serverInfo.name ? serverInfo.name.toUpperCase() : 'Minecraft Server';
    document.getElementById('server-ip').textContent =
        serverIpsData.ip_server || serverInfo.ip || '—';
    document.getElementById('server-address').textContent =
        fullDomain || serverIpsData.ip_server || serverInfo.ip || '—';

    updateConnectAddress();
    loadServerIps();
}

async function checkStatus() {
    const target = serverInfo.domain || serverInfo.ip;
    if (!target) {
        setOffline();
        return;
    }

    try {
        const res = await fetch(LOCAL_STATUS_API);
        const data = await res.json();

        if (data && data.online) {
            setOnline(data);
        } else {
            setOffline(data);
        }
    } catch (e) {
        setOffline();
    }

    document.getElementById('last-updated').textContent =
        new Date().toLocaleTimeString();
}

function setOnline(data) {
    const card = document.getElementById('status-card');
    const badge = document.getElementById('status-badge');
    const dot = document.getElementById('pulse-dot');
    const text = document.getElementById('status-text');
    const banner = document.getElementById('autostop-banner');

    if (banner) {
        banner.style.display = 'none';
    }

    card.classList.remove('offline');
    card.classList.add('online');
    dot.classList.add('online');
    dot.classList.remove('offline');
    text.textContent = '🟢 Online';

    const players = data.players;
    document.getElementById('player-count').textContent =
        players ? `${players.online} / ${players.max}` : '—';

    document.getElementById('server-version').textContent =
        data.version || '—';

    if (data.motd && data.motd.clean && data.motd.clean.length > 0) {
        const motdEl = document.getElementById('motd-box');
        document.getElementById('motd-text').textContent = data.motd.clean.join(' ');
        motdEl.style.display = '';
    }

    if (typeof setFaviconStatus === 'function') {
        setFaviconStatus('online');
    }
}

function setOffline(data) {
    const card = document.getElementById('status-card');
    const dot = document.getElementById('pulse-dot');
    const text = document.getElementById('status-text');
    const banner = document.getElementById('autostop-banner');
    const isIt = (typeof currentLang !== 'undefined' && currentLang === 'it');

    card.classList.remove('online');
    card.classList.add('offline');
    dot.classList.remove('online');
    dot.classList.add('offline');

    if (data && data.stopped_reason === 'autostop') {
        text.textContent = isIt ? '💤 Standby (Inattività)' : '💤 Standby (Inactivity)';
        if (banner) {
            banner.style.display = 'flex';
        }
        if (typeof setFaviconStatus === 'function') {
            setFaviconStatus('standby');
        }
    } else {
        text.textContent = '🔴 Offline';
        if (banner) {
            banner.style.display = 'none';
        }
        if (typeof setFaviconStatus === 'function') {
            setFaviconStatus('offline');
        }
    }

    document.getElementById('player-count').textContent = '—';
    document.getElementById('server-version').textContent = '—';
    document.getElementById('motd-box').style.display = 'none';
}

function copyAddress() {
    const addr = document.getElementById('connect-address').textContent;
    const isIt = (typeof currentLang !== 'undefined' && currentLang === 'it');
    navigator.clipboard.writeText(addr).then(() => {
        const btn = document.getElementById('copy-btn');
        btn.textContent = isIt ? '✅ Copiato!' : '✅ Copied!';
        setTimeout(() => btn.textContent = isIt ? '📋 Copia' : '📋 Copy', 1500);
    });
}

async function refresh() {
    const isIt = (typeof currentLang !== 'undefined' && currentLang === 'it');
    document.getElementById('status-text').textContent = isIt ? 'Controllo in corso...' : 'Checking...';
    document.getElementById('pulse-dot').classList.remove('online', 'offline');
    if (typeof setFaviconStatus === 'function') {
        setFaviconStatus('checking');
    }
    await checkStatus();
}

// Language change listener
document.addEventListener('languageChanged', () => {
    updateConnectAddress();
});

// Init
(async () => {
    await loadServerInfo();
    await Promise.all([checkStatus(), loadMembers()]);
})();

async function startServer() {
    const btn = document.getElementById('start-btn');
    btn.disabled = true;
    btn.textContent = '⏳ Starting...';
    try {
        const res = await fetch('/api/server/start', { method: 'POST' });
        const data = await res.json();
        if (data.status === 'success') {
            btn.textContent = '✅ Started';
            setTimeout(() => { btn.textContent = '▶ Start Server'; btn.disabled = false; }, 3000);
            refresh();
        } else {
            alert('Error: ' + data.message);
            btn.textContent = '▶ Start Server';
            btn.disabled = false;
        }
    } catch (e) {
        alert('Failed to start server: ' + e);
        btn.textContent = '▶ Start Server';
        btn.disabled = false;
    }
}

async function stopServer() {
    if (!confirm("Are you sure you want to stop the server?")) return;
    const btn = document.getElementById('stop-btn');
    btn.disabled = true;
    btn.textContent = '⏳ Stopping...';
    try {
        const res = await fetch('/api/server/stop', { method: 'POST' });
        const data = await res.json();
        if (data.status === 'success') {
            btn.textContent = '✅ Stopped';
            setTimeout(() => { btn.textContent = '⏹ Stop Server'; btn.disabled = false; }, 3000);
            refresh();
        } else {
            alert('Error: ' + data.message);
            btn.textContent = '⏹ Stop Server';
            btn.disabled = false;
        }
    } catch (e) {
        alert('Failed to stop server: ' + e);
        btn.textContent = '⏹ Stop Server';
        btn.disabled = false;
    }
}

// --- Log Viewer Logic ---
let logInterval = null;

function toggleLogs() {
    const logViewer = document.getElementById('log-viewer');
    if (logViewer.style.display === 'none') {
        logViewer.style.display = 'block';
        fetchLogs();
        logInterval = setInterval(fetchLogs, 2000);
    } else {
        logViewer.style.display = 'none';
        clearInterval(logInterval);
    }
}

async function fetchLogs() {
    const logContent = document.getElementById('log-content');
    try {
        const response = await fetch('/api/server/logs');
        const data = await response.json();
        
        if (data.status === 'success' && data.logs && data.logs.trim() !== '') {
            logContent.textContent = data.logs;
            logContent.scrollTop = logContent.scrollHeight;
        } else {
            logContent.textContent = "No logs available yet. The server might still be starting...";
        }
    } catch (err) {
        console.error("Failed to fetch logs", err);
        logContent.textContent = "Error fetching logs. Is the web container running?";
    }
}
