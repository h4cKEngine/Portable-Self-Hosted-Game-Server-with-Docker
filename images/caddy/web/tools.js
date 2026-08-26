async function runTool(category, action, arg = null) {
    const consoleDiv = document.getElementById(`${category}-console`);
    consoleDiv.style.display = 'block';
    consoleDiv.textContent = `⏳ Executing ${category} ${action}${arg ? ' ' + arg : ''}...\n`;

    try {
        const body = { category, action };
        if (arg) body.arg = arg;

        const response = await fetch('/api/tools/execute', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(body)
        });

        const data = await response.json();
        
        if (data.status === 'success') {
            consoleDiv.textContent += `\n✅ Process finished with exit code ${data.returncode}\n\n`;
            consoleDiv.textContent += data.output || "No output returned.";
        } else {
            consoleDiv.textContent += `\n❌ Error: ${data.message}\n`;
            if (data.output) {
                consoleDiv.textContent += `\nOutput:\n${data.output}`;
            }
        }
    } catch (err) {
        consoleDiv.textContent += `\n❌ Failed to execute: ${err.message}`;
    }
}
