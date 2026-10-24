import { api } from '../api.js';
import { state, canWrite, isAdmin, isSuper, hasModule } from '../store.js';
import { MODULES, defaultModules, defaultFinancials } from '../modules.js';
import * as ui from '../ui.js';

const TABS=[
  {id:'vehicles',label:'Vehículos',module:'masters'},
  {id:'employees',label:'Empleados',module:'masters'},
  {id:'routes',label:'Rutas',module:'masters'},
  {id:'workshops',label:'Talleres',module:'masters'},
  {id:'users',label:'Usuarios',module:'users',admin:true},
  {id:'settings',label:'Configuración',module:'settings',admin:true},
];

export default {
  title:'Maestros',
  subtitle:'Vehículos, empleados, rutas y configuración',
  async render(root){
    let tab='vehicles';
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Maestros</div><div class="page-sub">Vehículos, empleados, rutas y configuración</div></div>
        <div class="actions" id="tab-actions"></div>
      </div>
      <div class="card">
        <div class="tabs" id="tabs">${TABS.filter(t=>hasModule(t.module) && (!t.admin||isAdmin())).map(t=>`<button class="tab ${t.id===tab?'active':''}" data-tab="${t.id}">${t.label}</button>`).join('')}</div>
        <div id="pane"></div>
      </div>`;
    const pane=root.querySelector('#pane');
    const actions=root.querySelector('#tab-actions');

    async function show(id){
      tab=id;
      root.querySelectorAll('#tabs .tab').forEach(b=>b.classList.toggle('active',b.dataset.tab===id));
      actions.innerHTML='';
      pane.innerHTML='<div class="loading"><div class="skeleton" style="width:60%"></div><div class="skeleton" style="width:80%"></div></div>';
      try{
        if(id==='vehicles') await vehiclesTab(pane,actions,()=>show('vehicles'));
        else if(id==='employees') await employeesTab(pane,actions,()=>show('employees'));
        else if(id==='routes') await routesTab(pane,actions,()=>show('routes'));
        else if(id==='workshops') await workshopsTab(pane,actions,()=>show('workshops'));
        else if(id==='users') await usersTab(pane,actions,()=>show('users'));
        else if(id==='settings') await settingsTab(pane,actions);
      }catch(ex){
        pane.innerHTML=`<div class="empty"><strong>No se pudo cargar</strong><span>${ui.esc(ex.message)}</span></div>`;
      }
    }
    root.querySelectorAll('#tabs .tab').forEach(b=>b.onclick=()=>show(b.dataset.tab));
    await show(tab);
  }
};

/* ---------------- Vehículos ---------------- */
async function vehiclesTab(pane,actions,reload){
  const rows=await api.get('/vehicles');
  if(canWrite()) actions.innerHTML=`<button class="btn" id="add">${ui.icon('plus')} Nuevo vehículo</button>`;
  pane.innerHTML=`<div class="table-wrap"><table class="data">
    <thead><tr><th>#</th><th>Tipo</th><th>Patente</th><th>Modelo</th><th class="num">Año</th><th class="num">Asientos</th><th class="num">Odómetro</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(v=>`<tr>
      <td><strong>${ui.esc(v.internal_no)}</strong></td>
      <td><span class="badge ${v.kind==='truck'?'purple':'blue'}">${v.kind==='truck'?'Camión':(v.kind==='bus'?'Colectivo':'Otro')}</span></td>
      <td>${ui.esc(v.plate||'—')}</td>
      <td>${ui.esc(v.model||'—')}</td>
      <td class="num">${v.model_year||'—'}</td>
      <td class="num">${v.seats||'—'}</td>
      <td class="num">${ui.integer(v.odometer)}</td>
      <td>${v.active?'<span class="badge green">Activo</span>':'<span class="badge gray">Inactivo</span>'}</td>
      <td><div class="table-actions">${canWrite()?`
        <button class="btn btn-sm btn-secondary btn-icon" data-edit="${v.id}" title="Editar">${ui.icon('edit',14)}</button>
        <button class="btn btn-sm btn-secondary btn-icon" data-del="${v.id}" title="Desactivar">${ui.icon('trash',14)}</button>`:''}</div></td>
    </tr>`).join(''):`<tr><td colspan="9">${ui.emptyState('Sin vehículos','Cree el primer vehículo.','bus')}</td></tr>`}</tbody>
  </table></div>`;
  const add=pane.querySelector('#add')||actions.querySelector('#add');
  if(canWrite()) actions.querySelector('#add').onclick=()=>vehicleForm(null,reload);
  pane.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>vehicleForm(rows.find(v=>v.id===Number(b.dataset.edit)),reload));
  pane.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>softDelete('vehicles',b.dataset.del,reload,'Desactivar vehículo','El vehículo quedará inactivo y no aparecerá en los formularios.'));
}

function vehicleForm(v,reload){
  const isEdit=!!v, d=v||{};
  ui.openModal({
    title:isEdit?'Editar vehículo':'Nuevo vehículo',
    body:`<div class="form-grid cols-2">
      <div class="field"><label>Tipo *</label><select name="kind"><option value="bus" ${d.kind==='bus'?'selected':''}>Colectivo</option><option value="truck" ${d.kind==='truck'?'selected':''}>Camión</option><option value="other" ${d.kind==='other'?'selected':''}>Otro</option></select></div>
      <div class="field"><label>N° interno *</label><input name="internal_no" value="${ui.esc(d.internal_no||'')}" required></div>
      <div class="field"><label>Patente</label><input name="plate" value="${ui.esc(d.plate||'')}"></div>
      <div class="field"><label>Modelo</label><input name="model" value="${ui.esc(d.model||'')}"></div>
      <div class="field"><label>Año</label><input name="model_year" type="number" value="${d.model_year||''}"></div>
      <div class="field"><label>Asientos</label><input name="seats" type="number" value="${d.seats||''}"></div>
      <div class="field"><label>Capacidad kg</label><input name="capacity_kg" type="number" step="0.01" value="${d.capacity_kg||''}"></div>
      <div class="field"><label>Odómetro</label><input name="odometer" type="number" step="0.1" value="${d.odometer||0}"></div>
      <div class="field full"><label>Notas</label><input name="notes" value="${ui.esc(d.notes||'')}"></div>
      <div class="field"><label>Activo</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
    </div>`,
    async onSubmit(form,close){
      const p={kind:form.elements.kind.value,internal_no:form.elements.internal_no.value,plate:form.elements.plate.value,
        model:form.elements.model.value,model_year:ui.numVal(form,'model_year')||null,seats:ui.numVal(form,'seats')||null,
        capacity_kg:form.elements.capacity_kg.value?ui.numVal(form,'capacity_kg'):null,odometer:ui.numVal(form,'odometer'),
        notes:form.elements.notes.value,active:ui.boolVal(form,'active')};
      if(!p.internal_no) throw new Error('Ingrese el número interno');
      if(isEdit) await api.put('/vehicles/'+v.id,p); else await api.post('/vehicles',p);
      ui.toast(isEdit?'Vehículo actualizado':'Vehículo creado','ok'); close(); await reload();
    }
  });
}

/* ---------------- Empleados ---------------- */
async function employeesTab(pane,actions,reload){
  const rows=await api.get('/employees');
  if(canWrite()) actions.innerHTML=`<button class="btn" id="add">${ui.icon('plus')} Nuevo empleado</button>`;
  pane.innerHTML=`<div class="table-wrap"><table class="data">
    <thead><tr><th>Nombre</th><th>DNI</th><th>Tipo</th><th>Licencia</th><th>Teléfono</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(e=>`<tr>
      <td><strong>${ui.esc(e.full_name)}</strong></td><td>${ui.esc(e.dni||'—')}</td>
      <td><span class="badge ${e.kind==='driver'?'blue':(e.kind==='guard'?'purple':'gray')}">${e.kind==='driver'?'Chofer':(e.kind==='guard'?'Guarda':'Otro')}</span></td>
      <td>${ui.esc(e.license||'—')}</td><td>${ui.esc(e.phone||'—')}</td>
      <td>${e.active?'<span class="badge green">Activo</span>':'<span class="badge gray">Inactivo</span>'}</td>
      <td><div class="table-actions">${canWrite()?`
        <button class="btn btn-sm btn-secondary btn-icon" data-edit="${e.id}">${ui.icon('edit',14)}</button>
        <button class="btn btn-sm btn-secondary btn-icon" data-del="${e.id}">${ui.icon('trash',14)}</button>`:''}</div></td>
    </tr>`).join(''):`<tr><td colspan="7">${ui.emptyState('Sin empleados','Cree el primer chofer o guarda.','users')}</td></tr>`}</tbody>
  </table></div>`;
  if(canWrite()) actions.querySelector('#add').onclick=()=>employeeForm(null,reload);
  pane.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>employeeForm(rows.find(e=>e.id===Number(b.dataset.edit)),reload));
  pane.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>softDelete('employees',b.dataset.del,reload,'Desactivar empleado','El empleado quedará inactivo.'));
}

function employeeForm(e,reload){
  const isEdit=!!e,d=e||{};
  ui.openModal({
    title:isEdit?'Editar empleado':'Nuevo empleado',
    body:`<div class="form-grid cols-2">
      <div class="field full"><label>Nombre completo *</label><input name="full_name" value="${ui.esc(d.full_name||'')}" required></div>
      <div class="field"><label>DNI</label><input name="dni" value="${ui.esc(d.dni||'')}"></div>
      <div class="field"><label>Tipo *</label><select name="kind"><option value="driver" ${d.kind==='driver'?'selected':''}>Chofer</option><option value="guard" ${d.kind==='guard'?'selected':''}>Guarda</option><option value="other" ${d.kind==='other'?'selected':''}>Otro</option></select></div>
      <div class="field"><label>Licencia</label><input name="license" value="${ui.esc(d.license||'')}"></div>
      <div class="field"><label>Teléfono</label><input name="phone" value="${ui.esc(d.phone||'')}"></div>
      <div class="field"><label>Domicilio</label><input name="address" value="${ui.esc(d.address||'')}"></div>
      <div class="field"><label>Fecha de ingreso</label><input name="hire_date" type="date" value="${d.hire_date||''}"></div>
      <div class="field"><label>Activo</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
    </div>`,
    async onSubmit(form,close){
      const p={full_name:form.elements.full_name.value,dni:form.elements.dni.value,kind:form.elements.kind.value,
        license:form.elements.license.value,phone:form.elements.phone.value,address:form.elements.address.value,
        hire_date:form.elements.hire_date.value||null,active:ui.boolVal(form,'active')};
      if(!p.full_name) throw new Error('Ingrese el nombre');
      if(isEdit) await api.put('/employees/'+e.id,p); else await api.post('/employees',p);
      ui.toast(isEdit?'Empleado actualizado':'Empleado creado','ok'); close(); await reload();
    }
  });
}

/* ---------------- Rutas ---------------- */
async function routesTab(pane,actions,reload){
  const rows=await api.get('/routes');
  if(canWrite()) actions.innerHTML=`<button class="btn" id="add">${ui.icon('plus')} Nueva ruta</button>`;
  pane.innerHTML=`<div class="table-wrap"><table class="data">
    <thead><tr><th>Código</th><th>Nombre</th><th>Recorrido</th><th class="num">Km</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(r=>`<tr>
      <td><strong>${ui.esc(r.code||'—')}</strong></td><td>${ui.esc(r.name)}</td>
      <td>${ui.esc(r.origin)} → ${ui.esc(r.destination)}</td><td class="num">${ui.integer(r.distance_km)}</td>
      <td>${r.active?'<span class="badge green">Activa</span>':'<span class="badge gray">Inactiva</span>'}</td>
      <td><div class="table-actions">${canWrite()?`
        <button class="btn btn-sm btn-secondary btn-icon" data-edit="${r.id}">${ui.icon('edit',14)}</button>
        <button class="btn btn-sm btn-secondary btn-icon" data-del="${r.id}">${ui.icon('trash',14)}</button>`:''}</div></td>
    </tr>`).join(''):`<tr><td colspan="6">${ui.emptyState('Sin rutas','Cree la primera ruta.','route')}</td></tr>`}</tbody>
  </table></div>`;
  if(canWrite()) actions.querySelector('#add').onclick=()=>routeForm(null,reload);
  pane.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>routeForm(rows.find(r=>r.id===Number(b.dataset.edit)),reload));
  pane.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>softDelete('routes',b.dataset.del,reload,'Desactivar ruta','La ruta quedará inactiva.'));
}

function routeForm(r,reload){
  const isEdit=!!r,d=r||{};
  ui.openModal({
    title:isEdit?'Editar ruta':'Nueva ruta',
    body:`<div class="form-grid cols-2">
      <div class="field"><label>Código</label><input name="code" value="${ui.esc(d.code||'')}" placeholder="SJ-PS"></div>
      <div class="field"><label>Nombre *</label><input name="name" value="${ui.esc(d.name||'')}" required></div>
      <div class="field"><label>Origen *</label><input name="origin" value="${ui.esc(d.origin||'')}" required></div>
      <div class="field"><label>Destino *</label><input name="destination" value="${ui.esc(d.destination||'')}" required></div>
      <div class="field"><label>Distancia km</label><input name="distance_km" type="number" step="0.01" value="${d.distance_km||''}"></div>
      <div class="field"><label>Activa</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
    </div>`,
    async onSubmit(form,close){
      const p={code:form.elements.code.value,name:form.elements.name.value,origin:form.elements.origin.value,
        destination:form.elements.destination.value,distance_km:ui.numVal(form,'distance_km'),active:ui.boolVal(form,'active')};
      if(!p.name||!p.origin||!p.destination) throw new Error('Complete nombre, origen y destino');
      if(isEdit) await api.put('/routes/'+r.id,p); else await api.post('/routes',p);
      ui.toast(isEdit?'Ruta actualizada':'Ruta creada','ok'); close(); await reload();
    }
  });
}

/* ---------------- Talleres ---------------- */
async function workshopsTab(pane,actions,reload){
  const rows=await api.get('/workshops');
  if(canWrite()) actions.innerHTML=`<button class="btn" id="add">${ui.icon('plus')} Nuevo taller</button>`;
  pane.innerHTML=`<div class="table-wrap"><table class="data">
    <thead><tr><th>Taller</th><th>Teléfono</th><th>Dirección</th><th>Notas</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.length?rows.map(w=>`<tr>
      <td><strong>${ui.esc(w.name)}</strong></td>
      <td>${w.phone?ui.phoneLink(w.phone):'<span class="muted">—</span>'}</td>
      <td>${ui.esc(w.address||'—')}</td>
      <td>${ui.esc(w.notes||'—')}</td>
      <td>${w.active?'<span class="badge green">Activo</span>':'<span class="badge gray">Inactivo</span>'}</td>
      <td><div class="table-actions">${canWrite()?`
        <button class="btn btn-sm btn-secondary btn-icon" data-edit="${w.id}" title="Editar">${ui.icon('edit',14)}</button>
        <button class="btn btn-sm btn-secondary btn-icon" data-del="${w.id}" title="Desactivar">${ui.icon('trash',14)}</button>`:''}</div></td>
    </tr>`).join(''):`<tr><td colspan="6">${ui.emptyState('Sin talleres','Cargue el taller o proveedor donde se hacen los servicios.','wrench')}</td></tr>`}</tbody>
  </table></div>`;
  if(canWrite()) actions.querySelector('#add').onclick=()=>workshopForm(null,reload);
  pane.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>workshopForm(rows.find(w=>w.id===Number(b.dataset.edit)),reload));
  pane.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>softDelete('workshops',b.dataset.del,reload,'Desactivar taller','El taller quedará inactivo y no aparecerá en el formulario de mantenimiento.'));
}

function workshopForm(w,reload){
  const isEdit=!!w,d=w||{};
  ui.openModal({
    title:isEdit?'Editar taller':'Nuevo taller',
    subtitle:'Datos de contacto para llamar rápido desde mantenimiento.',
    body:`<div class="form-grid cols-2">
      <div class="field full"><label>Nombre del taller / proveedor *</label><input name="name" value="${ui.esc(d.name||'')}" required></div>
      <div class="field"><label>Teléfono</label><input name="phone" value="${ui.esc(d.phone||'')}" placeholder="Ej: 3764 123456"></div>
      <div class="field"><label>Dirección</label><input name="address" value="${ui.esc(d.address||'')}"></div>
      <div class="field full"><label>Notas</label><textarea name="notes">${ui.esc(d.notes||'')}</textarea></div>
      <div class="field"><label>Activo</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
    </div>`,
    async onSubmit(form,close){
      const p={name:form.elements.name.value,phone:form.elements.phone.value,address:form.elements.address.value,
        notes:form.elements.notes.value,active:ui.boolVal(form,'active')};
      if(!p.name) throw new Error('Ingrese el nombre del taller');
      if(isEdit) await api.put('/workshops/'+w.id,p); else await api.post('/workshops',p);
      ui.toast(isEdit?'Taller actualizado':'Taller creado','ok'); close(); await reload();
    }
  });
}

/* ---------------- Usuarios ---------------- */
async function usersTab(pane,actions,reload){
  const rows=await api.get('/users');
  actions.innerHTML=`<button class="btn" id="add">${ui.icon('plus')} Nuevo usuario</button>`;
  pane.innerHTML=`<div class="table-wrap"><table class="data">
    <thead><tr><th>Usuario</th><th>Nombre</th><th>Rol</th><th>Módulos</th><th>Importes</th><th>Email</th><th>Último ingreso</th><th>Estado</th><th></th></tr></thead>
    <tbody>${rows.map(u=>`<tr>
      <td><strong>${ui.esc(u.username)}</strong></td><td>${ui.esc(u.full_name)}</td>
      <td><span class="badge ${u.role==='viewer'?'gray':(u.role==='operator'?'blue':'purple')}">${ui.roleLabel(u.role)}</span></td>
      <td>${Array.isArray(u.allowed_modules)?`<span class="badge blue">${u.allowed_modules.length} módulos</span>`:'<span class="badge gray">Según rol</span>'}</td>
      <td>${(u.can_view_financials ?? defaultFinancials(u.role))?'<span class="badge green">Sí</span>':'<span class="badge gray">No</span>'}</td>
      <td>${ui.esc(u.email||'—')}</td><td>${u.last_login?ui.dateTime(u.last_login):'—'}</td>
      <td>${u.active?'<span class="badge green">Activo</span>':'<span class="badge gray">Inactivo</span>'}</td>
      <td><div class="table-actions">
        <button class="btn btn-sm btn-secondary btn-icon" data-edit="${u.id}">${ui.icon('edit',14)}</button>
        <button class="btn btn-sm btn-secondary btn-icon" data-del="${u.id}">${ui.icon('trash',14)}</button>
      </div></td>
    </tr>`).join('')}</tbody>
  </table></div>`;
  actions.querySelector('#add').onclick=()=>userForm(null,reload);
  pane.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>userForm(rows.find(u=>u.id===Number(b.dataset.edit)),reload));
  pane.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>softDelete('users',b.dataset.del,reload,'Desactivar usuario','El usuario no podrá ingresar al sistema.'));
}

function userForm(u,reload){
  const isEdit=!!u,d=u||{};
  const roles=[['operator','Operador'],['supervisor','Supervisor'],['admin','Administrador'],['viewer','Consulta']];
  if(isSuper()) roles.push(['superadmin','Superadmin']);
  const selected=Array.isArray(d.allowed_modules)?d.allowed_modules:defaultModules(d.role||'operator');
  const financial=(d.can_view_financials ?? defaultFinancials(d.role||'operator'));
  ui.openModal({
    title:isEdit?'Editar usuario':'Nuevo usuario',
    subtitle:isEdit?'Deje la contraseña vacía para conservarla.':'La contraseña es obligatoria.',
    body:`<div class="form-grid cols-2">
      <div class="field"><label>Usuario *</label><input name="username" value="${ui.esc(d.username||'')}" ${isEdit?'disabled':''} required></div>
      <div class="field"><label>Nombre completo *</label><input name="full_name" value="${ui.esc(d.full_name||'')}" required></div>
      <div class="field"><label>Email</label><input name="email" type="email" value="${ui.esc(d.email||'')}"></div>
      <div class="field"><label>Rol *</label><select name="role">${roles.map(([v,l])=>`<option value="${v}" ${d.role===v?'selected':''}>${l}</option>`).join('')}</select></div>
      <div class="field"><label>Contraseña ${isEdit?'(opcional)':'*'}</label><input name="password" type="password" minlength="8" ${isEdit?'':'required'}></div>
      <div class="field"><label>Activo</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
      <div class="field"><label>Cambiar clave al ingresar</label><label class="check"><input type="checkbox" name="must_change_password" ${d.must_change_password?'checked':''}> Sí</label></div>
      <div class="field full"><label>Importes y recaudación</label><label class="check"><input type="checkbox" name="can_view_financials" ${financial?'checked':''}> Ver importes, recaudación y reportes</label><div class="help">Si está desmarcado, el usuario opera sin ver montos ni totales. Los reportes quedan bloqueados.</div></div>
      <div class="field full"><label>Módulos permitidos</label>
        <div class="module-grid" id="module-grid">
          ${MODULES.map(m=>`<label class="check"><input type="checkbox" name="module" value="${m.id}" ${selected.includes(m.id)?'checked':''}> ${m.label}</label>`).join('')}
        </div>
        <div class="help">Los módulos no tildados no aparecen en el menú y la API los bloquea. <button type="button" class="btn btn-sm btn-secondary" id="reset-modules" style="margin-top:6px">Restablecer según rol</button></div>
      </div>
    </div>`,
    onReady(form){
      const setModules=(role)=>{
        form.querySelectorAll('input[name=module]').forEach(x=>{ x.checked=defaultModules(role).includes(x.value); });
        form.elements.can_view_financials.checked=defaultFinancials(role);
      };
      form.querySelector('#reset-modules').onclick=()=>setModules(form.elements.role.value);
      form.elements.role.addEventListener('change',()=>{ if(!isEdit) setModules(form.elements.role.value); else form.elements.can_view_financials.checked=defaultFinancials(form.elements.role.value); });
    },
    async onSubmit(form,close){
      const p={full_name:form.elements.full_name.value,email:form.elements.email.value,role:form.elements.role.value,
        active:ui.boolVal(form,'active'),must_change_password:ui.boolVal(form,'must_change_password'),
        can_view_financials:ui.boolVal(form,'can_view_financials'),
        allowed_modules:[...form.querySelectorAll('input[name=module]:checked')].map(x=>x.value)};
      const pass=form.elements.password.value;
      if(!p.full_name) throw new Error('Ingrese el nombre');
      if(!isEdit){ p.username=form.elements.username.value; if(!p.username) throw new Error('Ingrese el usuario'); }
      if(pass) p.password=pass; else if(!isEdit) throw new Error('Ingrese la contraseña');
      if(isEdit) await api.put('/users/'+u.id,p); else await api.post('/users',p);
      ui.toast(isEdit?'Usuario actualizado':'Usuario creado','ok'); close(); await reload();
    }
  });
}

/* ---------------- Configuración ---------------- */
async function settingsTab(pane,actions){
  const s=state.settings||{};
  pane.innerHTML=`<div class="card-body">
    <div class="section-title">Parámetros del sistema</div>
    <form id="settings-form">
      <div class="form-grid cols-2">
        <div class="field"><label>Días de alerta de mantenimiento</label><input name="maintenance_alert_days" type="number" min="0" value="${ui.esc(s.maintenance_alert_days||'15')}"></div>
        <div class="field"><label>IVA %</label><input name="vat_pct" type="number" step="0.01" value="${ui.esc(s.vat_pct||'21')}"></div>
        <div class="field"><label>Comisión chofer %</label><input name="commission_pct" type="number" step="0.01" value="${ui.esc(s.commission_pct||'15')}"></div>
        <div class="field"><label>Nombre comercial</label><input name="company_display_name" value="${ui.esc(s.company_display_name||'Empresa Unión')}"></div>
      </div>
      <div class="form-actions"><button class="btn" type="submit">Guardar configuración</button></div>
    </form>
    <div class="section-title" style="margin-top:26px">Empresa</div>
    <div class="form-grid cols-2">
      <div class="field"><label>Razón social</label><input value="${ui.esc(state.company?.legal_name||'')}" disabled></div>
      <div class="field"><label>CUIT</label><input value="${ui.esc(state.company?.cuit||'')}" disabled></div>
      <div class="field"><label>Nombre</label><input value="${ui.esc(state.company?.name||'')}" disabled></div>
      <div class="field"><label>Domicilio</label><input value="${ui.esc(state.company?.address||'')}" disabled></div>
    </div>
    <div class="tiny muted" style="margin-top:10px">Para editar los datos de la empresa contacte al superadministrador.</div>
  </div>`;
  pane.querySelector('#settings-form').onsubmit=async(e)=>{
    e.preventDefault();
    const form=e.target;
    const payload={
      maintenance_alert_days:form.elements.maintenance_alert_days.value,
      vat_pct:form.elements.vat_pct.value,
      commission_pct:form.elements.commission_pct.value,
      company_display_name:form.elements.company_display_name.value,
    };
    try{
      await api.put('/settings',payload);
      state.settings={...state.settings,...payload};
      ui.toast('Configuración guardada','ok');
    }catch(ex){ ui.toast(ex.message,'err'); }
  };
}

/* ---------------- Común ---------------- */
async function softDelete(entity,id,reload,title,message){
  if(!await ui.confirmDialog({title,message,confirmText:'Desactivar'})) return;
  try{ await api.del('/'+entity+'/'+id); ui.toast('Registro desactivado','ok'); await reload(); }catch(ex){ ui.toast(ex.message,'err'); }
}
