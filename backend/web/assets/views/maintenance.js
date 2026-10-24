import { api, qs } from '../api.js';
import { state, canWrite, canSeeMoney } from '../store.js';
import * as ui from '../ui.js';

let vehiclesCache=null;
async function vehicles(){
  if(!vehiclesCache) vehiclesCache=await api.get('/vehicles');
  return vehiclesCache.filter(v=>v.active!==false);
}
const CATEGORIES=['LUBRICANTES Y FILTROS','CUBIERTAS','CAJA Y EMBRAGUE','MECÁNICA EN GRAL.','AIRE ACONDICIONADO','CARROCERÍA','OTROS'];

function dueBadge(m){
  if(!m.next_due) return '<span class="muted">—</span>';
  const d=Number(m.days_left);
  if(d<0) return `<span class="badge red">Vencido ${Math.abs(d)} d</span>`;
  if(d<=15) return `<span class="badge orange">En ${d} d</span>`;
  return `<span class="badge green">${ui.dateDMY(m.next_due)}</span>`;
}

export default {
  title:'Mantenimiento',
  subtitle:'Reparaciones, services y próximos cambios',
  async render(root){
    const vs=await vehicles();
    const openId=Number(ui.hashParams().get('open')||0);
    const days=Number(state.settings?.maintenance_alert_days||15);
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Mantenimiento</div><div class="page-sub">Reparaciones, services y próximos cambios</div></div>
        <div class="actions">${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nuevo registro</button>`:''}</div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field wide"><label>Vehículo</label><select id="f-vehicle"><option value="">Todos</option>${ui.options(vs,'id',v=>`#${v.internal_no}`)}</select></div>
          <div class="field"><label>Alerta (días)</label><input type="number" id="f-days" value="${days}" min="0" style="width:100px"></div>
          <div class="field"><label>Solo vencimientos</label><label class="check"><input type="checkbox" id="f-due"> Activar</label></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div id="banner"></div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Vehículo</th><th>Rubro</th><th>Concepto</th><th>Medidas / repuesto</th><th>Próximo cambio</th><th class="num">Km</th><th class="num">Costo</th><th></th></tr></thead>
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
          days:root.querySelector('#f-days').value,
          due:root.querySelector('#f-due').checked?'1':'',
        }));
        const due=rows.filter(m=>m.next_due && Number(m.days_left)<=Number(root.querySelector('#f-days').value));
        banner.innerHTML=due.length?`<div style="margin:14px 18px 0;padding:11px 14px;border:1px solid #fcd34d;background:#fffbeb;border-radius:9px;display:flex;gap:10px;align-items:center"><span style="color:#b45309">${ui.icon('alert')}</span><div style="font-size:12px;color:#92400e"><b>${due.length} mantenimiento(s) requieren atención</b> en los próximos ${root.querySelector('#f-days').value} días.</div></div>`:'';
        tbody.innerHTML=rows.length?rows.map(m=>`<tr>
          <td class="nowrap">${ui.dateDMY(m.maintenance_date)}</td>
          <td><strong>#${ui.esc(m.vehicle_no)}</strong></td>
          <td><span class="badge gray">${ui.esc(m.category||'—')}</span></td>
          <td>${ui.esc(m.concept||'—')}</td>
          <td class="sub">${ui.esc(m.measures||'—')}</td>
          <td>${dueBadge(m)}<div class="sub">${m.next_due?ui.dateDMY(m.next_due):''}</div></td>
          <td class="num">${m.odometer?ui.integer(m.odometer):'—'}</td>
          <td class="num">${ui.money(m.cost)}</td>
          <td><div class="table-actions">${canWrite()?`
            <button class="btn btn-sm btn-secondary btn-icon" data-edit="${m.id}" title="Editar">${ui.icon('edit',14)}</button>
            <button class="btn btn-sm btn-secondary btn-icon" data-del="${m.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}</div></td>
        </tr>`).join(''):`<tr><td colspan="9">${ui.emptyState('Sin mantenimiento','No hay registros para el filtro seleccionado.','wrench')}</td></tr>`;
        const total=rows.reduce((a,m)=>a+Number(m.cost||0),0);
        foot.innerHTML=`<div style="display:flex;justify-content:space-between;font-size:12px"><span><b>${rows.length}</b> registros</span><span>Costo total <b>${ui.money(total)}</b></span></div>`;
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>form(Number(b.dataset.edit),rows.find(x=>x.id===Number(b.dataset.edit)),load,vs));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del),load));
        return rows;
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="9">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; return []; }
    }
    ['#f-vehicle','#f-days','#f-due'].forEach(s=>root.querySelector(s).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    const nb=root.querySelector('#btn-new'); if(nb) nb.onclick=()=>form(null,null,load,vs);
    const rows=await load();
    if(openId){
      history.replaceState(null,'','#/maintenance');
      let m=rows.find(x=>x.id===openId);
      if(!m){
        try{ m=await api.get('/maintenance/'+openId); }
        catch(ex){ ui.toast('No se encontró el registro de mantenimiento','err'); }
      }
      if(m) form(openId,m,load,vs);
    }
  }
};

function form(id,m,onDone,vs){
  const isEdit=!!m, d=m||{};
  ui.openModal({
    title:isEdit?'Editar mantenimiento':'Nuevo registro de mantenimiento',
    subtitle:isEdit?`Registro #${id}`:'Service, reparación, cubiertas o próximo cambio.',
    body:`
      <div class="form-grid cols-2">
        <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(vs,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`,isEdit?d.vehicle_id:'')}</select></div>
        <div class="field"><label>Fecha *</label><input name="maintenance_date" type="date" value="${isEdit?d.maintenance_date:state.today}" required></div>
        <div class="field"><label>Rubro *</label><select name="category" required>${CATEGORIES.map(c=>`<option ${d.category===c?'selected':''}>${c}</option>`).join('')}</select></div>
        <div class="field"><label>Concepto *</label><input name="concept" value="${ui.esc(d.concept||'')}" placeholder="Ej: cambio de aceite y filtros" required></div>
        <div class="field"><label>Medidas / repuesto</label><input name="measures" value="${ui.esc(d.measures||'')}" placeholder="Ej: Michelin 11R22.5"></div>
        <div class="field"><label>Próximo cambio</label><input name="next_due" type="date" value="${isEdit&&d.next_due?d.next_due:''}"></div>
        <div class="field"><label>Odómetro</label><input name="odometer" type="number" step="0.1" value="${isEdit&&d.odometer?d.odometer:''}"></div>
        ${canSeeMoney()?`<div class="field"><label>Costo $</label><input name="cost" type="number" step="0.01" value="${isEdit?d.cost:''}"></div>`:''}
        <div class="field full"><label>Notas</label><textarea name="notes">${ui.esc(d.notes||'')}</textarea></div>
      </div>`,
    async onSubmit(form, close){
      const payload={
        vehicle_id:Number(form.elements.vehicle_id.value),
        maintenance_date:form.elements.maintenance_date.value,
        category:form.elements.category.value,
        concept:form.elements.concept.value,
        measures:form.elements.measures.value,
        next_due:form.elements.next_due.value||null,
        odometer:form.elements.odometer.value?ui.numVal(form,'odometer'):null,
        notes:form.elements.notes.value,
      };
      if(canSeeMoney()) payload.cost=ui.numVal(form,'cost');
      if(!payload.vehicle_id||!payload.maintenance_date||!payload.concept) throw new Error('Complete vehículo, fecha y concepto');
      if(isEdit) await api.put('/maintenance/'+id,payload); else await api.post('/maintenance',payload);
      ui.toast(isEdit?'Mantenimiento actualizado':'Mantenimiento registrado','ok'); close(); await onDone();
    }
  });
}

async function del(id,onDone){
  if(!await ui.confirmDialog({title:'Eliminar mantenimiento',message:'Se eliminará el registro de mantenimiento.',confirmText:'Eliminar'})) return;
  try{ await api.del('/maintenance/'+id); ui.toast('Registro eliminado','ok'); await onDone(); }catch(ex){ ui.toast(ex.message,'err'); }
}
