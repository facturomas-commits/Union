import { api } from '../api.js';
import { state, canWrite, canSeeMoney } from '../store.js';
import * as ui from '../ui.js';

function defaultDate(){
  return (state.latest && state.latest.service_date) || state.today;
}

function kpi(label, value, foot, iconName, cls='', small=false){
  return `<div class="card kpi ${cls}">
    <div class="ico">${ui.icon(iconName)}</div>
    <div class="label">${label}</div>
    <div class="value money ${small?'small':''}">${value}</div>
    <div class="foot">${foot}</div>
  </div>`;
}

function serviceRows(rows){
  if (!rows || !rows.length) return `<tr><td colspan="${canSeeMoney()?8:6}">${ui.emptyState('Sin colectivos cargados','No hay colectivos para la fecha seleccionada.','bus')}</td></tr>`;
  return rows.map(s=>{
    const dir = s.direction==='vuelta'
      ? '<span class="badge purple">Vuelta</span>'
      : '<span class="badge blue">Ida</span>';
    const moneyCells = canSeeMoney()
      ? `<td class="num">${ui.money(s.revenue)}</td>
         <td class="num ${Number(s.surplus)<0?'neg':'pos'}">${ui.money(s.surplus)}</td>`
      : '';
    return `<tr>
    <td class="nowrap"><strong>${ui.timeHM(s.departure_time)}</strong><div class="sub">${ui.esc(s.schedule_label||'')}</div></td>
    <td>${dir}</td>
    <td><strong>#${ui.esc(s.vehicle_no)}</strong><div class="sub">${ui.esc(s.service_origin||'')} → ${ui.esc(s.service_destination||'')}</div></td>
    <td>${ui.esc(s.driver_name||'—')}<div class="sub">${ui.esc(s.guard_name||'')}</div></td>
    <td class="num">${ui.integer(s.tickets_count)}</td>
    ${moneyCells}
    <td>${ui.statusBadge(s.status)}</td>
  </tr>`;}).join('');
}

function alertRows(rows){
  if (!rows || !rows.length) return `<div class="empty" style="padding:24px 14px">${ui.icon('check',22)}<strong>Sin alertas</strong><span>Todo en orden para la fecha.</span></div>`;
  return rows.map(a=>{
    const cls = a.kind==='negative_surplus' ? 'red' : (a.kind==='open_service' ? 'blue' : '');
    const ico = a.kind==='maintenance' ? 'wrench' : (a.kind==='negative_surplus' ? 'alert' : 'bus');
    const when = a.kind==='maintenance' ? (Number(a.days_left) < 0 ? `Vencido ${Math.abs(a.days_left)} d` : `En ${a.days_left} d`) : '';
    return `<div class="alert-item">
      <div class="alert-ico ${cls}">${ui.icon(ico)}</div>
      <div><strong>${ui.esc(a.message)}</strong><span>${a.kind==='maintenance'?'Coche #'+ui.esc(a.reference):'Coche #'+ui.esc(a.reference)}</span></div>
      <div class="when">${ui.esc(when)}</div>
    </div>`;
  }).join('');
}

function recentRows(rows){
  if (!rows || !rows.length) return `<div class="empty" style="padding:22px 14px"><strong>Sin actividad</strong><span>Las acciones quedan registradas acá.</span></div>`;
  const actions={login:'Ingresó',logout:'Salió',create:'Creó',update:'Actualizó',delete:'Eliminó',close:'Cerró',reopen:'Reabrió'};
  return rows.map(r=>`<div class="list-row">
    <div class="avatar-sm">${ui.initials(r.username||'?')}</div>
    <div class="grow"><strong>${ui.esc(actions[r.action]||r.action)} ${ui.esc(r.entity)}${r.entity_id?' #'+r.entity_id:''}</strong><span>${ui.esc(r.username||'')}</span></div>
    <div class="tiny muted">${ui.dateTime(r.created_at)}</div>
  </div>`).join('');
}

export default {
  title:'Dashboard',
  subtitle:'Resumen operativo y financiero del día',
  async render(root){
    const date = defaultDate();
    root.innerHTML = `
      <div class="page-head">
        <div>
          <div class="page-title">Dashboard</div>
          <div class="page-sub">Resumen operativo y financiero del día</div>
        </div>
        <div class="actions">
          <div class="field" style="min-width:150px">
            <label>Fecha</label>
            <input type="date" id="dash-date" value="${date}">
          </div>
          <a class="btn btn-secondary" href="#/reports">${ui.icon('chart')} Reporte</a>
          ${canWrite()?`<a class="btn" href="#/colectivos">${ui.icon('plus')} Nuevo colectivo</a>`:''}
        </div>
      </div>
      <div id="dash-body"></div>`;

    const body = root.querySelector('#dash-body');
    const dateInput = root.querySelector('#dash-date');
    dateInput.onchange = () => load(body, dateInput.value);
    await load(body, date);
  }
};

async function load(body, date){
  ui.loading(body, 6);
  try{
    const d = await api.dashboard(date);
    const t = d.totals || {};
    const ft = d.freight_totals || {};
    const c = d.consolidated || {};
    const marginCls = Number(c.margin) < 0 ? 'neg' : 'pos';
    const series = (d.series||[]).map(x=>({ ...x, label: ui.dateShort(x.date) }));
    const recent = (d.recent||[]).slice(0,6);

    body.innerHTML = `
      <div class="grid grid-kpi" style="margin-bottom:16px">
        ${canSeeMoney()?`
        ${kpi('Recaudación', ui.money(t.revenue), `${ui.integer(t.services)} salidas · ${ui.integer(t.tickets)} boletos`, 'coins', 'accent')}
        ${kpi('Sobrante', ui.money(t.surplus), 'Recaudación menos deducciones', 'chart', Number(t.surplus)<0?'red':'green')}
        ${kpi('Gasoil', ui.money(t.fuel_amount), `${ui.num(t.fuel_liters)} litros`, 'fuel', 'orange')}
        ${kpi('Km recorridos', ui.integer(t.km), `${ui.num(c.bus_km_per_liter,2)} km/l`, 'route')}
        ${kpi('Camión (neto)', ui.money(ft.net_amount), `${ui.integer(ft.trips)} viajes · ${ui.integer(ft.kilos)} kg`, 'truck', 'purple')}
        ${kpi('Margen del día', ui.money(c.margin), `Costos ${ui.money(c.total_costs)}`, 'dashboard', marginCls)}
        `:`
        ${kpi('Salidas', ui.integer(t.services), 'Colectivos del día', 'bus', 'accent')}
        ${kpi('Boletos', ui.integer(t.tickets), 'Pasajes registrados', 'receipt')}
        ${kpi('Km recorridos', ui.integer(t.km), 'Colectivos', 'route')}
        ${kpi('Camión', ui.integer(ft.trips), `${ui.integer(ft.kilos)} kg transportados`, 'truck', 'purple')}
        `}
      </div>

      <div class="grid ${canSeeMoney()?'grid-main':''}" style="margin-bottom:16px">
        ${canSeeMoney()?`<div class="card">
          <div class="card-head"><h3>Últimos 7 días</h3><span class="hint">Recaudación vs. sobrante</span></div>
          <div class="card-body">${ui.barChart(series, [
            {key:'revenue', label:'Recaudación', cls:'bar-rev', color:'#1d528d'},
            {key:'surplus', label:'Sobrante', cls:'bar-sur', color:'#0ea5e9'}
          ], {height:230})}</div>
        </div>`:''}
        <div class="card">
          <div class="card-head"><h3>Alertas</h3><span class="hint">${(d.alerts||[]).length} pendientes</span></div>
          <div class="alert-list">${alertRows((d.alerts||[]).slice(0,5))}</div>
          ${(d.alerts||[]).length>5?`<div class="card-footer"><a class="btn btn-sm btn-secondary" href="#/maintenance">Ver todas las alertas ${ui.icon('arrow')}</a></div>`:''}
        </div>
      </div>

      <div class="card" style="margin-bottom:16px">
        <div class="card-head">
          <h3>Colectivos del día</h3>
          <span class="hint">${ui.dateDMY(d.date)} · ${ui.integer(t.open_services)} abiertos</span>
        </div>
        <div class="table-wrap">
          <table class="data">
            <thead><tr><th>Horario</th><th>Dir.</th><th>Coche / Recorrido</th><th>Chofer / Guarda</th><th class="num">Boletos</th>${canSeeMoney()?'<th class="num">Recaudación</th><th class="num">Sobrante</th>':''}<th>Estado</th></tr></thead>
            <tbody>${serviceRows(d.services)}</tbody>
          </table>
        </div>
        <div class="card-footer" style="display:flex;justify-content:space-between;align-items:center">
          <span class="tiny muted">Los montos están en pesos argentinos.</span>
          <a class="btn btn-sm btn-secondary" href="#/colectivos">Ver colectivos ${ui.icon('arrow')}</a>
        </div>
      </div>

      <div class="grid grid-2">
        <div class="card">
          <div class="card-head"><h3>Camión</h3><span class="hint">${ui.integer(ft.trips)} viajes</span></div>
          <div class="card-body" style="display:grid;gap:10px">
            <div style="display:flex;justify-content:space-between"><span class="muted">Kilos</span><strong>${ui.integer(ft.kilos)}</strong></div>
            ${canSeeMoney()?`
            <div style="display:flex;justify-content:space-between"><span class="muted">Neto</span><strong>${ui.money(ft.net_amount)}</strong></div>
            <div style="display:flex;justify-content:space-between"><span class="muted">IVA</span><strong>${ui.money(ft.vat_amount)}</strong></div>
            <div style="display:flex;justify-content:space-between"><span class="muted">Total</span><strong>${ui.money(ft.total_amount)}</strong></div>
            <div style="display:flex;justify-content:space-between"><span class="muted">Comisión chofer</span><strong>${ui.money(ft.driver_commission)}</strong></div>`:''}
            <a class="btn btn-sm btn-secondary" href="#/freight" style="margin-top:4px">Ver camión ${ui.icon('arrow')}</a>
          </div>
        </div>
        <div class="card">
          <div class="card-head"><h3>Actividad reciente</h3><span class="hint">Últimos movimientos</span></div>
          <div class="list-simple">${recentRows(recent)}</div>
        </div>
      </div>`;
    body.querySelectorAll('a[href^="#/"]').forEach(a=>{});
  }catch(ex){
    body.innerHTML = `<div class="card">${ui.emptyState('No se pudo cargar el dashboard', ex.message, 'alert')}</div>`;
    ui.toast(ex.message,'err');
  }
}


