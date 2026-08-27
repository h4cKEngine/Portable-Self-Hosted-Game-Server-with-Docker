/**
 * Dynamic Favicon Manager for Minecraft Server Dashboard
 * Updates tab favicon based on server status: online (🟢), offline (🔴), standby (🟡), checking (🔵).
 */

(function () {
    const STATUS_BADGES = {
        online: {
            main: '#22c55e',
            high: '#4ade80'
        },
        offline: {
            main: '#ef4444',
            high: '#f87171'
        },
        standby: {
            main: '#f59e0b',
            high: '#fbbf24'
        },
        checking: {
            main: '#38bdf8',
            high: '#7dd3fc'
        }
    };

    const BASE_SVG_BODY = `<rect x="2" y="2" width="60" height="60" rx="14" fill="url(#bgGrad)" stroke="#334155" stroke-width="2"/>
  <g filter="url(#pickaxe-glow)">
  <rect x="29" y="8" width="3" height="3" fill="#0f3c4b"/>
  <rect x="32" y="8" width="3" height="3" fill="#0f3c4b"/>
  <rect x="35" y="8" width="3" height="3" fill="#228a9e"/>
  <rect x="38" y="8" width="3" height="3" fill="#228a9e"/>
  <rect x="23" y="11" width="3" height="3" fill="#0f3c4b"/>
  <rect x="26" y="11" width="3" height="3" fill="#0f3c4b"/>
  <rect x="29" y="11" width="3" height="3" fill="#228a9e"/>
  <rect x="32" y="11" width="3" height="3" fill="#8cf0ff"/>
  <rect x="35" y="11" width="3" height="3" fill="#8cf0ff"/>
  <rect x="38" y="11" width="3" height="3" fill="#8cf0ff"/>
  <rect x="41" y="11" width="3" height="3" fill="#228a9e"/>
  <rect x="20" y="14" width="3" height="3" fill="#0f3c4b"/>
  <rect x="23" y="14" width="3" height="3" fill="#228a9e"/>
  <rect x="26" y="14" width="3" height="3" fill="#8cf0ff"/>
  <rect x="29" y="14" width="3" height="3" fill="#8cf0ff"/>
  <rect x="32" y="14" width="3" height="3" fill="#dcffff"/>
  <rect x="35" y="14" width="3" height="3" fill="#dcffff"/>
  <rect x="38" y="14" width="3" height="3" fill="#228a9e"/>
  <rect x="41" y="14" width="3" height="3" fill="#8cf0ff"/>
  <rect x="44" y="14" width="3" height="3" fill="#0f3c4b"/>
  <rect x="17" y="17" width="3" height="3" fill="#0f3c4b"/>
  <rect x="20" y="17" width="3" height="3" fill="#228a9e"/>
  <rect x="23" y="17" width="3" height="3" fill="#8cf0ff"/>
  <rect x="26" y="17" width="3" height="3" fill="#8cf0ff"/>
  <rect x="29" y="17" width="3" height="3" fill="#dcffff"/>
  <rect x="41" y="17" width="3" height="3" fill="#228a9e"/>
  <rect x="44" y="17" width="3" height="3" fill="#8cf0ff"/>
  <rect x="47" y="17" width="3" height="3" fill="#0f3c4b"/>
  <rect x="14" y="20" width="3" height="3" fill="#0f3c4b"/>
  <rect x="17" y="20" width="3" height="3" fill="#228a9e"/>
  <rect x="20" y="20" width="3" height="3" fill="#8cf0ff"/>
  <rect x="23" y="20" width="3" height="3" fill="#8cf0ff"/>
  <rect x="38" y="20" width="3" height="3" fill="#8e5526"/>
  <rect x="41" y="20" width="3" height="3" fill="#663918"/>
  <rect x="44" y="20" width="3" height="3" fill="#228a9e"/>
  <rect x="47" y="20" width="3" height="3" fill="#8cf0ff"/>
  <rect x="50" y="20" width="3" height="3" fill="#228a9e"/>
  <rect x="11" y="23" width="3" height="3" fill="#0f3c4b"/>
  <rect x="14" y="23" width="3" height="3" fill="#228a9e"/>
  <rect x="17" y="23" width="3" height="3" fill="#8cf0ff"/>
  <rect x="20" y="23" width="3" height="3" fill="#228a9e"/>
  <rect x="35" y="23" width="3" height="3" fill="#8e5526"/>
  <rect x="38" y="23" width="3" height="3" fill="#2d190a"/>
  <rect x="47" y="23" width="3" height="3" fill="#228a9e"/>
  <rect x="50" y="23" width="3" height="3" fill="#8cf0ff"/>
  <rect x="53" y="23" width="3" height="3" fill="#228a9e"/>
  <rect x="11" y="26" width="3" height="3" fill="#0f3c4b"/>
  <rect x="14" y="26" width="3" height="3" fill="#8cf0ff"/>
  <rect x="17" y="26" width="3" height="3" fill="#228a9e"/>
  <rect x="32" y="26" width="3" height="3" fill="#8e5526"/>
  <rect x="35" y="26" width="3" height="3" fill="#2d190a"/>
  <rect x="47" y="26" width="3" height="3" fill="#dcffff"/>
  <rect x="50" y="26" width="3" height="3" fill="#8cf0ff"/>
  <rect x="53" y="26" width="3" height="3" fill="#228a9e"/>
  <rect x="11" y="29" width="3" height="3" fill="#0f3c4b"/>
  <rect x="14" y="29" width="3" height="3" fill="#228a9e"/>
  <rect x="29" y="29" width="3" height="3" fill="#8e5526"/>
  <rect x="32" y="29" width="3" height="3" fill="#2d190a"/>
  <rect x="47" y="29" width="3" height="3" fill="#dcffff"/>
  <rect x="50" y="29" width="3" height="3" fill="#8cf0ff"/>
  <rect x="53" y="29" width="3" height="3" fill="#0f3c4b"/>
  <rect x="11" y="32" width="3" height="3" fill="#0f3c4b"/>
  <rect x="26" y="32" width="3" height="3" fill="#8e5526"/>
  <rect x="29" y="32" width="3" height="3" fill="#2d190a"/>
  <rect x="44" y="32" width="3" height="3" fill="#dcffff"/>
  <rect x="47" y="32" width="3" height="3" fill="#8cf0ff"/>
  <rect x="50" y="32" width="3" height="3" fill="#228a9e"/>
  <rect x="53" y="32" width="3" height="3" fill="#0f3c4b"/>
  <rect x="23" y="35" width="3" height="3" fill="#8e5526"/>
  <rect x="26" y="35" width="3" height="3" fill="#2d190a"/>
  <rect x="44" y="35" width="3" height="3" fill="#8cf0ff"/>
  <rect x="47" y="35" width="3" height="3" fill="#8cf0ff"/>
  <rect x="50" y="35" width="3" height="3" fill="#0f3c4b"/>
  <rect x="20" y="38" width="3" height="3" fill="#8e5526"/>
  <rect x="23" y="38" width="3" height="3" fill="#2d190a"/>
  <rect x="41" y="38" width="3" height="3" fill="#8cf0ff"/>
  <rect x="44" y="38" width="3" height="3" fill="#8cf0ff"/>
  <rect x="47" y="38" width="3" height="3" fill="#228a9e"/>
  <rect x="50" y="38" width="3" height="3" fill="#0f3c4b"/>
  <rect x="17" y="41" width="3" height="3" fill="#8e5526"/>
  <rect x="20" y="41" width="3" height="3" fill="#2d190a"/>
  <rect x="38" y="41" width="3" height="3" fill="#228a9e"/>
  <rect x="41" y="41" width="3" height="3" fill="#8cf0ff"/>
  <rect x="44" y="41" width="3" height="3" fill="#228a9e"/>
  <rect x="47" y="41" width="3" height="3" fill="#0f3c4b"/>
  <rect x="14" y="44" width="3" height="3" fill="#8e5526"/>
  <rect x="17" y="44" width="3" height="3" fill="#2d190a"/>
  <rect x="35" y="44" width="3" height="3" fill="#228a9e"/>
  <rect x="38" y="44" width="3" height="3" fill="#8cf0ff"/>
  <rect x="41" y="44" width="3" height="3" fill="#228a9e"/>
  <rect x="44" y="44" width="3" height="3" fill="#0f3c4b"/>
  <rect x="11" y="47" width="3" height="3" fill="#8e5526"/>
  <rect x="14" y="47" width="3" height="3" fill="#2d190a"/>
  <rect x="32" y="47" width="3" height="3" fill="#228a9e"/>
  <rect x="35" y="47" width="3" height="3" fill="#8cf0ff"/>
  <rect x="38" y="47" width="3" height="3" fill="#228a9e"/>
  <rect x="41" y="47" width="3" height="3" fill="#0f3c4b"/>
  <rect x="8" y="50" width="3" height="3" fill="#8e5526"/>
  <rect x="11" y="50" width="3" height="3" fill="#2d190a"/>
  <rect x="29" y="50" width="3" height="3" fill="#0f3c4b"/>
  <rect x="32" y="50" width="3" height="3" fill="#0f3c4b"/>
  <rect x="35" y="50" width="3" height="3" fill="#0f3c4b"/>
  <rect x="38" y="50" width="3" height="3" fill="#0f3c4b"/>
  <rect x="8" y="53" width="3" height="3" fill="#2d190a"/>
  </g>`;

    let currentStatus = null;

    function buildSvg(status) {
        let badge = '';
        if (status && STATUS_BADGES[status]) {
            const b = STATUS_BADGES[status];
            badge = `
  <circle cx="52" cy="52" r="9" fill="#0a0f1a" stroke="#1e293b" stroke-width="1.5"/>
  <circle cx="52" cy="52" r="6.5" fill="${b.main}"/>
  <circle cx="50" cy="50" r="2" fill="${b.high}"/>`;
        }

        return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1e293b"/>
      <stop offset="100%" stop-color="#0a0f1d"/>
    </linearGradient>
    <filter id="pickaxe-glow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#000000" flood-opacity="0.5"/>
    </filter>
  </defs>
  ${BASE_SVG_BODY}
  ${badge}
</svg>`;
    }

    function setFaviconStatus(status) {
        if (currentStatus === status) return;
        currentStatus = status;

        const svgCode = buildSvg(status);
        const dataUrl = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgCode);

        // Update favicon elements in document head
        let iconLink = document.getElementById('dynamic-favicon');
        if (!iconLink) {
            iconLink = document.querySelector('link[rel="icon"][type="image/svg+xml"]');
            if (iconLink) iconLink.id = 'dynamic-favicon';
        }

        if (iconLink) {
            iconLink.href = dataUrl;
        } else {
            const newLink = document.createElement('link');
            newLink.id = 'dynamic-favicon';
            newLink.rel = 'icon';
            newLink.type = 'image/svg+xml';
            newLink.href = dataUrl;
            document.head.appendChild(newLink);
        }
    }

    // Expose globally
    window.setFaviconStatus = setFaviconStatus;

    // Optional background check for pages without continuous status updater
    async function checkInitialStatus() {
        if (!document.getElementById('status-card')) {
            try {
                const res = await fetch('/api/status');
                if (res.ok) {
                    const data = await res.json();
                    if (data && data.online) {
                        setFaviconStatus('online');
                    } else if (data && data.stopped_reason === 'autostop') {
                        setFaviconStatus('standby');
                    } else {
                        setFaviconStatus('offline');
                    }
                } else {
                    setFaviconStatus('offline');
                }
            } catch (e) {
                setFaviconStatus('offline');
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', checkInitialStatus);
    } else {
        checkInitialStatus();
    }
})();
