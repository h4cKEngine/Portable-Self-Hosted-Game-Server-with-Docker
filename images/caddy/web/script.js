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

async function loadServerInfo() {
    try {
        const res = await fetch('/server-info.json');
        serverInfo = await res.json();
    } catch (e) {
        console.warn('Could not fetch server-info.json:', e);
    }

    const fullDomain = formatFullDomain(serverInfo.domain, serverInfo.provider);

    // Fill static fields immediately
    document.getElementById('server-name').textContent =
        serverInfo.name ? serverInfo.name.toUpperCase() : 'Minecraft Server';
    document.getElementById('server-ip').textContent =
        serverInfo.ip || '—';
    document.getElementById('server-address').textContent =
        fullDomain || serverInfo.ip || '—';

    const connectAddr = fullDomain || serverInfo.ip || '—';
    document.getElementById('connect-address').textContent = connectAddr;
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
            setOffline();
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
}

function setOffline() {
    const card = document.getElementById('status-card');
    const dot = document.getElementById('pulse-dot');
    const text = document.getElementById('status-text');

    card.classList.remove('online');
    card.classList.add('offline');
    dot.classList.remove('online');
    dot.classList.add('offline');
    text.textContent = '🔴 Offline';

    document.getElementById('player-count').textContent = '—';
    document.getElementById('server-version').textContent = '—';
    document.getElementById('motd-box').style.display = 'none';
}

function copyAddress() {
    const addr = document.getElementById('connect-address').textContent;
    navigator.clipboard.writeText(addr).then(() => {
        const btn = document.getElementById('copy-btn');
        btn.textContent = '✅ Copied!';
        setTimeout(() => btn.textContent = '📋 Copy', 1500);
    });
}

async function refresh() {
    document.getElementById('status-text').textContent = 'Checking...';
    document.getElementById('pulse-dot').classList.remove('online', 'offline');
    await checkStatus();
}

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
