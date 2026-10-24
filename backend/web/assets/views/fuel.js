import { api, qs } from '../api.js';
import { state, canWrite } from '../store.js';
import * as ui from '../ui.js';

let vehiclesCache = null;
async function vehicles(){
  if (!vehiclesCache) vehiclesCache = await api.get('/vehicles');
  return vehiclesCache.filter(v=>v.active!==false);
}

function range(){
  const base=(state.latest&&state.latest.service_date)||state.today;
  return { from: base.slice(0,7)+'-01', to: base, vehicle:'' };
}

export default {
  title:'Combustible',
  subtitle:'Cargas de gasoil por vehículo',
  async render(root){
    const r=range();
    const vs=await vehicles();
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Combustible</div><div class="page-sub">Cargas de gasoil por vehículo y servicio</div></div>
        <div class="actions">${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nueva carga</button>`:''}</div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field"><label>Desde</label><input type="date" id="f-from" value="${r.from}"></div>
          <div class="field"><label>Hasta</label><input type="date" id="f-to" value="${r.to}"></div>
          <div class="field wide"><label>Vehículo</label><select id="f-vehicle"><option value="">Todos</option>${ui.options(vs,'id',v=>`#${v.internal_no}`)}</select></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Vehículo</th><th>Servicio</th><th class="num">Litros</th><th class="num">$/L</th><th class="num">Importe</th><th class="num">Odómetro</th><th>Tanque</th><th></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;
    const tbody=root.querySelector('#tbody');
    const foot=root.querySelector('#foot');

    async function load(){
      ui.loading(tbody,4);
      try{
        const rows=await api.get('/fuel'+qs({date_from:root.querySelector('#f-from').value,date_to:root.querySelector('#f-to').value,vehicle_id:root.querySelector('#f-vehicle').value}));
        tbody.innerHTML=rows.length?rows.map(f=>`<tr>
          <td class="nowrap">${ui.dateDMY(f.load_date)}</td>
          <td><strong>#${ui.esc(f.vehicle_no)}</strong></td>
          <td>${f.service_id?`<span class="badge blue">#${f.service_id}</span> <span class="sub">${ui.esc(f.schedule_label||'')}</span>`:'<span class="muted">—</span>'}</td>
          <td class="num">${ui.num(f.liters)}</td>
          <td class="num">${ui.money(f.price_per_liter)}</td>
          <td class="num"><strong>${ui.money(f.amount)}</strong></td>
          <td class="num">${f.odometer?ui.integer(f.odometer):'—'}</td>
          <td>${f.full_tank?'<span class="badge green">Sí</span>':'<span class="badge gray">No</span>'}</td>
          <td><div class="table-actions">${canWrite()?`
            <button class="btn btn-sm btn-secondary btn-icon" data-edit="${f.id}" title="Editar">${ui.icon('edit',14)}</button>
            <button class="btn btn-sm btn-secondary btn-icon" data-del="${f.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}</div></td>
        </tr>`).join(''):`<tr><td colspan="9">${ui.emptyState('Sin cargas','No hay combustible en el rango.','fuel')}</td></tr>`;
        const tot=rows.reduce((a,f)=>{a.l+=Number(f.liters||0);a.m+=Number(f.amount||0);return a;},{l:0,m:0});
        foot.innerHTML=`<div style="display:flex;justify-content:space-between;font-size:12px"><span><b>${rows.length}</b> cargas</span><span>${ui.num(tot.l)} litros · <b>${ui.money(tot.m)}</b></span></div>`;
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>form(Number(b.dataset.edit), rows.find(x=>x.id===Number(b.dataset.edit)), onSaved, vs));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del), onSaved));
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="9">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; }
    }
    ['#f-from','#f-to','#f-vehicle'].forEach(s=>root.querySelector(s).onchange=load);
    root.querySelector('#btn-reload').onclick=load;
    const onSaved = async (date)=>{
      if(date){
        const from=root.querySelector('#f-from'), to=root.querySelector('#f-to');
        if(date < from.value || date > to.value){ from.value=date.slice(0,7)+'-01'; to.value=date; }
      }
      await load();
    };
    const nb=root.querySelector('#btn-new'); if(nb) nb.onclick=()=>form(null,null,onSaved,vs);
    await load();
  }
};

function form(id, f, onDone, vs){
  const isEdit=!!f;
  const d=f||{};
  ui.openModal({
    title:isEdit?'Editar carga':'Nueva carga de combustible',
    subtitle:isEdit?`Carga #${id}`:'Registre litros e importe. Se puede vincular desde el servicio.',
    body:`
      <div class="form-grid cols-2">
        <div class="field"><label>Vehículo *</label><select name="vehicle_id" required>${ui.options(vs,'id',v=>`#${v.internal_no} (${v.kind==='truck'?'camión':'colectivo'})`,isEdit?d.vehicle_id:'')}</select></div>
        <div class="field"><label>Fecha *</label><input name="load_date" type="date" value="${isEdit?d.load_date:state.today}" required></div>
        <div class="field"><label>Litros</label><input name="liters" type="number" step="0.01" value="${isEdit?d.liters:''}"></div>
        <div class="field"><label>Precio por litro</label><input name="price_per_liter" type="number" step="0.01" value="${isEdit?d.price_per_liter:''}"></div>
        <div class="field"><label>Importe total $</label><input name="amount" type="number" step="0.01" value="${isEdit?d.amount:''}"></div>
        <div class="field"><label>Odómetro</label><input name="odometer" type="number" step="0.1" value="${isEdit&&d.odometer?d.odometer:''}"></div>
        <div class="field"><label>Estación</label><input name="station" value="${ui.esc(d.station||'')}"></div>
        <div class="field"><label>Tanque lleno</label><label class="check"><input type="checkbox" name="full_tank" ${isEdit&&d.full_tank?'checked':''}> Sí</label></div>
        <div class="field full"><label>Notas</label><textarea name="notes">${ui.esc(d.notes||'')}</textarea></div>
      </div>`,
    onReady(form){
      const calc=()=>{
        const l=ui.numVal(form,'liters'), p=ui.numVal(form,'price_per_liter');
        if (l>0&&p>0&&!form.elements.amount.value) form.elements.amount.value=(Math.round(l*p*100)/100).toFixed(2);
      };
      form.elements.liters.addEventListener('input',calc);
      form.elements.price_per_liter.addEventListener('input',calc);
    },
    async onSubmit(form, close){
      const payload={
        vehicle_id:Number(form.elements.vehicle_id.value),
        load_date:form.elements.load_date.value,
        liters:ui.numVal(form,'liters'),
        price_per_liter:ui.numVal(form,'price_per_liter'),
        amount:ui.numVal(form,'amount'),
        odometer:form.elements.odometer.value?ui.numVal(form,'odometer'):null,
        full_tank:ui.boolVal(form,'full_tank'),
        station:form.elements.station.value,
        notes:form.elements.notes.value,
      };
      if(!payload.vehicle_id||!payload.load_date) throw new Error('Complete vehículo y fecha');
      if(isEdit) await api.put('/fuel/'+id,payload); else await api.post('/fuel',payload);
      ui.toast(isEdit?'Carga actualizada':'Carga registrada','ok'); close(); await onDone(payload.load_date);
    }
  });
}

async function del(id,onDone){
  if(!await ui.confirmDialog({title:'Eliminar carga',message:'Se eliminará la carga de combustible.',confirmText:'Eliminar'})) return;
  try{ await api.del('/fuel/'+id); ui.toast('Carga eliminada','ok'); await onDone(); }catch(ex){ ui.toast(ex.message,'err'); }
}
