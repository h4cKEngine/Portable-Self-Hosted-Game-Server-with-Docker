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

async function loadServerInfo() {
    try {
        const res = await fetch('/server-info.json');
        serverInfo = await res.json();
    } catch (e) {
        console.warn('Could not fetch server-info.json:', e);
    }

    // Fill static fields immediately
    document.getElementById('server-name').textContent =
        serverInfo.name ? serverInfo.name.toUpperCase() : 'Minecraft Server';
    document.getElementById('server-ip').textContent =
        serverInfo.ip || '—';
    document.getElementById('server-address').textContent =
        serverInfo.domain || serverInfo.ip || '—';

    const connectAddr = serverInfo.domain || serverInfo.ip || '—';
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
