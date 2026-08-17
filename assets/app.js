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
