import os
import re

files = [
    'images/caddy/web/index.html',
    'images/caddy/web/config.html',
    'images/caddy/web/tools.html'
]

theme_btn = """            <button type="button" class="lang-dropdown-btn" id="theme-toggle-btn" onclick="toggleTheme()" title="Toggle Theme" style="margin-left: 8px; padding: 6px 10px;">
                <span id="theme-icon">☀️</span>
            </button>
            <div class="lang-dropdown-wrapper\""""

script_tag = """    <script src="js/theme.js?v=13"></script>
    <script src="js/favicon.js"""

for f in files:
    with open(f, 'r') as file:
        content = file.read()
    
    # Insert button before lang-dropdown-wrapper
    content = content.replace('            <div class="lang-dropdown-wrapper"', theme_btn)
    
    # Insert script before favicon.js
    content = content.replace('    <script src="js/favicon.js', script_tag)
    
    with open(f, 'w') as file:
        file.write(content)

print("Added theme button and script to HTML files")
