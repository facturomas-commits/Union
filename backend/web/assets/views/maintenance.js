import { api, qs } from '../api.js';
import { state, canWrite, canSeeMoney } from '../store.js';
import * as ui from '../ui.js';

let vehiclesCache=null;
let workshopsCache=null;

async function vehicles(){
  if(!vehiclesCache) vehiclesCache=await api.get('/vehicles');
  return vehiclesCache.filter(v=>v.active!==false);
}
async function workshops(force=false){
  if(!workshopsCache||force) workshopsCache=await api.get('/workshops?active=1');
  return workshopsCache;
}

const CATEGORIES=['LUBRICANTES Y FILTROS','CUBIERTAS','CAJA Y EMBRAGUE','MECÁNICA EN GRAL.','AIRE ACONDICIONADO','CARROCERÍA','OTROS'];
const STATUS={
  programado:{label:'Programado',cls:'blue'},
  presupuestado:{label:'Presupuestado',cls:'orange'},
  realizado:{label:'Realizado',cls:'green'},
  cancelado:{label:'Cancelado',cls:'gray'},
};

function statusBadge(status){
  const s=STATUS[status]||{label:status||'—',cls:'gray'};
  return `<span class="badge ${s.cls}">${s.label}</span>`;
}

function dueBadge(m){
  if(!m.next_due) return '<span class="muted">—</span>';
  const d=Number(m.days_left);
  if(d<0) return `<span class="badge red">Vencido ${Math.abs(d)} d</span>`;
  if(d<=15) return `<span class="badge orange">En ${d} d</span>`;
  return `<span class="badge green">${ui.dateDMY(m.next_due)}</span>`;
}

function workshopCell(m){
  if(!m.workshop_name && !m.workshop_phone) return '<span class="muted">—</span>';
  return `${m.workshop_name?`<strong>${ui.esc(m.workshop_name)}</strong>`:''}
    ${m.workshop_phone?`<div class="sub">${ui.phoneLink(m.workshop_phone)}</div>`:''}
    ${m.workshop_address?`<div class="sub">${ui.esc(m.workshop_address)}</div>`:''}`;
}

function moneyCell(m){
  if(!canSeeMoney()) return '';
  if(m.status==='realizado'){
    return `<td class="num"><strong>${ui.money(m.cost)}</strong>${Number(m.budget_amount)>0?`<div class="sub">Presup. ${ui.money(m.budget_amount)}</div>`:''}</td>`;
  }
  return `<td class="num">${Number(m.budget_amount)>0?ui.money(m.budget_amount):'<span class="muted">Sin presupuesto</span>'}</td>`;
}

export default {
  title:'Mantenimiento',
  subtitle:'Programación, presupuestos y servicios realizados',
  async render(root){
    vehiclesCache=null;
    const vs=await vehicles();
    const ws=await workshops(true);
    const params=ui.hashParams();
    const openId=Number(params.get('open')||0);
    const programVehicle=Number(params.get('program_vehicle')||0);
    const sourceId=Number(params.get('source')||0);
    const days=Number(state.settings?.maintenance_alert_days||15);

    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Mantenimiento</div><div class="page-sub">Programá el servicio, presupuestalo y marcalo como realizado</div></div>
        <div class="actions">${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Programar servicio</button>`:''}</div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field wide"><label>Vehículo</label><select id="f-vehicle"><option value="">Todos</option>${ui.options(vs,'id',v=>`#${v.internal_no}`)}</select></div>
          <div class="field"><label>Estado</label><select id="f-status">
            <option value="">Todos</option>
            <option value="programado">Programados</option>
            <option value="presupuestado">Presupuestados</option>
            <option value="realizado">Realizados</option>
          </select></div>
          <div class="field"><label>Alerta (días)</label><input type="number" id="f-days" value="${days}" min="0" style="width:100px"></div>
          <div class="field"><label>Solo vencimientos</label><label class="check"><input type="checkbox" id="f-due"> Activar</label></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div id="banner"></div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Vehículo</th><th>Rubro</th><th>Concepto</th><th>Taller / contacto</th><th>Próximo cambio</th><th class="num">Km</th>${canSeeMoney()?'<th class="num">Presupuesto / costo</th>':''}<th>Estado</th><th></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;
    const tbody=root.querySelector('#tbody'), foot=root.querySelector('#foot'), banner=root.querySelector('#banner');

    async function load(){
      ui.loading(tbody,5);
      try{
        const rows=await api.get('/maintenance'+qs({
          vehicle_id:root.querySelector('#f-vehicle').value,
          status:root.querySelector('#f-status').value,
          days:root.querySelector('#f-days').value,
          due:root.querySelector('#f-due').checked?'1':'',
        }));
        const seen=new Set();
        const latestRealized=rows.filter(m=>m.status==='realizado').filter(m=>{
          const key=`${m.vehicle_id}|${m.category}`;
          if(seen.has(key)) return false;
          seen.add(key);
          return true;
        });
        const due=latestRealized.filter(m=>m.next_due && Number(m.days_left)<=Number(root.querySelector('#f-days').value));
        const pending=rows.filter(m=>m.status==='programado'||m.status==='presupuestado');
        banner.innerHTML=(due.length||pending.length)?`<div style="margin:14px 18px 0;padding:11px 14px;border:1px solid #fcd34d;background:#fffbeb;border-radius:9px;display:flex;gap:14px;flex-wrap:wrap;align-items:center"><span style="color:#b45309">${ui.icon('alert')}</span><div style="font-size:12px;color:#92400e"><b>${pending.length} servicio(s) programados o presupuestados</b>${due.length?` · <b>${due.length} vencimiento(s)</b> en los próximos ${root.querySelector('#f-days').value} días`:''}</div></div>`:'';
        tbody.innerHTML=rows.length?rows.map(m=>`<tr>
          <td class="nowrap">${ui.dateDMY(m.maintenance_date)}<div class="sub">${m.status==='realizado'?'Realizado':'Programado'}</div></td>
          <td><strong>#${ui.esc(m.vehicle_no)}</strong></td>
          <td><span class="badge gray">${ui.esc(m.category||'—')}</span></td>
          <td>${ui.esc(m.concept||'—')}</td>
          <td>${workshopCell(m)}</td>
          <td>${m.status==='realizado'?dueBadge(m):`<span class="badge blue">${ui.dateDMY(m.maintenance_date)}</span>`}${m.next_due?`<div class="sub">${ui.dateDMY(m.next_due)}</div>`:''}</td>
          <td class="num">${m.odometer?ui.integer(m.odometer):'—'}</td>
          ${moneyCell(m)}
          <td>${statusBadge(m.status)}</td>
          <td><div class="table-actions">${canWrite()?`
            <button class="btn btn-sm btn-secondary btn-icon" data-edit="${m.id}" title="${m.status==='realizado'?'Editar servicio realizado':'Editar programación'}">${ui.icon('edit',14)}</button>
            ${(m.status==='programado'&&canSeeMoney())?`<button class="btn btn-sm btn-secondary btn-icon" data-budget="${m.id}" title="Presupuestar">${ui.icon('coins',14)}</button>`:''}
            ${(m.status==='programado'||m.status==='presupuestado')?`<button class="btn btn-sm btn-secondary btn-icon" data-complete="${m.id}" title="Marcar como realizado">${ui.icon('check',14)}</button>`:''}
            <button class="btn btn-sm btn-secondary btn-icon" data-del="${m.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}</div></td>
        </tr>`).join(''):`<tr><td colspan="${canSeeMoney()?10:9}">${ui.emptyState('Sin mantenimiento','No hay registros para el filtro seleccionado.','wrench')}</td></tr>`;

        const total=rows.filter(m=>m.status==='realizado').reduce((a,m)=>a+Number(m.cost||0),0);
        const pendingTotal=rows.filter(m=>m.status!=='realizado').reduce((a,m)=>a+Number(m.budget_amount||0),0);
        foot.innerHTML=`<div style="display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;font-size:12px">
          <span><b>${rows.length}</b> registros · <b>${pending.length}</b> programados/presupuestados</span>
          ${canSeeMoney()?`<span>Realizados <b>${ui.money(total)}</b>${pendingTotal>0?` · Presupuestado <b>${ui.money(pendingTotal)}</b>`:''}</span>`:''}
        </div>`;

        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>{
          const m=rows.find(x=>x.id===Number(b.dataset.edit));
          if(m) m.status==='realizado' ? editCompleted(m,load,vs,ws) : orderForm(m.id,null,load,vs,ws);
        });
        tbody.querySelectorAll('[data-budget]').forEach(b=>b.onclick=()=>{
          const m=rows.find(x=>x.id===Number(b.dataset.budget));
          if(m) orderForm(m.id,null,load,vs,ws,'presupuestado');
        });
        tbody.querySelectorAll('[data-complete]').forEach(b=>b.onclick=()=>{
          const m=rows.find(x=>x.id===Number(b.dataset.complete));
          if(m) completeForm(m,load);
        });
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del),load));
        return rows;
      }catch(ex){
        tbody.innerHTML=`<tr><td colspan="${canSeeMoney()?10:9}">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`;
        return [];
      }
    }

    ['#f-vehicle','#f-status','#f-days','#f-due'].forEach(s=>root.querySelector(s).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    const nb=root.querySelector('#btn-new');
    if(nb) nb.onclick=()=>orderForm(null,null,load,vs,ws);

    const rows=await load();
    if(openId){
      history.replaceState(null,'','#/maintenance');
      let m=rows.find(x=>x.id===openId);
      if(!m){
        try{ m=await api.get('/maintenance/'+openId); }
        catch(ex){ ui.toast('No se encontró el registro de mantenimiento','err'); }
      }
      if(m) m.status==='realizado' ? editCompleted(m,load,vs,ws) : orderForm(openId,null,load,vs,ws);
    } else if(programVehicle){
      history.replaceState(null,'','#/maintenance');
      let source=null;
      if(sourceId){
        try{ source=await api.get('/maintenance/'+sourceId); }
        catch(ex){ /* la alerta puede seguir funcionando sin el registro fuente */ }
      }
      orderForm(null,{...(source||{}),vehicle_id:programVehicle,maintenance_date:state.today,status:'programado',budget_amount:0,measures:'',notes:''},load,vs,ws);
    }
  }
};

/* ---------------- Programar / presupuestar ---------------- */
async function orderForm(id, source, onDone, vs, ws, presetStatus){
  let d={...(source||{})};
  if(id){
    try{ d=await api.get('/maintenance/'+id); }
    catch(ex){ ui.toast(ex.message,'err'); return; }
  }
  const isEdit=!!id;
  const status=presetStatus || (d.status==='presupuestado'?'presupuestado':'programado');
  const body=`
    <div class="callout" style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:9px;padding:10px 12px;margin-bottom:14px;font-size:12px;color:#075985">
      ${isEdit?'Editá la programación o el presupuesto.':'Programá el trabajo. Después podrás cargar el presupuesto y, cuando esté terminado, marcarlo como realizado.'}
    </div>
    <div class="form-grid cols-2">
      <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(vs,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`,d.vehicle_id||'')}</select></div>
      <div class="field"><label>Fecha programada *</label><input name="maintenance_date" type="date" value="${d.maintenance_date||state.today}" required></div>
      <div class="field"><label>Rubro *</label><select name="category" required>${CATEGORIES.map(c=>`<option ${d.category===c?'selected':''}>${c}</option>`).join('')}</select></div>
      <div class="field"><label>Concepto *</label><input name="concept" value="${ui.esc(d.concept||'')}" placeholder="Ej: service de aceite y filtros" required></div>
      <div class="field"><label>Taller / proveedor</label><select name="workshop_id"><option value="">— Sin taller —</option>${ui.options(ws,'id',w=>`${w.name}${w.phone?' · '+w.phone:''}`,d.workshop_id||'')}</select><div class="help">Teléfono: <span id="ws-phone">—</span></div></div>
      <div class="field"><label>Estado</label><select name="status"><option value="programado" ${status==='programado'?'selected':''}>Programado</option>${(canSeeMoney()||status==='presupuestado')?`<option value="presupuestado" ${status==='presupuestado'?'selected':''}>Presupuestado</option>`:''}</select></div>
      ${canSeeMoney()?`<div class="field"><label>Presupuesto $</label><input name="budget_amount" type="number" step="0.01" min="0" value="${d.budget_amount??''}"></div>`:''}
      <div class="field"><label>Medidas / repuesto</label><input name="measures" value="${ui.esc(d.measures||'')}" placeholder="Ej: Michelin 11R22.5"></div>
      <div class="field full"><label>Notas</label><textarea name="notes">${ui.esc(d.notes||'')}</textarea></div>
    </div>`;
  ui.openModal({
    title:isEdit?'Programar / presupuestar servicio':'Programar servicio',
    subtitle:isEdit?`Registro #${id}`:'Elegí coche/camión, taller y fecha. Después se puede presupuestar y marcar realizado.',
    body,
    submitText:isEdit?'Guardar cambios':'Programar servicio',
    onReady(form){
      const showPhone=()=>{
        const w=ws.find(x=>String(x.id)===form.elements.workshop_id.value);
        const el=form.querySelector('#ws-phone');
        el.innerHTML=w&&w.phone?ui.phoneLink(w.phone):(w?'Sin teléfono':'—');
      };
      form.elements.workshop_id.addEventListener('change',showPhone);
      showPhone();
    },
    async onSubmit(form,close){
      const payload={
        vehicle_id:Number(form.elements.vehicle_id.value),
        maintenance_date:form.elements.maintenance_date.value,
        category:form.elements.category.value,
        concept:form.elements.concept.value,
        measures:form.elements.measures.value,
        status:form.elements.status.value,
        workshop_id:form.elements.workshop_id.value?Number(form.elements.workshop_id.value):null,
        notes:form.elements.notes.value,
      };
      if(canSeeMoney()) payload.budget_amount=ui.numVal(form,'budget_amount');
      if(!payload.vehicle_id||!payload.maintenance_date||!payload.concept) throw new Error('Complete vehículo, fecha y concepto');
      if(isEdit) await api.put('/maintenance/'+id,payload); else await api.post('/maintenance',payload);
      ui.toast(isEdit?'Programación actualizada':'Servicio programado','ok');
      close();
      await onDone();
    }
  });
}

/* ---------------- Marcar realizado ---------------- */
function completeForm(m,onDone){
  ui.openModal({
    title:'Marcar servicio como realizado',
    subtitle:`Coche #${m.vehicle_no} · ${m.concept}`,
    body:`
      <div class="callout" style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:9px;padding:10px 12px;margin-bottom:14px;font-size:12px;color:#166534">
        Al confirmar, el servicio pasa al historial como <b>realizado</b> y queda disponible para el próximo vencimiento.
        ${m.workshop_name?`<div style="margin-top:6px">Taller: <b>${ui.esc(m.workshop_name)}</b>${m.workshop_phone?` · ${ui.phoneLink(m.workshop_phone)}`:''}</div>`:''}
      </div>
      <div class="form-grid cols-2">
        <div class="field"><label>Fecha de realización *</label><input name="maintenance_date" type="date" value="${state.today}" required></div>
        ${canSeeMoney()?`<div class="field"><label>Costo final $</label><input name="cost" type="number" step="0.01" min="0" value="${m.budget_amount||''}"></div>`:''}
        <div class="field"><label>Odómetro</label><input name="odometer" type="number" step="0.1" value="${m.odometer||''}"></div>
        <div class="field"><label>Próximo cambio</label><input name="next_due" type="date" value="${m.next_due||''}"></div>
        <div class="field full"><label>Notas / trabajos realizados</label><textarea name="notes">${ui.esc(m.notes||'')}</textarea></div>
      </div>`,
    submitText:'Marcar como realizado',
    async onSubmit(form,close){
      const payload={
        maintenance_date:form.elements.maintenance_date.value,
        odometer:form.elements.odometer.value?ui.numVal(form,'odometer'):null,
        next_due:form.elements.next_due.value||null,
        notes:form.elements.notes.value,
      };
      if(canSeeMoney()) payload.cost=ui.numVal(form,'cost');
      if(!payload.maintenance_date) throw new Error('Indique la fecha de realización');
      await api.post('/maintenance/'+m.id+'/complete',payload);
      ui.toast('Servicio marcado como realizado','ok');
      close();
      await onDone();
    }
  });
}

/* ---------------- Editar un servicio ya realizado ---------------- */
function editCompleted(m,onDone,vs,ws){
  ui.openModal({
    title:'Editar servicio realizado',
    subtitle:`Coche #${m.vehicle_no} · ${m.concept}`,
    body:`
      <div class="form-grid cols-2">
        <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(vs,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`,m.vehicle_id)}</select></div>
        <div class="field"><label>Fecha de realización *</label><input name="maintenance_date" type="date" value="${m.maintenance_date}" required></div>
        <div class="field"><label>Rubro *</label><select name="category" required>${CATEGORIES.map(c=>`<option ${m.category===c?'selected':''}>${c}</option>`).join('')}</select></div>
        <div class="field"><label>Concepto *</label><input name="concept" value="${ui.esc(m.concept||'')}" required></div>
        <div class="field"><label>Taller / proveedor</label><select name="workshop_id"><option value="">— Sin taller —</option>${ui.options(ws,'id',w=>`${w.name}${w.phone?' · '+w.phone:''}`,m.workshop_id||'')}</select><div class="help">Teléfono: <span id="ws-phone">—</span></div></div>
        <div class="field"><label>Medidas / repuesto</label><input name="measures" value="${ui.esc(m.measures||'')}"></div>
        ${canSeeMoney()?`<div class="field"><label>Costo final $</label><input name="cost" type="number" step="0.01" min="0" value="${m.cost??''}"></div><div class="field"><label>Presupuesto $</label><input name="budget_amount" type="number" step="0.01" min="0" value="${m.budget_amount??''}"></div>`:''}
        <div class="field"><label>Odómetro</label><input name="odometer" type="number" step="0.1" value="${m.odometer??''}"></div>
        <div class="field"><label>Próximo cambio</label><input name="next_due" type="date" value="${m.next_due||''}"></div>
        <div class="field full"><label>Notas</label><textarea name="notes">${ui.esc(m.notes||'')}</textarea></div>
      </div>`,
    onReady(form){
      const showPhone=()=>{
        const w=ws.find(x=>String(x.id)===form.elements.workshop_id.value);
        const el=form.querySelector('#ws-phone');
        el.innerHTML=w&&w.phone?ui.phoneLink(w.phone):(w?'Sin teléfono':'—');
      };
      form.elements.workshop_id.addEventListener('change',showPhone);
      showPhone();
    },
    async onSubmit(form,close){
      const payload={
        vehicle_id:Number(form.elements.vehicle_id.value),
        maintenance_date:form.elements.maintenance_date.value,
        category:form.elements.category.value,
        concept:form.elements.concept.value,
        measures:form.elements.measures.value,
        workshop_id:form.elements.workshop_id.value?Number(form.elements.workshop_id.value):null,
        odometer:form.elements.odometer.value?ui.numVal(form,'odometer'):null,
        next_due:form.elements.next_due.value||null,
        notes:form.elements.notes.value,
      };
      if(canSeeMoney()){ payload.cost=ui.numVal(form,'cost'); payload.budget_amount=ui.numVal(form,'budget_amount'); }
      if(!payload.vehicle_id||!payload.maintenance_date||!payload.concept) throw new Error('Complete vehículo, fecha y concepto');
      await api.put('/maintenance/'+m.id,payload);
      ui.toast('Servicio actualizado','ok');
      close();
      await onDone();
    }
  });
}

async function del(id,onDone){
  if(!await ui.confirmDialog({title:'Eliminar mantenimiento',message:'Se eliminará el registro de mantenimiento.',confirmText:'Eliminar'})) return;
  try{ await api.del('/maintenance/'+id); ui.toast('Registro eliminado','ok'); await onDone(); }catch(ex){ ui.toast(ex.message,'err'); }
}
