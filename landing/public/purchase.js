const panel = document.querySelector('[data-purchase-mode]');
const issuer = panel.dataset.issuer;
const scheme = panel.dataset.scheme;
const tokenPattern = /^[A-Za-z0-9_-]{43}$/;
const status = document.getElementById('purchase-status');
const states = ['state-loading', 'state-success', 'restore-form', 'state-error'];
let ticket;
let savedKey;

function show(id) {
  for (const state of states) document.getElementById(state).hidden = state !== id;
}

function error(message) {
  document.getElementById('error-detail').textContent = message;
  show('state-error');
}

async function post(path, body) {
  return fetch(`${issuer}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    cache: 'no-store',
    credentials: 'omit',
    referrerPolicy: 'no-referrer',
    signal: AbortSignal.timeout(20000),
  });
}

function ready(token, key) {
  if (!tokenPattern.test(token) || (key !== undefined && typeof key !== 'string')) {
    error('Your activation link could not be prepared. Try again.');
    return;
  }
  ticket = token;
  savedKey = key;
  document.getElementById('activate-link').href = `${scheme}://activate?token=${token}`;
  status.textContent = '';
  show('state-success');
}

async function loadPurchase() {
  const sessionID = new URLSearchParams(location.search).get('session_id');
  if (!/^cs_[A-Za-z0-9_]{1,200}$/.test(sessionID || '')) {
    error(
      'Reopen your checkout confirmation or restore your purchase using the email on your receipt.',
    );
    return;
  }
  show('state-loading');
  status.textContent = '';
  try {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const response = await post('/license/activation', { session_id: sessionID });
      if (response.ok) {
        const purchase = await response.json();
        ready(purchase.activation_token, purchase.license_key);
        return;
      }
      if (response.status !== 404) {
        error("Couldn't reach the purchase service. Check your connection and try again.");
        return;
      }
      if (attempt < 4) await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
    }
    error('Your purchase is still processing. Try again in a minute or restore your purchase.');
  } catch {
    error("Couldn't reach the purchase service. Check your connection and try again.");
  }
}

document.getElementById('manual-entry').addEventListener('toggle', async (event) => {
  if (!event.target.open) return;
  try {
    if (!savedKey) {
      const response = await post('/license/redeem', { token: ticket });
      if (!response.ok) throw new Error('unavailable');
      savedKey = (await response.json()).license_key;
    }
    if (typeof savedKey !== 'string' || !savedKey) throw new Error('unavailable');
    document.getElementById('license-key').textContent = savedKey;
    document.getElementById('manual-key').hidden = false;
  } catch {
    error('This link is unavailable or expired. Request another restore link.');
  }
});

document.getElementById('copy-btn').addEventListener('click', async (event) => {
  try {
    await navigator.clipboard.writeText(savedKey);
    event.target.textContent = 'Copied';
  } catch {
    const range = document.createRange();
    range.selectNodeContents(document.getElementById('license-key'));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = 'Press ⌘C to copy your selected license key.';
  }
});

document.getElementById('restore-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const email = document.getElementById('purchase-email').value.trim().toLowerCase();
  const button = event.target.querySelector('button');
  button.disabled = true;
  status.textContent = 'Sending restore link…';
  try {
    const response = await post('/license/restore', { email });
    if (!response.ok) {
      status.textContent =
        response.status === 429
          ? 'Please wait a minute before requesting another link.'
          : "Couldn't send your restore link. Try again shortly or contact support.";
      return;
    }
    status.textContent = `Check ${email} for your restore link.`;
  } catch {
    status.textContent =
      "Couldn't reach the purchase service. Check your connection and try again.";
  } finally {
    button.disabled = false;
  }
});

document.getElementById('retry-btn').addEventListener('click', () => {
  if (panel.dataset.purchaseMode === 'checkout') void loadPurchase();
  else {
    status.textContent = '';
    show('restore-form');
  }
});

function restoreFromLink() {
  const token = new URLSearchParams(location.hash.slice(1)).get('token');
  // Fragments stay out of server requests. Clear history before navigation.
  history.replaceState(null, '', location.pathname);
  if (token && tokenPattern.test(token)) ready(token);
  else show('restore-form');
}

if (panel.dataset.purchaseMode === 'checkout') void loadPurchase();
else {
  window.addEventListener('hashchange', restoreFromLink);
  restoreFromLink();
}
