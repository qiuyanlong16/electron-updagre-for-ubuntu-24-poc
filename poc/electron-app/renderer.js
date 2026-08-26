// Renderer process - displays app version and status
document.addEventListener('DOMContentLoaded', async () => {
  const versionEl = document.getElementById('app-version');
  const statusEl = document.getElementById('app-status');

  try {
    const version = await window.nanobotAPI.getAppVersion();
    versionEl.textContent = version;
    statusEl.textContent = 'Running';
    statusEl.style.color = '#27ae60';
  } catch (err) {
    versionEl.textContent = 'Error';
    statusEl.textContent = 'Failed to load';
    statusEl.style.color = '#e74c3c';
    console.error('Failed to get app version:', err);
  }
});
