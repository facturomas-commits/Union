import { api, ApiError } from './api.js';
import { state, canWrite, isAdmin, isSuper } from './store.js';
import { icon, initials, roleLabel, toast, openModal, formData } from './ui.js';
import { renderLogin } from './views/login.js';

import dashboard from './views/dashboard.js';
import services from './views/services.js';
import fuel from './views/fuel.js';
import expenses from './views/expenses.js';
import maintenance from './views/maintenance.js';
import freight from './views/freight.js';
import reports from './views/reports.js';
import masters from './views/masters.js';
import audit from './views/audit.js';

const views = { dashboard, services, fuel, expenses, maintenance, freight, reports, masters, audit };

const NAV = [
  { group:'Operación', items:[
    { id:'dashboard', label:'Dashboard', icon:'dashboard' },
    { id:'services', label:'Servicios', icon:'bus' },
    { id:'fuel', label:'Combustible', icon:'fuel' },
    { id:'expenses', label:'Gastos', icon:'receipt' },
    { id:'freight', label:'Camión', icon:'truck' },
  ]},
  { group:'Flota', items:[
    { id:'maintenance', label:'Mantenimiento', icon:'wrench' },
    { id:'masters', label:'Maestros', icon:'settings' },
  ]},
  { group:'Análisis', items:[
    { id:'reports', label:'Reportes', icon:'chart' },
    { id:'audit', label:'Auditoría', icon:'audit', admin:true },
  ]},
];

function navHtml(current){
  return NAV.map(g=>{
    const items=g.items.filter(it=>!it.admin || isAdmin());
    if (!items.length) return '';
    return `<div class="nav-group">${g.group}</div>` + items.map(it=>{
      const active = it.id===current ? ' active' : '';
      return `<a class="nav-item${active}" href="#/${it.id}">${icon(it.icon)}<span>${it.label}</span></a>`;
    }).join('');
  }).join('');
}

function shell(current){
  const u=state.user||{};
  const c=state.company||{};
  return `
  <div class="app">
    <aside class="sidebar">
      <div class="sidebar-brand">
        <div class="mark">U</div>
        <div><div class="name">UNIÓN</div><div class="sub">GESTIÓN DE TRANSPORTE</div></div>
      </div>
      <nav class="nav" id="nav">${navHtml(current)}</nav>
      <div class="sidebar-user">
        <div class="avatar">${initials(u.full_name)}</div>
        <div class="who"><strong>${u.full_name||''}</strong><span>${roleLabel(u.role)}</span></div>
        <button class="icon-btn" id="btn-logout" title="Salir">${icon('logout')}</button>
      </div>
    </aside>
    <div class="main">
      <header class="topbar">
        <div class="topbar-left">
          <div>
            <div class="topbar-title" id="ptitle">—</div>
            <div class="topbar-sub" id="psub">—</div>
          </div>
        </div>
        <div class="topbar-right">
          <span class="pill"><span class="dot"></span>${c.name || 'Empresa'}</span>
          <span class="pill">${new Date().toLocaleDateString('es-AR',{day:'2-digit',month:'short',year:'numeric'})}</span>
          ${u.must_change_password ? `<button class="btn btn-sm btn-secondary" id="btn-pass">${icon('lock')} Cambiar clave</button>` : ''}
          <button class="icon-btn" id="btn-refresh" title="Actualizar" style="color:var(--muted)">${icon('refresh')}</button>
        </div>
      </header>
      <main class="content" id="view"></main>
    </div>
  </div>`;
}

function currentRoute(){
  const raw = (location.hash || '#/dashboard').replace(/^#\/?/, '');
  const [path] = raw.split('?');
  const id = path || 'dashboard';
  return views[id] ? id : 'dashboard';
}

async function renderCurrent(){
  const app=document.getElementById('app');
  const id=currentRoute();
  if (!app.querySelector('.app')){
    app.innerHTML=shell(id);
    bindShell();
  } else {
    document.getElementById('nav').innerHTML=navHtml(id);
  }
  const view=views[id];
  document.getElementById('ptitle').textContent=view.title || id;
  document.getElementById('psub').textContent=view.subtitle || '';
  document.title=`${view.title || 'UNIÓN'} · UNION`;
  const content=document.getElementById('view');
  content.innerHTML='';
  try{
    await view.render(content);
  }catch(ex){
    if (ex instanceof ApiError && ex.unauthorized){ showLogin(); return; }
    content.innerHTML=`<div class="card"><div class="empty"><strong>No se pudo cargar la vista</strong><span>${ex.message||ex}</span></div></div>`;
    toast(ex.message||'Error cargando la vista','err');
  }
  window.scrollTo({top:0,behavior:'instant'});
}

function bindShell(){
  document.getElementById('btn-logout').onclick=async()=>{
    try{ await api.logout(); }catch(e){}
    showLogin();
  };
  const refresh=document.getElementById('btn-refresh');
  if (refresh) refresh.onclick=()=>renderCurrent();
  const pass=document.getElementById('btn-pass');
  if (pass) pass.onclick=changePassword;
}

function changePassword(){
  openModal({
    title:'Cambiar contraseña',
    subtitle:'Mínimo 8 caracteres.',
    submitText:'Actualizar',
    body:`
      <div class="field"><label>Contraseña actual</label><input name="current_password" type="password" required></div>
      <div class="field" style="margin-top:12px"><label>Nueva contraseña</label><input name="new_password" type="password" minlength="8" required></div>
      <div class="field" style="margin-top:12px"><label>Repetir nueva contraseña</label><input name="repeat_password" type="password" minlength="8" required></div>`,
    onSubmit: async (form, close)=>{
      const d=formData(form);
      if (d.new_password !== d.repeat_password) throw new Error('Las contraseñas no coinciden');
      await api.post('/auth/change-password', { current_password:d.current_password, new_password:d.new_password });
      state.user.must_change_password=false;
      toast('Contraseña actualizada','ok');
      close();
      renderCurrent();
    }
  });
}

function showLogin(){
  if (document.querySelector('#login-form')) return;
  state.user=null; state.company=null; state.settings={};
  const app=document.getElementById('app');
  renderLogin(app, async (data)=>{
    await loadSession(data);
    if (!location.hash) history.replaceState(null,'','#/dashboard');
    await renderCurrent();
  });
}

async function loadSession(loginData){
  try{
    const me=await api.me();
    state.user=me.user;
    state.company=me.company;
    state.settings=me.settings||{};
  }catch(e){
    if (loginData && loginData.user){
      state.user=loginData.user;
      state.company={name:'Empresa'};
      state.settings={};
    } else throw e;
  }
  try{
    state.latest=await api.latest();
  }catch(e){ state.latest=null; }
}

async function boot(){
  try{
    const me=await api.me();
    state.user=me.user;
    state.company=me.company;
    state.settings=me.settings||{};
    try{ state.latest=await api.latest(); }catch(e){ state.latest=null; }
    if (!location.hash) history.replaceState(null,'','#/dashboard');
    await renderCurrent();
  }catch(ex){
    if (ex instanceof ApiError && ex.unauthorized){ showLogin(); return; }
    document.getElementById('app').innerHTML=`<div class="card" style="max-width:620px;margin:60px auto"><div class="empty"><strong>No se pudo iniciar el sistema</strong><span>${ex.message||ex}</span><br><br><button class="btn" onclick="location.reload()">Reintentar</button></div></div>`;
  }
}

window.addEventListener('hashchange', ()=>{ if (state.user) renderCurrent(); });
window.addEventListener('union:unauthorized', ()=>showLogin());
boot();
