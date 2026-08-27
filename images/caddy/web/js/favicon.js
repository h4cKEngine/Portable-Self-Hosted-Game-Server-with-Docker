/**
 * Universal Dynamic Favicon Manager for Minecraft Server Dashboard
 * Overlays live status badges (🟢 Online, 🔴 Offline, 🟡 Standby, 🔵 Checking)
 * directly on any custom favicon icon image.
 */

(function () {
    const STATUS_CONFIG = {
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

    const BASE_SRC = 'img/favicon-96x96.png';
    const FALLBACK_SRC = 'img/favicon.svg';

    let currentStatus = null;
    let baseImage = null;
    let imageLoaded = false;
    let offscreenCanvas = null;

    function initImage() {
        if (!offscreenCanvas) {
            offscreenCanvas = document.createElement('canvas');
            offscreenCanvas.width = 96;
            offscreenCanvas.height = 96;
        }

        if (!baseImage) {
            baseImage = new Image();
            baseImage.crossOrigin = 'anonymous';
            baseImage.onload = function () {
                imageLoaded = true;
                if (currentStatus) {
                    renderFavicon(currentStatus);
                }
            };
            baseImage.onerror = function () {
                if (baseImage.src.indexOf('favicon-96x96.png') !== -1) {
                    baseImage.src = FALLBACK_SRC;
                }
            };
            baseImage.src = BASE_SRC;
        }
    }

    function renderFavicon(status) {
        if (!imageLoaded || !baseImage || !offscreenCanvas) {
            return;
        }

        const ctx = offscreenCanvas.getContext('2d');
        ctx.clearRect(0, 0, 96, 96);
        ctx.drawImage(baseImage, 0, 0, 96, 96);

        if (status && STATUS_CONFIG[status]) {
            const colors = STATUS_CONFIG[status];
            const cx = 78;
            const cy = 78;
            const radius = 13;

            // Outer dark border circle
            ctx.beginPath();
            ctx.arc(cx, cy, radius + 3, 0, Math.PI * 2);
            ctx.fillStyle = '#0a0f1a';
            ctx.fill();

            // Main status colored circle
            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx.fillStyle = colors.main;
            ctx.fill();

            // Highlight dot
            ctx.beginPath();
            ctx.arc(cx - 3, cy - 3, 4, 0, Math.PI * 2);
            ctx.fillStyle = colors.high;
            ctx.fill();
        }

        const dataUrl = offscreenCanvas.toDataURL('image/png');
        applyFaviconUrl(dataUrl);
    }

    function applyFaviconUrl(url) {
        let dynamicLink = document.getElementById('dynamic-favicon');
        if (!dynamicLink) {
            dynamicLink = document.querySelector('link[rel="icon"]');
            if (dynamicLink) dynamicLink.id = 'dynamic-favicon';
        }

        if (dynamicLink) {
            dynamicLink.type = 'image/png';
            dynamicLink.href = url;
        }

        // Also update standard icon links so all browsers refresh tab icon
        const iconLinks = document.querySelectorAll('link[rel="icon"], link[rel="shortcut icon"]');
        iconLinks.forEach(link => {
            link.href = url;
        });
    }

    function setFaviconStatus(status) {
        if (currentStatus === status) return;
        currentStatus = status;

        if (imageLoaded) {
            renderFavicon(status);
        } else {
            initImage();
        }
    }

    // Expose globally
    window.setFaviconStatus = setFaviconStatus;

    // Optional background check for pages without continuous status poller
    async function checkInitialStatus() {
        initImage();
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
