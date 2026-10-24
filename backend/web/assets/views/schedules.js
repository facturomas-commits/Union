import { api, qs } from '../api.js';
import { state, canWrite } from '../store.js';
import * as ui from '../ui.js';

let catsCache=null;
async function catalogs(){
  if(catsCache) return catsCache;
  const [routes, vehicles, drivers, guards] = await Promise.all([
    api.get('/routes'),
    api.get('/vehicles'),
    api.get('/employees?kind=driver&active=1'),
    api.get('/employees?kind=guard&active=1'),
  ]);
  catsCache={
    routes:routes.filter(r=>r.active!==false),
    vehicles:vehicles.filter(v=>v.active!==false),
    drivers,
    guards,
  };
  return catsCache;
}

function dirBadge(d){
  return d==='vuelta'
    ? '<span class="badge purple">Vuelta</span>'
    : '<span class="badge blue">Ida</span>';
}

function rowsHtml(rows){
  if(!rows.length) return `<tr><td colspan="8">${ui.emptyState('Sin programación','Cree el primer horario de servicio.','calendar')}</td></tr>`;
  return rows.map(s=>`<tr>
    <td><strong>${ui.esc(s.route_code||'')}</strong><div class="sub">${ui.esc(s.service_origin||'')} → ${ui.esc(s.service_destination||'')}</div></td>
    <td>${dirBadge(s.direction)}</td>
    <td class="nowrap"><strong>${ui.timeHM(s.departure_time)}</strong></td>
    <td><strong>#${ui.esc(s.vehicle_no)}</strong><div class="sub">${ui.esc(s.plate||'')}</div></td>
    <td>${ui.esc(s.driver_name||'—')}</td>
    <td>${ui.esc(s.guard_name||'—')}</td>
    <td>${s.active?'<span class="badge green">Activo</span>':'<span class="badge gray">Inactivo</span>'}</td>
    <td><div class="table-actions">
      ${canWrite()?`<button class="btn btn-sm btn-secondary btn-icon" data-generate="${s.id}" title="Generar colectivo">${ui.icon('bus',14)}</button>
      <button class="btn btn-sm btn-secondary btn-icon" data-edit="${s.id}" title="Editar">${ui.icon('edit',14)}</button>
      <button class="btn btn-sm btn-secondary btn-icon" data-del="${s.id}" title="Desactivar">${ui.icon('trash',14)}</button>`:''}
    </div></td>
  </tr>`).join('');
}

export default {
  title:'Servicios',
  subtitle:'Programación de horarios y turnos (ida y vuelta)',
  async render(root){
    const c=await catalogs();
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Servicios</div><div class="page-sub">Programación de horarios y turnos (ida y vuelta)</div></div>
        <div class="actions">
          <button class="btn btn-secondary" id="btn-print">${ui.icon('print')} Imprimir</button>
          ${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nuevo horario</button>`:''}
        </div>
      </div>
      <div class="card">
        <div class="filters no-print">
          <div class="field wide"><label>Ruta</label><select id="f-route"><option value="">Todas</option>${ui.options(c.routes,'id',r=>`${r.code?r.code+' · ':''}${r.origin} → ${r.destination}`)}</select></div>
          <div class="field"><label>Dirección</label><select id="f-direction"><option value="">Todas</option><option value="ida">Ida</option><option value="vuelta">Vuelta</option></select></div>
          <div class="field"><label>Estado</label><select id="f-active"><option value="">Todos</option><option value="1">Activos</option></select></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Ruta / Recorrido</th><th>Dirección</th><th>Salida</th><th>Coche</th><th>Chofer</th><th>Guarda</th><th>Estado</th><th></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;
    const tbody=root.querySelector('#tbody'), foot=root.querySelector('#foot');

    async function load(){
      ui.loading(tbody,4);
      try{
        const rows=await api.get('/schedules'+qs({
          route_id:root.querySelector('#f-route').value,
          direction:root.querySelector('#f-direction').value,
          active:root.querySelector('#f-active').value,
        }));
        tbody.innerHTML=rowsHtml(rows);
        foot.innerHTML=`<div style="font-size:12px" class="muted"><b>${rows.length}</b> horarios programados · Ida y vuelta se cargan como horarios separados.</div>`;
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>form(rows.find(x=>x.id===Number(b.dataset.edit)),load,c));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del),load));
        tbody.querySelectorAll('[data-generate]').forEach(b=>b.onclick=()=>generate(rows.find(x=>x.id===Number(b.dataset.generate)),c));
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="8">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; }
    }
    ['#f-route','#f-direction','#f-active'].forEach(s=>root.querySelector(s).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    root.querySelector('#btn-print').onclick=()=>window.print();
    const nb=root.querySelector('#btn-new'); if(nb) nb.onclick=()=>form(null,load,c);
    await load();
  }
};

function form(s,reload,c){
  const isEdit=!!s, d=s||{};
  ui.openModal({
    title:isEdit?'Editar horario':'Nuevo horario de servicio',
    subtitle:'La ida y la vuelta son horarios separados.',
    body:`<div class="form-grid cols-2">
      <div class="field"><label>Ruta *</label><select name="route_id" required>${ui.options(c.routes,'id',r=>`${r.code?r.code+' · ':''}${r.origin} → ${r.destination}`,isEdit?d.route_id:'')}</select></div>
      <div class="field"><label>Dirección *</label><select name="direction"><option value="ida" ${d.direction!=='vuelta'?'selected':''}>Ida (origen → destino)</option><option value="vuelta" ${d.direction==='vuelta'?'selected':''}>Vuelta (destino → origen)</option></select></div>
      <div class="field"><label>Hora de salida *</label><input name="departure_time" type="time" value="${isEdit?ui.timeHM(d.departure_time):''}" required></div>
      <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(c.vehicles,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`,isEdit?d.vehicle_id:'')}</select></div>
      <div class="field"><label>Chofer</label><select name="driver_id"><option value="">—</option>${ui.options(c.drivers,'id',e=>e.full_name,isEdit?d.driver_id:'')}</select></div>
      <div class="field"><label>Guarda</label><select name="guard_id"><option value="">—</option>${ui.options(c.guards,'id',e=>e.full_name,isEdit?d.guard_id:'')}</select></div>
      <div class="field"><label>Activo</label><label class="check"><input type="checkbox" name="active" ${d.active!==false?'checked':''}> Sí</label></div>
      <div class="field"><label>Notas</label><input name="notes" value="${ui.esc(d.notes||'')}"></div>
    </div>`,
    async onSubmit(form,close){
      const payload={
        route_id:Number(form.elements.route_id.value),
        direction:form.elements.direction.value,
        departure_time:form.elements.departure_time.value,
        vehicle_id:Number(form.elements.vehicle_id.value),
        driver_id:form.elements.driver_id.value?Number(form.elements.driver_id.value):null,
        guard_id:form.elements.guard_id.value?Number(form.elements.guard_id.value):null,
        active:ui.boolVal(form,'active'),
        notes:form.elements.notes.value,
      };
      if(!payload.route_id||!payload.vehicle_id||!payload.departure_time) throw new Error('Complete ruta, vehículo y horario');
      if(isEdit) await api.put('/schedules/'+s.id,payload); else await api.post('/schedules',payload);
      ui.toast(isEdit?'Horario actualizado':'Horario creado','ok'); close(); await reload();
    }
  });
}

async function generate(s,c){
  const route=c.routes.find(r=>String(r.id)===String(s.route_id));
  ui.openModal({
    title:'Generar colectivo del día',
    subtitle:`${ui.esc(route?.origin||'')} → ${ui.esc(route?.destination||'')} · ${ui.timeHM(s.departure_time)} · ${s.direction==='vuelta'?'Vuelta':'Ida'}`,
    submitText:'Generar colectivo',
    body:`<div class="form-grid cols-2">
      <div class="field"><label>Fecha *</label><input name="service_date" type="date" value="${state.today}" required></div>
      <div class="field"><label>Coche</label><input value="#${ui.esc(s.vehicle_no)}" disabled></div>
      <div class="field"><label>Recaudación inicial</label><input name="fare_total" type="number" step="0.01" value="0"></div>
      <div class="field"><label>Km</label><input value="${ui.integer(route?.distance_km)}" disabled></div>
    </div>
    <div class="tiny muted" style="margin-top:10px">Se crea el servicio en Colectivos con la programación, coche, chofer y guarda. Luego se cargan boletos, recaudación y gasoil.</div>`,
    async onSubmit(form,close){
      const payload={
        service_date:form.elements.service_date.value,
        route_id:s.route_id,
        vehicle_id:s.vehicle_id,
        driver_id:s.driver_id||null,
        guard_id:s.guard_id||null,
        departure_time:ui.timeHM(s.departure_time),
        direction:s.direction,
        schedule_id:s.id,
        schedule_label:`${s.direction==='vuelta'?'VUELTA':'IDA'} ${ui.timeHM(s.departure_time)}`,
        km:route?.distance_km||0,
        fare_total:ui.numVal(form,'fare_total'),
      };
      await api.post('/services',payload);
      ui.toast('Colectivo generado. Ya está disponible en Colectivos.','ok');
      close();
    }
  });
}

async function del(id,reload){
  if(!await ui.confirmDialog({title:'Desactivar horario',message:'El horario dejará de estar disponible para generar colectivos.',confirmText:'Desactivar'})) return;
  try{ await api.del('/schedules/'+id); ui.toast('Horario desactivado','ok'); await reload(); }catch(ex){ ui.toast(ex.message,'err'); }
}
