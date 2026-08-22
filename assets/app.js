// ============================================================
// FINANCE HUB — shared app logic (loaded as an ES module)
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const supabase = createClient(
  window.SUPABASE_CONFIG.url,
  window.SUPABASE_CONFIG.anonKey
);

// ---------- Formatting ----------
export function formatINR(amount) {
  const n = Number(amount || 0);
  return '₹' + n.toLocaleString('en-IN', { maximumFractionDigits: 2 });
}
export function formatDate(d) {
  if (!d) return '';
  const dt = new Date(d);
  return dt.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}
export function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

// ---------- Auth guard ----------
// Call at the top of every protected page.
export async function requireAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    window.location.href = 'index.html';
    return null;
  }
  const profile = await getMyProfile(session.user.id);
  if (!profile || profile.status !== 'active') {
    await supabase.auth.signOut();
    window.location.href = 'index.html?inactive=1';
    return null;
  }
  window.__financeHub = { session, profile };
  return { session, profile };
}

export async function getMyProfile(userId) {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).single();
  if (error) { console.error(error); return null; }
  return data;
}

export async function logout() {
  await supabase.auth.signOut();
  window.location.href = 'index.html';
}

// ---------- Sites ----------
let _sitesCache = null;
export async function getSites(forceRefresh = false) {
  if (_sitesCache && !forceRefresh) return _sitesCache;
  const { data, error } = await supabase.from('sites').select('*').eq('status', 'active').order('site_name');
  if (error) { console.error(error); return []; }
  _sitesCache = data;
  return data;
}

export function currentSiteId() {
  return localStorage.getItem('fh_current_site') || 'all';
}
export function setCurrentSiteId(id) {
  localStorage.setItem('fh_current_site', id);
}

// ---------- Site selector + header + bottom nav (shared chrome) ----------
export async function renderChrome({ activeNav, title } = {}) {
  const header = document.getElementById('appHeader');
  if (header) {
    const sites = await getSites();
    const sel = currentSiteId();
    header.innerHTML = `
      <div class="brand">Finance<span class="dot">.</span>Hub</div>
      <div class="header-actions">
        <button class="global-search-btn" id="globalSearchBtn" title="Search">⌕</button>
        <select id="siteSelector">
          <option value="all" ${sel === 'all' ? 'selected' : ''}>All Sites</option>
          ${sites.map(s => `<option value="${s.id}" ${sel === s.id ? 'selected' : ''}>${s.site_name}</option>`).join('')}
        </select>
        <button class="header-btn" id="logoutBtn">Logout</button>
      </div>`;
    document.getElementById('siteSelector').addEventListener('change', (e) => {
      setCurrentSiteId(e.target.value);
      window.location.reload();
    });
    document.getElementById('logoutBtn').addEventListener('click', logout);
    document.getElementById('globalSearchBtn').addEventListener('click', openGlobalSearch);
  }

  const nav = document.getElementById('bottomNav');
  if (nav) {
    const items = [
      { key: 'dashboard', icon: '⌂', label: 'Home', href: 'dashboard.html' },
      { key: 'transactions', icon: '≡', label: 'Entries', href: 'client-payments.html' },
      { key: 'reports', icon: '▤', label: 'Reports', href: 'reports.html' },
      { key: 'import', icon: '⇧', label: 'Import', href: 'import.html' },
      { key: 'users', icon: '◎', label: 'Users', href: 'users.html' },
    ];
    nav.innerHTML = items.map(i => `
      <a href="${i.href}" class="${activeNav === i.key ? 'active' : ''}">
        <span class="icon">${i.icon}</span>${i.label}
      </a>`).join('');
  }

  if (title) {
    const t = document.getElementById('pageTitle');
    if (t) t.textContent = title;
  }
}

// ---------- Transactions sub-nav (Part 4 §2: Transactions submenu) ----------
export function renderSubNav(activeKey) {
  const el = document.getElementById('subNav');
  if (!el) return;
  const items = [
    { key: 'client', label: 'Client Receipts', href: 'client-payments.html' },
    { key: 'supplier', label: 'Supplier Expenses', href: 'supplier-expenses.html' },
    { key: 'contractor', label: 'Contractor', href: 'contractor-payments.html' },
    { key: 'labour', label: 'Labour', href: 'labour-payments.html' },
    { key: 'self', label: 'Self Expenses', href: 'self-expenses.html' },
    { key: 'allocation', label: 'Site Allocation', href: 'site-allocation.html' },
  ];
  el.innerHTML = items.map(i => `
    <a href="${i.href}" class="subnav-chip ${activeKey === i.key ? 'active' : ''}">${i.label}</a>
  `).join('');
}

// ---------- Parties (search + auto-create) ----------
export async function searchParties(query, partyType) {
  let q = supabase.from('parties').select('*').order('party_name').limit(15);
  if (partyType) q = q.eq('party_type', partyType);
  if (query) q = q.ilike('party_name', `%${query}%`);
  const { data, error } = await q;
  if (error) { console.error(error); return []; }
  return data;
}

export async function findOrCreateParty(name, partyType) {
  const clean = (name || '').trim();
  if (!clean) return null;
  const { data: existing } = await supabase
    .from('parties').select('*')
    .eq('party_name', clean).eq('party_type', partyType).maybeSingle();
  if (existing) return existing;
  const { data, error } = await supabase
    .from('parties').insert({ party_name: clean, party_type: partyType })
    .select().single();
  if (error) { console.error(error); return null; }
  return data;
}

// ---------- Audit log ----------
export async function logAudit(action, table, recordId, details = {}) {
  const profile = window.__financeHub?.profile;
  await supabase.from('audit_log').insert({
    user_id: profile?.id, action, transaction_table: table, record_id: recordId, details
  });
}

// ---------- Pagination-safe fetch (PostgREST caps a single response at 1000 rows) ----------
export async function fetchAllRows(buildQuery) {
  const PAGE = 1000;
  let page = 0, all = [];
  while (true) {
    const { data, error } = await buildQuery(page * PAGE, page * PAGE + PAGE - 1);
    if (error) { console.error(error); break; }
    all = all.concat(data || []);
    if (!data || data.length < PAGE) break;
    page++;
  }
  return all;
}

// ---------- Soft delete / archive (spec: never hard-delete financial records) ----------
export async function archiveRecord(table, id) {
  const { error } = await supabase.from(table).update({ status: 'archived' }).eq('id', id);
  if (!error) await logAudit('archive', table, id, {});
  return !error;
}

// ---------- Recent parties (quick-select chips on entry forms) ----------
export async function getRecentPartyNames(table, nameCol, dateCol, limit = 6) {
  const { data, error } = await supabase
    .from(table).select(`${nameCol}, ${dateCol}`)
    .eq('status', 'active').not(nameCol, 'is', null)
    .order(dateCol, { ascending: false }).limit(50);
  if (error) { console.error(error); return []; }
  const seen = new Set(), out = [];
  for (const row of data) {
    const name = (row[nameCol] || '').trim();
    if (name && !seen.has(name.toLowerCase())) { seen.add(name.toLowerCase()); out.push(name); }
    if (out.length >= limit) break;
  }
  return out;
}

// ---------- Repeat last entry (prefill site/party/mode from most recent row) ----------
export async function getLastEntry(table, siteId) {
  let q = supabase.from(table).select('*').eq('status', 'active').order('created_at', { ascending: false }).limit(1);
  if (siteId && siteId !== 'all') q = q.eq('site_id', siteId);
  const { data, error } = await q;
  if (error || !data || !data.length) return null;
  return data[0];
}

// ---------- Attachments ----------
export async function getAttachments(table, recordId) {
  const { data, error } = await supabase.from('attachments').select('*')
    .eq('transaction_table', table).eq('transaction_id', recordId);
  if (error) { console.error(error); return []; }
  return data;
}
export async function getAttachmentUrl(filePath) {
  const { data, error } = await supabase.storage.from('attachments').createSignedUrl(filePath, 3600);
  if (error) { console.error(error); return null; }
  return data.signedUrl;
}

// ---------- Site colour theming (consistent colour per site across the app) ----------
const SITE_PALETTE = ['#E8A33D', '#2B6CB0', '#2F855A', '#C0392B', '#805AD5', '#D69E2E'];
export function siteColor(siteId, sites) {
  if (!sites || !siteId) return SITE_PALETTE[0];
  const idx = sites.findIndex(s => s.id === siteId);
  return SITE_PALETTE[idx >= 0 ? idx % SITE_PALETTE.length : 0];
}

// ---------- Global search (searches names across all 4 ledgers) ----------
async function openGlobalSearch() {
  let overlay = document.getElementById('globalSearchOverlay');
  if (overlay) { overlay.remove(); return; }
  overlay = document.createElement('div');
  overlay.id = 'globalSearchOverlay';
  overlay.className = 'search-overlay';
  overlay.innerHTML = `
    <div class="search-panel">
      <input type="search" id="globalSearchInput" placeholder="Search a name — client, supplier, contractor, labour…" autofocus>
      <div id="globalSearchResults" class="text-sm text-muted">Type at least 2 letters…</div>
    </div>`;
  overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
  document.body.appendChild(overlay);

  const input = document.getElementById('globalSearchInput');
  const resultsEl = document.getElementById('globalSearchResults');
  input.addEventListener('input', debounce(async () => {
    const q = input.value.trim();
    if (q.length < 2) { resultsEl.innerHTML = '<div class="text-sm text-muted">Type at least 2 letters…</div>'; return; }
    resultsEl.innerHTML = '<div class="text-sm text-muted">Searching…</div>';
    const tables = [
      { table: 'client_payments', nameCol: 'client_name', type: 'Client' },
      { table: 'expense_transactions', nameCol: 'party_name_snapshot', type: 'Supplier' },
      { table: 'contractor_payments', nameCol: 'contractor_name_snapshot', type: 'Contractor' },
      { table: 'labour_payments', nameCol: 'labour_name_snapshot', type: 'Labour' },
    ];
    const matches = await Promise.all(tables.map(async t => {
      const { data } = await supabase.from(t.table).select(t.nameCol).eq('status', 'active').ilike(t.nameCol, `%${q}%`).limit(200);
      const names = [...new Set((data || []).map(r => r[t.nameCol]).filter(Boolean))];
      return names.map(n => ({ name: n, type: t.type }));
    }));
    const flat = matches.flat();
    const seen = new Set(), unique = [];
    flat.forEach(m => { const k = m.name.toLowerCase() + '|' + m.type; if (!seen.has(k)) { seen.add(k); unique.push(m); } });
    resultsEl.innerHTML = unique.length
      ? unique.slice(0, 30).map(m => `
          <div class="search-result-row">
            <a href="reports.html?type=party&party=${encodeURIComponent(m.name)}" style="display:flex;justify-content:space-between;">
              <span>${m.name}</span><span class="chip pending">${m.type}</span>
            </a>
          </div>`).join('')
      : '<div class="text-sm text-muted">No matches found.</div>';
  }, 300));
}

// ---------- Small UI helpers ----------
export function showBanner(el, message, type = 'info') {
  el.className = `banner ${type}`;
  el.textContent = message;
  el.classList.remove('hidden');
}
export function money(n) { return Number(n || 0); }
export function debounce(fn, ms = 300) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}
