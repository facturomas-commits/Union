const BASE = '/api';

export class ApiError extends Error {
  constructor(message, status){
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.unauthorized = status === 401;
  }
}

async function request(path, options = {}){
  const opts = {
    method: options.method || 'GET',
    credentials: 'same-origin',
    headers: {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      ...(options.headers || {}),
    },
  };
  if (options.body !== undefined){
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(options.body);
  }

  let res;
  try {
    res = await fetch(BASE + path, opts);
  } catch (e){
    throw new ApiError('No se pudo conectar con el servidor', 0);
  }

  const ct = res.headers.get('content-type') || '';
  let data = null;
  if (ct.includes('application/json')){
    try { data = await res.json(); } catch (e) { data = null; }
  } else {
    try { data = await res.text(); } catch (e) { data = null; }
  }

  if (!res.ok){
    const msg = (data && data.error) ? data.error : `Error HTTP ${res.status}`;
    if (res.status === 401 && !path.startsWith('/auth/login')){
      window.dispatchEvent(new CustomEvent('union:unauthorized'));
    }
    throw new ApiError(msg, res.status);
  }
  return data;
}

export const api = {
  get: (path) => request(path),
  post: (path, body) => request(path, { method:'POST', body }),
  put: (path, body) => request(path, { method:'PUT', body }),
  del: (path) => request(path, { method:'DELETE' }),

  login: (username, password) => request('/auth/login', { method:'POST', body:{ username, password } }),
  logout: () => request('/auth/logout', { method:'POST', body:{} }),
  me: () => request('/auth/me'),

  daily: (date) => request(`/reports/daily?date=${encodeURIComponent(date)}`),
  dashboard: (date) => request(`/dashboard?date=${encodeURIComponent(date)}`),
  monthly: (month) => request(`/reports/monthly?month=${encodeURIComponent(month)}`),
  latest: () => request('/reports/latest'),
  maintenanceDue: (days) => request(`/reports/maintenance-due?days=${encodeURIComponent(days)}`),
  audit: (limit=200) => request(`/reports/audit?limit=${encodeURIComponent(limit)}`),

  exportDaily: (date) => window.open(`/api/reports/export/daily.csv?date=${encodeURIComponent(date)}`, '_blank'),
  exportMonthly: (month) => window.open(`/api/reports/export/monthly.csv?month=${encodeURIComponent(month)}`, '_blank'),
};

export function qs(params){
  const p = new URLSearchParams();
  Object.entries(params).forEach(([k,v]) => {
    if (v !== undefined && v !== null && v !== '') p.set(k, v);
  });
  const s = p.toString();
  return s ? `?${s}` : '';
}
