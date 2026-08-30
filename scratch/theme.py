import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # We need to replace specific colors with variables.
    
    # 1. Replace rgba(255, 255, 255, X) -> rgba(var(--white-rgb), X)
    content = re.sub(r'rgba\(\s*255\s*,\s*255\s*,\s*255\s*,\s*([0-9.]+)\s*\)', r'rgba(var(--white-rgb), \1)', content)
    
    # 2. Replace rgba(0, 0, 0, X) -> rgba(var(--black-rgb), X)
    content = re.sub(r'rgba\(\s*0\s*,\s*0\s*,\s*0\s*,\s*([0-9.]+)\s*\)', r'rgba(var(--black-rgb), \1)', content)
    
    # 3. Replace rgba(15, 23, 42, X) -> rgba(var(--panel-rgb), X)
    content = re.sub(r'rgba\(\s*15\s*,\s*23\s*,\s*42\s*,\s*([0-9.]+)\s*\)', r'rgba(var(--panel-rgb), \1)', content)

    # 4. Replace rgba(10, 15, 26, X) -> rgba(var(--nav-bg-rgb), X)
    content = re.sub(r'rgba\(\s*10\s*,\s*15\s*,\s*26\s*,\s*([0-9.]+)\s*\)', r'rgba(var(--nav-bg-rgb), \1)', content)

    # 5. #ffffff / #fff -> var(--white)
    content = re.sub(r'#ffffff\b', 'var(--white)', content, flags=re.IGNORECASE)
    content = re.sub(r'#fff\b', 'var(--white)', content, flags=re.IGNORECASE)

    # 6. #000000 / #000 -> var(--black) (excluding colors in i18n section, but this is CSS)
    content = re.sub(r'#000000\b', 'var(--black)', content, flags=re.IGNORECASE)
    content = re.sub(r'#000\b', 'var(--black)', content, flags=re.IGNORECASE)

    with open(filepath, 'w') as f:
        f.write(content)

process_file('images/caddy/web/css/style.css')
process_file('images/caddy/web/css/config.css')

print("Done replacing.")
