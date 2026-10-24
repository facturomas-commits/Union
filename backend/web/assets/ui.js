/* Utilidades de interfaz */
const moneyFmt = new Intl.NumberFormat('es-AR', { style:'currency', currency:'ARS', minimumFractionDigits:2, maximumFractionDigits:2 });
const numFmt = new Intl.NumberFormat('es-AR', { minimumFractionDigits:2, maximumFractionDigits:2 });
const intFmt = new Intl.NumberFormat('es-AR', { maximumFractionDigits:0 });

export function esc(v){
  return String(v === null || v === undefined ? '' : v)
    .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
    .replaceAll('"','&quot;').replaceAll("'",'&#39;');
}
export function money(n){
  const v = Number(n);
  return moneyFmt.format(Number.isFinite(v) ? v : 0);
}
export function num(n, d=2){
  const v = Number(n);
  if (!Number.isFinite(v)) return '0,00';
  return new Intl.NumberFormat('es-AR', { minimumFractionDigits:d, maximumFractionDigits:d }).format(v);
}
export function integer(n){
  const v = Number(n);
  return intFmt.format(Number.isFinite(v) ? v : 0);
}
export function compact(n){
  const v = Number(n) || 0;
  if (Math.abs(v) >= 1e6) return (v/1e6).toFixed(v % 1e6 === 0 ? 0 : 1) + 'M';
  if (Math.abs(v) >= 1e3) return (v/1e3).toFixed(v % 1e3 === 0 ? 0 : 0) + 'k';
  return String(Math.round(v));
}
export function todayISO(d = new Date()){
  const y=d.getFullYear(), m=String(d.getMonth()+1).padStart(2,'0'), day=String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}
export function monthISO(d = new Date()){
  const y=d.getFullYear(), m=String(d.getMonth()+1).padStart(2,'0');
  return `${y}-${m}`;
}
export function addDays(iso, n){
  const [y,m,d]=iso.split('-').map(Number);
  const dt=new Date(y, m-1, d);
  dt.setDate(dt.getDate()+n);
  return todayISO(dt);
}
export function dateDMY(iso){
  if (!iso) return '—';
  const s=String(iso);
  const m=s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  return s;
}
export function dateShort(iso){
  if (!iso) return '';
  const s=String(iso);
  const m=s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[3]}/${m[2]}`;
  return s;
}
export function timeHM(t){
  if (!t) return '—';
  return String(t).slice(0,5);
}
export function dateTime(iso){
  if (!iso) return '—';
  const s=String(iso).replace('T',' ');
  const d=s.slice(0,10), h=s.slice(11,16);
  return dateDMY(d) + (h ? ` ${h}` : '');
}
export function monthLabel(ym){
  if (!ym) return '';
  const [y,m]=ym.split('-').map(Number);
  return new Date(y,m-1,1).toLocaleDateString('es-AR',{month:'long',year:'numeric'});
}
export function initials(name){
  return String(name||'?').trim().split(/\s+/).slice(0,2).map(x=>x[0]).join('').toUpperCase();
}
export function statusBadge(status){
  if (status === 'closed') return '<span class="badge green"><span class="dot"></span>Cerrado</span>';
  return '<span class="badge orange"><span class="dot"></span>Abierto</span>';
}
export function roleLabel(role){
  return ({superadmin:'Superadmin',admin:'Administrador',supervisor:'Supervisor',operator:'Operador',viewer:'Consulta'})[role] || role;
}

const ICONS = {
  dashboard:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  bus:'<path d="M6 17h12M6 17v2m12-2v2M4 8h16v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8Z"/><path d="M4 10h16M8 5h8a2 2 0 0 1 2 2v1H6V7a2 2 0 0 1 2-2Z"/><circle cx="7.5" cy="13.5" r=".8"/><circle cx="16.5" cy="13.5" r=".8"/>',
  fuel:'<path d="M4 20V6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v14M3 20h12M4 10h10"/><path d="M14 8h2l3 3v6a2 2 0 0 1-4 0v-4h-1"/>',
  receipt:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 7h6M9 11h6M9 15h3"/>',
  wrench:'<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17v3h3l5.3-5.3a4 4 0 0 0 5.4-5.4l-2.3 2.3-2.7-2.7 2-3Z"/>',
  truck:'<path d="M3 7h11v9H3zM14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="1.6"/><circle cx="18" cy="18" r="1.6"/>',
  chart:'<path d="M4 20V4M4 20h16"/><path d="M7 16l4-5 3 2 4-6"/>',
  users:'<circle cx="9" cy="8" r="3"/><path d="M3 20c0-3 2.7-5 6-5s6 2 6 5"/><path d="M16 5.5a3 3 0 0 1 0 5.8M17 15c2.6.4 4 2 4 4.5"/>',
  settings:'<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2 2-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6V21h-2.8v-.2a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1-2-2 .1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.6-1H3v-2.8h.2a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9l-.1-.1 2-2 .1.1a1.7 1.7 0 0 0 1.9.3 1.7 1.7 0 0 0 1-1.6V3h2.8v.2a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1 2 2-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1H21v2.8h-.2a1.7 1.7 0 0 0-1.4 1Z"/>',
  audit:'<path d="M9 5h11M9 12h11M9 19h11"/><path d="M4 5h.01M4 12h.01M4 19h.01"/>',
  logout:'<path d="M10 17l5-5-5-5"/><path d="M15 12H3"/><path d="M15 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  edit:'<path d="M4 20h4l10-10-4-4L4 16v4Z"/><path d="M14 6l4 4"/>',
  trash:'<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/><path d="M10 11v5M14 11v5"/>',
  check:'<path d="M5 13l4 4L19 7"/>',
  x:'<path d="M6 6l12 12M18 6L6 18"/>',
  calendar:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  download:'<path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 19h16"/>',
  print:'<path d="M7 8V3h10v5"/><rect x="4" y="8" width="16" height="8" rx="2"/><path d="M7 14h10v7H7z"/>',
  search:'<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
  alert:'<path d="M12 3l10 18H2L12 3Z"/><path d="M12 9v5M12 17h.01"/>',
  arrow:'<path d="M5 12h14M13 6l6 6-6 6"/>',
  refresh:'<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
  lock:'<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  building:'<path d="M4 21V4h10v17M14 9h6v12M8 8h2M8 12h2M8 16h2M17 13h1M17 17h1"/>',
  user:'<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-6 8-6s8 2 8 6"/>',
  eye:'<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/>',
  menu:'<path d="M4 7h16M4 12h16M4 17h16"/>',
  route:'<circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M8 19h4a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h7"/>',
  coins:'<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/><path d="M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6"/>',
  file:'<path d="M6 3h8l4 4v14H6V3Z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
};

export function icon(name, size=16){
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]||ICONS.file}</svg>`;
}

export function toast(message, type='ok'){
  const root=document.getElementById('toasts');
  const el=document.createElement('div');
  el.className=`toast ${type}`;
  el.textContent=message;
  root.appendChild(el);
  setTimeout(()=>{ el.style.opacity='0'; el.style.transform='translateY(6px)'; setTimeout(()=>el.remove(),200); }, 3200);
}

export function options(items, valueKey, labelFn, selected){
  if (!items) return '';
  return items.map(it=>{
    const val=typeof valueKey==='function'?valueKey(it):it[valueKey];
    const label=typeof labelFn==='function'?labelFn(it):it[labelFn];
    const sel=String(val)===String(selected)?' selected':'';
    return `<option value="${esc(val)}"${sel}>${esc(label)}</option>`;
  }).join('');
}

export function loading(container, rows=4){
  container.innerHTML = `<div class="loading">${Array.from({length:rows}).map(()=>`<div class="skeleton" style="width:${60+Math.random()*35}%"></div>`).join('')}</div>`;
}

export function emptyState(title, text, iconName='file'){
  return `<div class="empty"><div class="mark">${icon(iconName,20)}</div><strong>${esc(title)}</strong><span>${esc(text||'')}</span></div>`;
}

export function openModal({title, subtitle='', body='', wide=false, xwide=false, submitText='Guardar', hideSubmit=false, onSubmit, onReady}){
  const root=document.getElementById('modal-root');
  const wrap=document.createElement('div');
  wrap.className='modal-backdrop';
  wrap.innerHTML=`<div class="modal ${xwide?'xwide':wide?'wide':''}" role="dialog" aria-modal="true">
    <div class="modal-head">
      <div><h3>${esc(title)}</h3>${subtitle?`<p>${esc(subtitle)}</p>`:''}</div>
      <button type="button" class="icon-btn" data-close aria-label="Cerrar" style="color:var(--muted)">${icon('x')}</button>
    </div>
    <form novalidate>
      <div class="modal-body"><div class="form-error" data-error></div>${body}</div>
      ${hideSubmit?'':`<div class="modal-foot"><button type="button" class="btn btn-secondary" data-close>Cancelar</button><button type="submit" class="btn">${esc(submitText)}</button></div>`}
    </form>
  </div>`;
  root.appendChild(wrap);
  const form=wrap.querySelector('form');
  const err=wrap.querySelector('[data-error]');
  const onKey=(e)=>{ if(e.key==='Escape') close(); };
  function close(){ wrap.remove(); document.removeEventListener('keydown', onKey); }
  document.addEventListener('keydown', onKey);
  wrap.querySelectorAll('[data-close]').forEach(b=>b.onclick=close);
  wrap.addEventListener('mousedown', e=>{ if(e.target===wrap) close(); });
  form.addEventListener('submit', async e=>{
    e.preventDefault();
    err.classList.remove('show');
    const btn=form.querySelector('button[type=submit]');
    if(btn) btn.disabled=true;
    try{
      if(onSubmit) await onSubmit(form, close);
    }catch(ex){
      err.textContent=ex.message||'Ocurrió un error';
      err.classList.add('show');
    }finally{
      if(btn) btn.disabled=false;
    }
  });
  if(onReady) onReady(form, close);
  setTimeout(()=>{ const f=form.querySelector('input:not([type=hidden]),select,textarea'); if(f) f.focus(); },30);
  return {form, close, root:wrap};
}

export function confirmDialog({title='Confirmar', message='', confirmText='Eliminar', danger=true}){
  return new Promise(resolve=>{
    const root=document.getElementById('modal-root');
    const wrap=document.createElement('div');
    wrap.className='modal-backdrop';
    wrap.innerHTML=`<div class="modal" style="max-width:440px" role="dialog" aria-modal="true">
      <div class="modal-head"><div><h3>${esc(title)}</h3></div></div>
      <div class="modal-body"><p style="font-size:13px;color:var(--text-2)">${esc(message)}</p></div>
      <div class="modal-foot">
        <button type="button" class="btn btn-secondary" data-no>Cancelar</button>
        <button type="button" class="btn ${danger?'btn-danger':''}" data-yes>${esc(confirmText)}</button>
      </div>
    </div>`;
    root.appendChild(wrap);
    const done=(v)=>{ wrap.remove(); resolve(v); };
    wrap.querySelector('[data-no]').onclick=()=>done(false);
    wrap.querySelector('[data-yes]').onclick=()=>done(true);
    wrap.addEventListener('mousedown', e=>{ if(e.target===wrap) done(false); });
  });
}

export function formData(form){
  const out={};
  new FormData(form).forEach((v,k)=>{ out[k]=typeof v==='string'?v.trim():v; });
  return out;
}
export function numVal(form, name, def=0){
  const v=form.elements[name] ? String(form.elements[name].value).replace(',','.') : '';
  const n=Number(v);
  return Number.isFinite(n)?n:def;
}
export function boolVal(form, name){
  const el=form.elements[name];
  return !!(el && el.checked);
}

export function barChart(data, series, {height=230, id=''}={}){
  const W=740, H=height, pad={l:52,r:10,t:12,b:30};
  const pw=W-pad.l-pad.r, ph=H-pad.t-pad.b;
  const rows=data&&data.length?data:[];
  let max=0;
  rows.forEach(r=>series.forEach(s=>{ max=Math.max(max, Number(r[s.key])||0); }));
  max = max<=0?1:max;
  const exp=Math.pow(10, Math.floor(Math.log10(max)));
  const step=Math.ceil(max/exp/2)*exp;
  const niceMax=step*2 || 1;
  const gy=(v)=>pad.t+ph-(v/niceMax)*ph;
  const groupW=rows.length?pw/rows.length:pw;
  const barW=Math.max(3, Math.min(22, (groupW*0.66)/Math.max(series.length,1)));
  let svg=`<svg class="chart" viewBox="0 0 ${W} ${H}" role="img">`;
  for(let i=0;i<=4;i++){
    const v=niceMax*i/4, y=gy(v);
    svg+=`<line class="grid-line" x1="${pad.l}" y1="${y}" x2="${W-pad.r}" y2="${y}"/>`;
    svg+=`<text x="${pad.l-8}" y="${y+3}" text-anchor="end">${compact(v)}</text>`;
  }
  rows.forEach((r,i)=>{
    const gx=pad.l+groupW*i;
    const totalW=barW*series.length+2*(series.length-1);
    const start=gx+(groupW-totalW)/2;
    series.forEach((s,j)=>{
      const v=Math.max(0, Number(r[s.key])||0);
      const h=(v/niceMax)*ph;
      svg+=`<rect class="${s.cls||'bar-rev'}" x="${start+j*(barW+2)}" y="${gy(v)}" width="${barW}" height="${Math.max(h,0)}" rx="2"><title>${esc(s.label)}: ${money(v)}</title></rect>`;
    });
    const every=rows.length>14?3:(rows.length>8?2:1);
    if(i%every===0){
      svg+=`<text x="${gx+groupW/2}" y="${H-9}" text-anchor="middle">${esc(r.label||'')}</text>`;
    }
  });
  svg+='</svg>';
  const legend=`<div class="legend">${series.map(s=>`<span><i style="background:${s.color||'#1d528d'}"></i>${esc(s.label)}</span>`).join('')}</div>`;
  return svg+legend;
}

export function lineChart(data, series, {height=230}={}){
  const W=740, H=height, pad={l:52,r:12,t:12,b:30};
  const pw=W-pad.l-pad.r, ph=H-pad.t-pad.b;
  const rows=data&&data.length?data:[];
  let max=0;
  rows.forEach(r=>series.forEach(s=>{ max=Math.max(max, Number(r[s.key])||0); }));
  max=max<=0?1:max;
  const exp=Math.pow(10, Math.floor(Math.log10(max)));
  const step=Math.ceil(max/exp/2)*exp;
  const niceMax=step*2||1;
  const x=(i)=>pad.l+(rows.length<=1?pw/2:(pw*i)/(rows.length-1));
  const y=(v)=>pad.t+ph-(v/niceMax)*ph;
  let svg=`<svg class="chart" viewBox="0 0 ${W} ${H}" role="img">`;
  for(let i=0;i<=4;i++){
    const v=niceMax*i/4, yy=y(v);
    svg+=`<line class="grid-line" x1="${pad.l}" y1="${yy}" x2="${W-pad.r}" y2="${yy}"/>`;
    svg+=`<text x="${pad.l-8}" y="${yy+3}" text-anchor="end">${compact(v)}</text>`;
  }
  series.forEach(s=>{
    const pts=rows.map((r,i)=>`${x(i)},${y(Number(r[s.key])||0)}`).join(' ');
    svg+=`<polyline class="${s.cls||'line-rev'}" points="${pts}"/>`;
    rows.forEach((r,i)=>{
      svg+=`<circle cx="${x(i)}" cy="${y(Number(r[s.key])||0)}" r="2.5" fill="${s.color||'#1d528d'}"><title>${esc(s.label)}: ${money(r[s.key])}</title></circle>`;
    });
  });
  const every=rows.length>16?5:(rows.length>9?3:1);
  rows.forEach((r,i)=>{
    if(i%every===0) svg+=`<text x="${x(i)}" y="${H-9}" text-anchor="middle">${esc(r.label||'')}</text>`;
  });
  svg+='</svg>';
  const legend=`<div class="legend">${series.map(s=>`<span><i style="background:${s.color||'#1d528d'}"></i>${esc(s.label)}</span>`).join('')}</div>`;
  return svg+legend;
}
