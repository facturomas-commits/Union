import { api, qs } from '../api.js';
import { state, canWrite } from '../store.js';
import * as ui from '../ui.js';

const CATS = {
  oncology:{label:'Oncológico', cls:'orange'},
  ticket_office:{label:'Boleterías', cls:'blue'},
  mp:{label:'Mercado Pago', cls:'purple'},
  other:{label:'Otros', cls:'gray'},
};
let vehiclesCache=null;
async function vehicles(){
  if(!vehiclesCache) vehiclesCache=await api.get('/vehicles');
  return vehiclesCache.filter(v=>v.active!==false);
}
function range(){
  const base=(state.latest&&state.latest.service_date)||state.today;
  return { from: base.slice(0,7)+'-01', to: base };
}

export default {
  title:'Gastos',
  subtitle:'Deducciones y gastos del servicio',
  async render(root){
    const r=range();
    const vs=await vehicles();
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Gastos</div><div class="page-sub">Deducciones y gastos del servicio</div></div>
        <div class="actions">${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nuevo gasto</button>`:''}</div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field"><label>Desde</label><input type="date" id="f-from" value="${r.from}"></div>
          <div class="field"><label>Hasta</label><input type="date" id="f-to" value="${r.to}"></div>
          <div class="field"><label>Categoría</label><select id="f-cat"><option value="">Todas</option>${Object.entries(CATS).map(([k,v])=>`<option value="${k}">${v.label}</option>`).join('')}</select></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Categoría</th><th>Concepto</th><th>Servicio</th><th>Vehículo</th><th class="num">Importe</th><th></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;
    const tbody=root.querySelector('#tbody'), foot=root.querySelector('#foot');

    async function load(){
      ui.loading(tbody,4);
      try{
        const rows=await api.get('/expenses'+qs({date_from:root.querySelector('#f-from').value,date_to:root.querySelector('#f-to').value}));
        const cat=root.querySelector('#f-cat').value;
        const filtered=cat?rows.filter(x=>x.category===cat):rows;
        tbody.innerHTML=filtered.length?filtered.map(x=>{
          const c=CATS[x.category]||{label:x.category,cls:'gray'};
          return `<tr>
            <td class="nowrap">${ui.dateDMY(x.expense_date)}</td>
            <td><span class="badge ${c.cls}">${ui.esc(c.label)}</span></td>
            <td>${ui.esc(x.description||'—')}</td>
            <td>${x.service_id?`#${x.service_id} <span class="sub">${ui.dateDMY(x.service_date)}</span>`:'<span class="muted">—</span>'}</td>
            <td>${x.vehicle_no?'#'+ui.esc(x.vehicle_no):'—'}</td>
            <td class="num"><strong>${ui.money(x.amount)}</strong></td>
            <td><div class="table-actions">${canWrite()?`
              <button class="btn btn-sm btn-secondary btn-icon" data-edit="${x.id}" title="Editar">${ui.icon('edit',14)}</button>
              <button class="btn btn-sm btn-secondary btn-icon" data-del="${x.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}</div></td>
          </tr>`;
        }).join(''):`<tr><td colspan="7">${ui.emptyState('Sin gastos','No hay gastos en el rango.','receipt')}</td></tr>`;
        const total=filtered.reduce((a,x)=>a+Number(x.amount||0),0);
        foot.innerHTML=`<div style="display:flex;justify-content:space-between;font-size:12px"><span><b>${filtered.length}</b> registros</span><span>Total <b>${ui.money(total)}</b></span></div>`;
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>form(Number(b.dataset.edit),filtered.find(x=>x.id===Number(b.dataset.edit)),load,vs));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del),load));
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="7">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; }
    }
    ['#f-from','#f-to','#f-cat'].forEach(s=>root.querySelector(s).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    const nb=root.querySelector('#btn-new'); if(nb) nb.onclick=()=>form(null,null,load,vs);
    await load();
  }
};

async function servicesForForm(){
  const base=(state.latest&&state.latest.service_date)||state.today;
  const from=base.slice(0,7)+'-01';
  return api.get('/services'+qs({date_from:from,date_to:base}));
}

function form(id,x,onDone,vs){
  const isEdit=!!x, d=x||{};
  servicesForForm().then(svcs=>{
    const opts=svcs.map(s=>`<option value="${s.id}" ${String(d.service_id)===String(s.id)?'selected':''}>#${s.id} · ${ui.dateDMY(s.service_date)} · #${ui.esc(s.vehicle_no)} · ${ui.timeHM(s.departure_time)}</option>`).join('');
    ui.openModal({
      title:isEdit?'Editar gasto':'Nuevo gasto',
      subtitle:isEdit?`Gasto #${id}`:'Deducción o gasto asociado a un servicio.',
      body:`
        <div class="form-grid cols-2">
          <div class="field"><label>Fecha *</label><input name="expense_date" type="date" value="${isEdit?d.expense_date:state.today}" required></div>
          <div class="field"><label>Categoría *</label><select name="category" required>${Object.entries(CATS).map(([k,v])=>`<option value="${k}" ${d.category===k?'selected':''}>${v.label}</option>`).join('')}</select></div>
          <div class="field"><label>Importe $ *</label><input name="amount" type="number" step="0.01" value="${isEdit?d.amount:''}" required></div>
          <div class="field"><label>Servicio</label><select name="service_id"><option value="">— General —</option>${opts}</select></div>
          <div class="field"><label>Vehículo</label><select name="vehicle_id"><option value="">—</option>${ui.options(vs,'id',v=>`#${v.internal_no}`,isEdit?d.vehicle_id:'')}</select></div>
          <div class="field"><label>Concepto</label><input name="description" value="${ui.esc(d.description||'')}" placeholder="Detalle del gasto"></div>
        </div>`,
      onReady(form){
        form.elements.service_id.addEventListener('change',()=>{
          const s=svcs.find(z=>String(z.id)===form.elements.service_id.value);
          if(s){ form.elements.expense_date.value=s.service_date; form.elements.vehicle_id.value=s.vehicle_id; }
        });
      },
      async onSubmit(form, close){
        const payload={
          expense_date:form.elements.expense_date.value,
          category:form.elements.category.value,
          amount:ui.numVal(form,'amount'),
          service_id:form.elements.service_id.value?Number(form.elements.service_id.value):null,
          vehicle_id:form.elements.vehicle_id.value?Number(form.elements.vehicle_id.value):null,
          description:form.elements.description.value,
        };
        if(!payload.expense_date||!payload.category||!(payload.amount>0)) throw new Error('Complete fecha, categoría e importe');
        if(isEdit) await api.put('/expenses/'+id,payload); else await api.post('/expenses',payload);
        ui.toast(isEdit?'Gasto actualizado':'Gasto registrado','ok'); close(); await onDone();
      }
    });
  }).catch(ex=>ui.toast(ex.message,'err'));
}

async function del(id,onDone){
  if(!await ui.confirmDialog({title:'Eliminar gasto',message:'Se eliminará el gasto seleccionado.',confirmText:'Eliminar'})) return;
  try{ await api.del('/expenses/'+id); ui.toast('Gasto eliminado','ok'); await onDone(); }catch(ex){ ui.toast(ex.message,'err'); }
}
