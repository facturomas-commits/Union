import { api, qs } from '../api.js';
import { state, canWrite } from '../store.js';
import * as ui from '../ui.js';

let cache=null;
async function catalogs(){
  if(cache) return cache;
  const [vehicles,drivers]=await Promise.all([api.get('/vehicles'),api.get('/employees?kind=driver&active=1')]);
  cache={ vehicles:vehicles.filter(v=>v.active!==false&&v.kind==='truck'), drivers };
  return cache;
}
function range(){
  const base=(state.latest&&state.latest.freight_date)||state.today;
  return { from: base.slice(0,7)+'-01', to: base };
}

function rowsHtml(rows){
  if(!rows.length) return `<tr><td colspan="10">${ui.emptyState('Sin viajes','No hay viajes de camión en el rango.','truck')}</td></tr>`;
  return rows.map(t=>`<tr>
    <td class="nowrap">${ui.dateDMY(t.trip_date)}</td>
    <td><strong>#${ui.esc(t.vehicle_no)}</strong><div class="sub">${ui.esc(t.plate||'')}</div></td>
    <td>${ui.esc(t.driver_name||'—')}</td>
    <td class="num">${ui.integer(t.items_count)}</td>
    <td class="num">${ui.integer(t.kilos)}</td>
    <td class="num">${ui.money(t.net_amount)}</td>
    <td class="num">${ui.money(t.vat_amount)}</td>
    <td class="num"><strong>${ui.money(t.total_amount)}</strong></td>
    <td class="num">${ui.money(t.driver_commission)}</td>
    <td><div class="table-actions">
      <button class="btn btn-sm btn-secondary btn-icon" data-view="${t.id}" title="Ver remitos">${ui.icon('eye',14)}</button>
      ${canWrite()?`<button class="btn btn-sm btn-secondary btn-icon" data-edit="${t.id}" title="Editar">${ui.icon('edit',14)}</button>
      <button class="btn btn-sm btn-secondary btn-icon" data-del="${t.id}" title="Eliminar">${ui.icon('trash',14)}</button>`:''}
    </div></td>
  </tr>`).join('');
}

export default {
  title:'Camión',
  subtitle:'Viajes, remitos, kilos, IVA y comisión del chofer',
  async render(root){
    const r=range();
    const c=await catalogs();
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Camión</div><div class="page-sub">Viajes, remitos, kilos, IVA y comisión del chofer</div></div>
        <div class="actions">${canWrite()?`<button class="btn" id="btn-new">${ui.icon('plus')} Nuevo viaje</button>`:''}</div>
      </div>
      <div class="card">
        <div class="filters">
          <div class="field"><label>Desde</label><input type="date" id="f-from" value="${r.from}"></div>
          <div class="field"><label>Hasta</label><input type="date" id="f-to" value="${r.to}"></div>
          <div class="field wide"><label>Camión</label><select id="f-vehicle"><option value="">Todos</option>${ui.options(c.vehicles,'id',v=>`#${v.internal_no}`)}</select></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-reload">${ui.icon('refresh')} Actualizar</button>
        </div>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Fecha</th><th>Camión</th><th>Chofer</th><th class="num">Remitos</th><th class="num">Kilos</th><th class="num">Neto</th><th class="num">IVA</th><th class="num">Total</th><th class="num">Comisión</th><th></th></tr></thead>
          <tbody id="tbody"></tbody>
        </table></div>
        <div class="card-footer" id="foot"></div>
      </div>`;
    const tbody=root.querySelector('#tbody'), foot=root.querySelector('#foot');

    async function load(){
      ui.loading(tbody,4);
      try{
        const rows=await api.get('/freight/trips'+qs({date_from:root.querySelector('#f-from').value,date_to:root.querySelector('#f-to').value,vehicle_id:root.querySelector('#f-vehicle').value}));
        tbody.innerHTML=rowsHtml(rows);
        const tot=rows.reduce((a,t)=>{a.k+=Number(t.kilos||0);a.n+=Number(t.net_amount||0);a.v+=Number(t.vat_amount||0);a.t+=Number(t.total_amount||0);a.c+=Number(t.driver_commission||0);return a;},{k:0,n:0,v:0,t:0,c:0});
        foot.innerHTML=`<div style="display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap;font-size:12px">
          <span><b>${rows.length}</b> viajes · <b>${ui.integer(tot.k)}</b> kg</span>
          <span>Neto <b>${ui.money(tot.n)}</b> · IVA <b>${ui.money(tot.v)}</b> · Total <b>${ui.money(tot.t)}</b> · Comisión <b>${ui.money(tot.c)}</b></span>
        </div>`;
        tbody.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>viewTrip(Number(b.dataset.view)));
        tbody.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openForm(Number(b.dataset.edit),onSaved,c));
        tbody.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>del(Number(b.dataset.del),onSaved));
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="10">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; }
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
    const nb=root.querySelector('#btn-new'); if(nb) nb.onclick=()=>openForm(null,onSaved,c);
    await load();
  }
};

function itemRow(it={}){
  return `<tr data-item>
    <td><input class="remito" value="${ui.esc(it.remito||'')}" placeholder="0005-9136" style="height:32px;width:100%;border:1px solid var(--border-strong);border-radius:6px;padding:0 7px"></td>
    <td><input class="origin" value="${ui.esc(it.origin||'')}" placeholder="Origen" style="height:32px;width:100%;border:1px solid var(--border-strong);border-radius:6px;padding:0 7px"></td>
    <td><input class="destination" value="${ui.esc(it.destination||'')}" placeholder="Destino" style="height:32px;width:100%;border:1px solid var(--border-strong);border-radius:6px;padding:0 7px"></td>
    <td><input class="kilos" type="number" step="0.01" value="${it.kilos??''}" placeholder="0" style="height:32px;width:100%;border:1px solid var(--border-strong);border-radius:6px;padding:0 7px;text-align:right"></td>
    <td><input class="tariff" type="number" step="0.01" value="${it.tariff??''}" placeholder="0" style="height:32px;width:100%;border:1px solid var(--border-strong);border-radius:6px;padding:0 7px;text-align:right"></td>
    <td class="num"><strong class="line-total">${ui.money(0)}</strong></td>
    <td><button type="button" class="btn btn-sm btn-secondary btn-icon" data-remove>${ui.icon('x',13)}</button></td>
  </tr>`;
}

function openForm(id,onDone,c){
  (async()=>{
    let trip=null;
    if(id){ const d=await api.get('/freight/trips/'+id); trip=d; }
    const t=trip?trip.trip:{};
    const items=trip&&trip.items.length?trip.items:[{}];
    const body=`
      <div class="form-grid cols-4">
        <div class="field"><label>Fecha *</label><input name="trip_date" type="date" value="${trip?t.trip_date:state.today}" required></div>
        <div class="field"><label>Camión *</label><select name="vehicle_id" required>${ui.options(c.vehicles,'id',v=>`#${v.internal_no}`,trip?t.vehicle_id:'')}</select></div>
        <div class="field"><label>Chofer</label><select name="driver_id"><option value="">—</option>${ui.options(c.drivers,'id',e=>e.full_name,trip?t.driver_id:'')}</select></div>
        <div class="field"><label>Comisión %</label><input name="commission_pct" type="number" step="0.01" value="${trip?t.commission_pct:15}"></div>
        <div class="field"><label>Km del viaje</label><input name="km" type="number" step="0.01" value="${trip?t.km:''}"></div>
        <div class="field" style="grid-column:span 3"><label>Notas</label><input name="notes" value="${ui.esc(t.notes||'')}"></div>
      </div>
      <div class="section-title" style="display:flex;justify-content:space-between;align-items:center">Remitos <button type="button" class="btn btn-sm btn-secondary" id="add-item">${ui.icon('plus',13)} Agregar remito</button></div>
      <div class="table-wrap" style="border:1px solid var(--border);border-radius:9px;overflow:hidden">
        <table class="data" style="font-size:11.5px">
          <thead><tr><th>Remito</th><th>Origen</th><th>Destino</th><th class="num">Kilos</th><th class="num">Tarifa $/t</th><th class="num">Neto</th><th></th></tr></thead>
          <tbody id="items-body">${items.map(itemRow).join('')}</tbody>
        </table>
      </div>
      <div class="summary-strip" style="margin-top:14px;margin-bottom:0;grid-template-columns:repeat(5,1fr)">
        ${['Kilos','Neto','IVA 21%','Total','Comisión'].map((l,i)=>`<div class="summary-cell"><div class="l">${l}</div><div class="v money" id="sum-${i}">$0,00</div></div>`).join('')}
      </div>`;

    ui.openModal({
      title:trip?'Editar viaje':'Nuevo viaje de camión',
      subtitle:trip?`Viaje #${id}`:'Cargue los remitos del viaje. Los importes se calculan automáticamente.',
      body, xwide:true, submitText:trip?'Guardar viaje':'Crear viaje',
      onReady(form){
        const itemsBody=form.querySelector('#items-body');
        const calc=()=>{
          let kilos=0, net=0;
          itemsBody.querySelectorAll('[data-item]').forEach(row=>{
            const k=Number(row.querySelector('.kilos').value)||0;
            const tariff=Number(row.querySelector('.tariff').value)||0;
            const n=Math.round(tariff*k/1000*100)/100;
            row.querySelector('.line-total').textContent=ui.money(n);
            kilos+=k; net+=n;
          });
          const pct=Number(form.elements.commission_pct.value)||0;
          const vat=Math.round(net*21)/100;
          const total=Math.round((net+vat)*100)/100;
          const comm=Math.round(net*pct)/100;
          const vals=[kilos,net,vat,total,comm];
          vals.forEach((v,i)=>{ const el=form.querySelector('#sum-'+i); el.textContent=i===0?ui.integer(v):ui.money(v); });
        };
        itemsBody.addEventListener('input',calc);
        itemsBody.addEventListener('click',e=>{
          const btn=e.target.closest('[data-remove]');
          if(btn){ btn.closest('tr').remove(); calc(); }
        });
        form.querySelector('#add-item').onclick=()=>{ itemsBody.insertAdjacentHTML('beforeend',itemRow()); calc(); };
        form.elements.commission_pct.addEventListener('input',calc);
        calc();
      },
      async onSubmit(form, close){
        const items=[];
        form.querySelectorAll('#items-body [data-item]').forEach(row=>{
          const k=Number(row.querySelector('.kilos').value)||0;
          const tariff=Number(row.querySelector('.tariff').value)||0;
          const remito=row.querySelector('.remito').value.trim();
          if(!remito && !k && !tariff) return;
          items.push({
            remito: remito||null,
            origin: row.querySelector('.origin').value.trim()||null,
            destination: row.querySelector('.destination').value.trim()||null,
            kilos:k, tariff
          });
        });
        const payload={
          trip_date:form.elements.trip_date.value,
          vehicle_id:Number(form.elements.vehicle_id.value),
          driver_id:form.elements.driver_id.value?Number(form.elements.driver_id.value):null,
          commission_pct:ui.numVal(form,'commission_pct',15),
          km:ui.numVal(form,'km'),
          notes:form.elements.notes.value,
          items,
        };
        if(!payload.trip_date||!payload.vehicle_id) throw new Error('Complete fecha y camión');
        if(!items.length) throw new Error('Agregue al menos un remito');
        if(trip) await api.put('/freight/trips/'+id,payload); else await api.post('/freight/trips',payload);
        ui.toast(trip?'Viaje actualizado':'Viaje creado','ok'); close(); await onDone(payload.trip_date);
      }
    });
  })().catch(ex=>ui.toast(ex.message,'err'));
}

async function viewTrip(id){
  try{
    const d=await api.get('/freight/trips/'+id);
    const t=d.trip||{}, items=d.items||[];
    ui.openModal({
      title:`Viaje #${id}`,
      subtitle:`${ui.dateDMY(t.trip_date)} · Camión #${t.vehicle_no} · ${t.driver_name||'Sin chofer'}`,
      wide:true, hideSubmit:true,
      body:`
        <div class="summary-strip" style="grid-template-columns:repeat(4,1fr)">
          <div class="summary-cell"><div class="l">Kilos</div><div class="v">${ui.integer(t.kilos)}</div></div>
          <div class="summary-cell"><div class="l">Neto</div><div class="v">${ui.money(t.net_amount)}</div></div>
          <div class="summary-cell"><div class="l">Total</div><div class="v">${ui.money(t.total_amount)}</div></div>
          <div class="summary-cell"><div class="l">Comisión chofer</div><div class="v">${ui.money(t.driver_commission)}</div></div>
        </div>
        <div class="table-wrap" style="border:1px solid var(--border);border-radius:9px;overflow:hidden">
          <table class="data"><thead><tr><th>Remito</th><th>Origen</th><th>Destino</th><th class="num">Kilos</th><th class="num">Tarifa</th><th class="num">Neto</th><th class="num">IVA</th><th class="num">Total</th></tr></thead>
          <tbody>${items.map(i=>`<tr><td>${ui.esc(i.remito||'—')}</td><td>${ui.esc(i.origin||'—')}</td><td>${ui.esc(i.destination||'—')}</td><td class="num">${ui.integer(i.kilos)}</td><td class="num">${ui.money(i.tariff)}</td><td class="num">${ui.money(i.net_amount)}</td><td class="num">${ui.money(i.vat_amount)}</td><td class="num"><strong>${ui.money(i.total_amount)}</strong></td></tr>`).join('')}</tbody>
          </table>
        </div>
        <div class="tiny muted" style="margin-top:10px">Comisión: ${t.commission_pct}% sobre el neto · Km: ${ui.integer(t.km)}</div>`
    });
  }catch(ex){ ui.toast(ex.message,'err'); }
}

async function del(id,onDone){
  if(!await ui.confirmDialog({title:'Eliminar viaje',message:'Se eliminará el viaje y todos sus remitos.',confirmText:'Eliminar'})) return;
  try{ await api.del('/freight/trips/'+id); ui.toast('Viaje eliminado','ok'); await onDone(); }catch(ex){ ui.toast(ex.message,'err'); }
}
