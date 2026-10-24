import { api, qs } from '../api.js';
import { state, canWrite } from '../store.js';
import * as ui from '../ui.js';

let cats = null;

async function loadCats(force=false){
  if (cats && !force) return cats;
  const [vehicles, drivers, guards, routes, schedules] = await Promise.all([
    api.get('/vehicles'),
    api.get('/employees?kind=driver&active=1'),
    api.get('/employees?kind=guard&active=1'),
    api.get('/routes'),
    api.get('/schedules?active=1'),
  ]);
  cats = { vehicles: vehicles.filter(v=>v.active!==false), drivers, guards, routes: routes.filter(r=>r.active!==false), schedules };
  return cats;
}

function defaultRange(){
  const base = (state.latest && state.latest.service_date) || state.today;
  return { from: base.slice(0,7) + '-01', to: base, vehicle: '' };
}

function deduction(s){
  return Number(s.oncology_amount||0)+Number(s.ticket_office_amount||0)+Number(s.mp_amount||0)+Number(s.other_amount||0);
}

function dirBadge(d){
  return d==='vuelta'
    ? '<span class="badge purple">Vuelta</span>'
    : '<span class="badge blue">Ida</span>';
}

function rowHtml(s, canEdit){
  return `<tr>
    <td class="nowrap">${ui.dateDMY(s.service_date)}<div class="sub">${dirBadge(s.direction)}</div></td>
    <td class="nowrap"><strong>${ui.timeHM(s.departure_time)}</strong><div class="sub">${ui.esc(s.schedule_label||'')}</div></td>
    <td><strong>#${ui.esc(s.vehicle_no)}</strong><div class="sub">${ui.esc(s.service_origin||'')} → ${ui.esc(s.service_destination||'')}</div></td>
    <td>${ui.esc(s.driver_name||'—')}<div class="sub">${ui.esc(s.guard_name||'')}</div></td>
    <td class="num">${ui.integer(s.tickets_count)}</td>
    <td class="num">${ui.money(s.revenue)}</td>
    <td class="num">${ui.money(s.fuel_amount)}<div class="sub">${ui.num(s.fuel_liters)} L</div></td>
    <td class="num">${ui.money(deduction(s))}</td>
    <td class="num ${Number(s.surplus)<0?'neg':'pos'}"><strong>${ui.money(s.surplus)}</strong></td>
    <td>${ui.statusBadge(s.status)}</td>
    <td class="sticky-col"><div class="table-actions">
      ${canEdit?`<button class="btn btn-sm btn-secondary btn-icon" data-edit="${s.id}" title="Editar">${ui.icon('edit',14)}</button>
      <button class="btn btn-sm btn-secondary btn-icon" data-close-svc="${s.id}" title="${s.status==='closed'?'Reabrir':'Cerrar'}">${ui.icon(s.status==='closed'?'refresh':'check',14)}</button>
      <button class="btn btn-sm btn-secondary btn-icon" data-del="${s.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}
    </div></td>
  </tr>`;
}

export default {
  title:'Colectivos',
  subtitle:'Libro diario de recaudación de colectivos',
  async render(root){
    const range = defaultRange();
    let c = await loadCats();
    root.innerHTML = `
      <div class="page-head">
        <div><div class="page-title">Colectivos</div><div class="page-sub">Libro diario de recaudación de colectivos</div></div>
        <div class="actions">
          ${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nuevo servicio</button>`:''}
        </div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field"><label>Desde</label><input type="date" id="f-from" value="${range.from}"></div>
          <div class="field"><label>Hasta</label><input type="date" id="f-to" value="${range.to}"></div>
          <div class="field wide"><label>Vehículo</label><select id="f-vehicle"><option value="">Todos</option>${ui.options(c.vehicles,'id',v=>`#${v.internal_no} · ${v.kind==='truck'?'Camión':'Colectivo'}`)}</select></div>
          <div class="field"><label>Dirección</label><select id="f-direction"><option value="">Todas</option><option value="ida">Ida</option><option value="vuelta">Vuelta</option></select></div>
          <div class="field"><label>Estado</label><select id="f-status"><option value="">Todos</option><option value="open">Abiertos</option><option value="closed">Cerrados</option></select></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Horario</th><th>Coche / Recorrido</th><th>Chofer / Guarda</th><th class="num">Boletos</th><th class="num">Recaudación</th><th class="num">Gasoil</th><th class="num">Deducciones</th><th class="num">Sobrante</th><th>Estado</th><th class="sticky-col"></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;

    const tbody = root.querySelector('#tbody');
    const foot = root.querySelector('#foot');

    async function load(){
      ui.loading(tbody, 6);
      try{
        const rows = await api.get('/services' + qs({
          date_from: root.querySelector('#f-from').value,
          date_to: root.querySelector('#f-to').value,
          vehicle_id: root.querySelector('#f-vehicle').value,
          direction: root.querySelector('#f-direction').value,
          status: root.querySelector('#f-status').value,
        }));
        tbody.innerHTML = rows.length ? rows.map(s=>rowHtml(s, canWrite())).join('') : `<tr><td colspan="11">${ui.emptyState('Sin colectivos','No hay colectivos en el rango seleccionado.','bus')}</td></tr>`;
        const tot = rows.reduce((a,s)=>{
          a.rev += Number(s.revenue||0); a.fuel += Number(s.fuel_amount||0); a.ded += deduction(s); a.sur += Number(s.surplus||0); a.tickets += Number(s.tickets_count||0);
          return a;
        },{rev:0,fuel:0,ded:0,sur:0,tickets:0});
        foot.innerHTML = `<div style="display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;font-size:12px">
          <span><b>${rows.length}</b> salidas · <b>${ui.integer(tot.tickets)}</b> boletos</span>
          <span>Recaudación <b>${ui.money(tot.rev)}</b> · Gasoil <b>${ui.money(tot.fuel)}</b> · Deducciones <b>${ui.money(tot.ded)}</b> · Sobrante <b class="${tot.sur<0?'neg':'pos'}">${ui.money(tot.sur)}</b></span>
        </div>`;
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openForm(Number(b.dataset.edit), onSaved));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>removeService(Number(b.dataset.del), onSaved));
        tbody.querySelectorAll('[data-close-svc]').forEach(b=>b.onclick=()=>toggleClose(Number(b.dataset.closeSvc), rows.find(r=>r.id===Number(b.dataset.closeSvc)), onSaved));
      }catch(ex){
        tbody.innerHTML = `<tr><td colspan="11">${ui.emptyState('No se pudo cargar','','alert')}</td></tr>`;
        ui.toast(ex.message,'err');
      }
    }

    ['#f-from','#f-to','#f-vehicle','#f-direction','#f-status'].forEach(sel=>root.querySelector(sel).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    const onSaved = async (date)=>{
      if(date){
        const from=root.querySelector('#f-from'), to=root.querySelector('#f-to');
        if(date < from.value || date > to.value){
          from.value=date.slice(0,7)+'-01';
          to.value=date;
        }
      }
      await load();
    };
    const btnNew=root.querySelector('#btn-new');
    if (btnNew) btnNew.onclick=()=>openForm(null, onSaved);
    await load();
  }
};

async function openForm(id, onDone){
  const c = await loadCats();
  let s = null;
  if (id){
    const detail = await api.get('/services/'+id);
    s = detail.service;
  }
  const isEdit=!!s;
  const d = s || {};
  const body = `
    <div class="section-title">Servicio</div>
    <div class="form-grid cols-3">
      <div class="field full"><label>Programación (opcional)</label><select name="schedule_id"><option value="">— Carga manual —</option>${ui.options(c.schedules,'id',s=>`${s.route_code||''} · ${s.direction==='vuelta'?'Vuelta':'Ida'} ${ui.timeHM(s.departure_time)} · #${s.vehicle_no}`, isEdit?d.schedule_id:'')}</select><div class="help">Al elegir un horario se completan ruta, dirección, coche, chofer, guarda y hora.</div></div>
      <div class="field"><label>Dirección *</label><select name="direction"><option value="ida" ${isEdit&&d.direction==='vuelta'?'':'selected'}>Ida</option><option value="vuelta" ${isEdit&&d.direction==='vuelta'?'selected':''}>Vuelta</option></select></div>
      <div class="field"><label>Fecha *</label><input name="service_date" type="date" value="${isEdit?d.service_date:state.today}" required></div>
      <div class="field"><label>Ruta *</label><select name="route_id" required>${ui.options(c.routes,'id',r=>`${r.code?r.code+' · ':''}${r.origin} → ${r.destination}`, isEdit?d.route_id:'')}</select></div>
      <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(c.vehicles,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`, isEdit?d.vehicle_id:'')}</select></div>
      <div class="field"><label>Chofer</label><select name="driver_id"><option value="">—</option>${ui.options(c.drivers,'id',e=>e.full_name,isEdit?d.driver_id:'')}</select></div>
      <div class="field"><label>Guarda</label><select name="guard_id"><option value="">—</option>${ui.options(c.guards,'id',e=>e.full_name,isEdit?d.guard_id:'')}</select></div>
      <div class="field"><label>Hora de salida</label><input name="departure_time" type="time" value="${isEdit?ui.timeHM(d.departure_time):''}"></div>
      <div class="field"><label>Horario / etiqueta</label><input name="schedule_label" placeholder="IDA 06.50 SJ-PS" value="${ui.esc(d.schedule_label||'')}"></div>
      <div class="field"><label>Km recorridos</label><input name="km" type="number" step="0.01" value="${isEdit?d.km:''}"></div>
      <div class="field"><label>Estado</label><input value="${isEdit?(d.status==='closed'?'Cerrado':'Abierto'):'Abierto'}" disabled></div>
    </div>

    <div id="return-box" style="margin-top:14px;border:1px solid var(--border);border-radius:10px;padding:12px 14px;background:#fbfdff">
      <div style="font-size:12px;font-weight:800;margin-bottom:8px">Vuelta del servicio</div>
      <div class="form-grid cols-3">
        <div class="field"><label>Crear / administrar vuelta</label><label class="check"><input type="checkbox" name="create_return" ${isEdit&&d.return_id?'checked':''}> Sí</label></div>
        <div class="field"><label>Horario de vuelta</label><input name="return_departure_time" type="time" value="${isEdit&&d.return_departure_time?ui.timeHM(d.return_departure_time):''}"></div>
        <div class="field"><label>Vuelta vinculada</label><input value="${isEdit&&d.return_id?'#'+d.return_id+' · '+ui.timeHM(d.return_departure_time):'—'}" disabled></div>
      </div>
      ${isEdit&&d.direction==='vuelta'&&d.outbound_id?`<div class="tiny muted" style="margin-top:6px">Ida vinculada: #${d.outbound_id} · ${ui.timeHM(d.outbound_departure_time)}</div>`:''}
    </div>

    <div class="section-title">Boletos y recaudación</div>
    <div class="form-grid cols-4">
      <div class="field"><label>Boleto desde</label><input name="ticket_from" type="number" value="${isEdit&&d.ticket_from!==null?d.ticket_from:''}"></div>
      <div class="field"><label>Boleto hasta</label><input name="ticket_to" type="number" value="${isEdit&&d.ticket_to!==null?d.ticket_to:''}"></div>
      <div class="field"><label>Recaudación $</label><input name="fare_total" type="number" step="0.01" value="${isEdit?d.revenue:''}"></div>
      <div class="field"><label>Cantidad boletos</label><input value="${isEdit?d.tickets_count:''}" disabled></div>
    </div>

    <div class="section-title">Gasoil y deducciones</div>
    <div class="form-grid cols-4">
      <div class="field"><label>Gasoil $</label><input name="fuel_amount" type="number" step="0.01" value="${isEdit?d.fuel_amount:''}"></div>
      <div class="field"><label>Gasoil litros</label><input name="fuel_liters" type="number" step="0.01" value="${isEdit?d.fuel_liters:''}"></div>
      <div class="field"><label>Oncológico $</label><input name="oncology_amount" type="number" step="0.01" value="${isEdit?d.oncology_amount:''}"></div>
      <div class="field"><label>Boleterías $</label><input name="ticket_office_amount" type="number" step="0.01" value="${isEdit?d.ticket_office_amount:''}"></div>
      <div class="field"><label>Mercado Pago $</label><input name="mp_amount" type="number" step="0.01" value="${isEdit?d.mp_amount:''}"></div>
      <div class="field"><label>Otros $</label><input name="other_amount" type="number" step="0.01" value="${isEdit?d.other_amount:''}"></div>
      <div class="field"><label>Tanque lleno</label><label class="check"><input type="checkbox" name="full_tank" ${isEdit&&d.full_tank?'checked':''}> Sí</label></div>
      <div class="field"><label>Sobrante estimado</label><div id="surplus-preview" style="height:37px;display:flex;align-items:center;font-weight:900;font-size:16px"></div></div>
    </div>

    <div class="section-title">Observaciones</div>
    <div class="field"><textarea name="notes" placeholder="Novedades del servicio, reemplazos, etc.">${ui.esc(d.notes||'')}</textarea></div>`;

  const m = ui.openModal({
    title: isEdit ? 'Editar servicio' : 'Nuevo servicio',
    subtitle: isEdit ? `Servicio #${id} · ${ui.dateDMY(d.service_date)}` : 'Cargue el servicio y su cierre del día.',
    body, wide:true, submitText: isEdit?'Guardar cambios':'Crear servicio',
    onReady(form){
      const calc=()=>{
        const rev=ui.numVal(form,'fare_total'), fuel=ui.numVal(form,'fuel_amount');
        const ded=ui.numVal(form,'oncology_amount')+ui.numVal(form,'ticket_office_amount')+ui.numVal(form,'mp_amount')+ui.numVal(form,'other_amount');
        const v=rev-fuel-ded;
        const el=form.querySelector('#surplus-preview');
        el.textContent=ui.money(v); el.className=v<0?'neg':'pos'; el.style.fontWeight='900';
      };
      form.querySelectorAll('input[type=number]').forEach(i=>i.addEventListener('input',calc));
      const routeSel=form.elements['route_id'];
      routeSel.addEventListener('change',()=>{
        const r=c.routes.find(x=>String(x.id)===String(routeSel.value));
        if (r && !form.elements['km'].value) form.elements['km'].value=r.distance_km;
      });
      const dirSel=form.elements['direction'];
      const retBox=form.querySelector('#return-box');
      const toggleReturn=()=>{ retBox.style.display = dirSel.value==='ida' ? 'block' : 'none'; };
      dirSel.addEventListener('change',toggleReturn);
      const scheduleSel=form.elements['schedule_id'];
      scheduleSel.addEventListener('change',()=>{
        const sc=c.schedules.find(x=>String(x.id)===String(scheduleSel.value));
        if(!sc) return;
        form.elements['route_id'].value=sc.route_id;
        form.elements['direction'].value=sc.direction;
        toggleReturn();
        form.elements['vehicle_id'].value=sc.vehicle_id;
        form.elements['driver_id'].value=sc.driver_id||'';
        form.elements['guard_id'].value=sc.guard_id||'';
        form.elements['departure_time'].value=ui.timeHM(sc.departure_time);
        const route=c.routes.find(r=>String(r.id)===String(sc.route_id));
        if(route) form.elements['km'].value=route.distance_km;
        form.elements['schedule_label'].value=`${sc.direction==='vuelta'?'VUELTA':'IDA'} ${ui.timeHM(sc.departure_time)}`;
      });
      toggleReturn();
      calc();
    },
    async onSubmit(form, close){
      const payload={
        service_date: form.elements.service_date.value,
        route_id: Number(form.elements.route_id.value),
        vehicle_id: Number(form.elements.vehicle_id.value),
        driver_id: form.elements.driver_id.value ? Number(form.elements.driver_id.value) : null,
        guard_id: form.elements.guard_id.value ? Number(form.elements.guard_id.value) : null,
        departure_time: form.elements.departure_time.value || null,
        schedule_label: form.elements.schedule_label.value,
        direction: form.elements.direction.value,
        schedule_id: form.elements.schedule_id.value ? Number(form.elements.schedule_id.value) : null,
        create_return: form.elements.direction.value==='ida' && ui.boolVal(form,'create_return'),
        return_departure_time: form.elements.return_departure_time.value || null,
        km: ui.numVal(form,'km'),
        ticket_from: form.elements.ticket_from.value ? Number(form.elements.ticket_from.value) : null,
        ticket_to: form.elements.ticket_to.value ? Number(form.elements.ticket_to.value) : null,
        fare_total: ui.numVal(form,'fare_total'),
        notes: form.elements.notes.value,
        fuel_amount: ui.numVal(form,'fuel_amount'),
        fuel_liters: ui.numVal(form,'fuel_liters'),
        full_tank: ui.boolVal(form,'full_tank'),
        oncology_amount: ui.numVal(form,'oncology_amount'),
        ticket_office_amount: ui.numVal(form,'ticket_office_amount'),
        mp_amount: ui.numVal(form,'mp_amount'),
        other_amount: ui.numVal(form,'other_amount'),
      };
      if (!payload.service_date || !payload.route_id || !payload.vehicle_id) throw new Error('Complete fecha, ruta y vehículo');
      if (payload.create_return && !payload.return_departure_time) throw new Error('Indique el horario de la vuelta');
      if (isEdit) await api.put('/services/'+id, payload);
      else await api.post('/services', payload);
      ui.toast(isEdit?'Servicio actualizado':'Servicio creado','ok');
      close(); await onDone(payload.service_date);
    }
  });
  return m;
}

async function toggleClose(id, s, onDone){
  if (!s) return;
  if (s.status==='closed'){
    if (!await ui.confirmDialog({title:'Reabrir servicio', message:'El servicio volverá a estado abierto y se eliminará el cierre registrado.', confirmText:'Reabrir', danger:false})) return;
    try{ await api.post('/services/'+id+'/reopen',{}); ui.toast('Servicio reabierto','ok'); await onDone(); }
    catch(ex){ ui.toast(ex.message,'err'); }
    return;
  }
  ui.openModal({
    title:'Cerrar servicio',
    subtitle:`${ui.dateDMY(s.service_date)} · Coche #${s.vehicle_no} · ${ui.timeHM(s.departure_time)}`,
    submitText:'Cerrar servicio',
    body:`
      <div class="form-grid cols-2">
        <div class="field"><label>Recaudación</label><input value="${ui.money(s.revenue)}" disabled></div>
        <div class="field"><label>Sobrante calculado</label><input value="${ui.money(s.surplus)}" disabled></div>
        <div class="field"><label>Efectivo entregado</label><input name="cash_delivered" type="number" step="0.01" value="${s.surplus}"></div>
        <div class="field"><label>Diferencia</label><div id="diff" style="height:37px;display:flex;align-items:center;font-weight:900"></div></div>
      </div>
      <div class="field" style="margin-top:12px"><label>Observaciones</label><textarea name="notes" placeholder="Detalle del cierre, faltante, etc."></textarea></div>`,
    onReady(form){
      const calc=()=>{
        const v=ui.numVal(form,'cash_delivered')-Number(s.surplus||0);
        const el=form.querySelector('#diff'); el.textContent=ui.money(v); el.className=v<0?'neg':'pos';
      };
      form.elements.cash_delivered.addEventListener('input',calc); calc();
    },
    async onSubmit(form, close){
      await api.post('/services/'+id+'/close', { cash_delivered: ui.numVal(form,'cash_delivered'), notes: form.elements.notes.value });
      ui.toast('Servicio cerrado','ok'); close(); await onDone();
    }
  });
}

async function removeService(id, onDone){
  if (!await ui.confirmDialog({title:'Eliminar servicio', message:'Se eliminará el servicio, su combustible y sus gastos asociados. Esta acción no se puede deshacer.', confirmText:'Eliminar'})) return;
  try{ await api.del('/services/'+id); ui.toast('Servicio eliminado','ok'); await onDone(); }
  catch(ex){ ui.toast(ex.message,'err'); }
}

