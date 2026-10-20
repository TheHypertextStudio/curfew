const root = document.documentElement;
const systemTheme = matchMedia('(prefers-color-scheme: dark)');
const assetRoot = new URL('./assets/', document.currentScript.src);

function updateAppearance() {
  const dark = root.dataset.theme === 'dark';
  const schedule = document.querySelector('.schedule-image');
  if (schedule) {
    const source = new URL(`schedule-${dark ? 'dark' : 'light'}.png`, assetRoot).pathname;
    schedule.src = source;
    document.querySelector('.schedule-link').href = source;
  }
  document.querySelector('meta[name="theme-color"]').content = getComputedStyle(root)
    .getPropertyValue('--surface')
    .trim();
}

systemTheme.addEventListener('change', (event) => {
  root.dataset.theme = event.matches ? 'dark' : 'light';
  updateAppearance();
});
updateAppearance();
