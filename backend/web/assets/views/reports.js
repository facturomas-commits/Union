import { api } from '../api.js';
import { state } from '../store.js';
import * as ui from '../ui.js';

function defaultDate(){ return (state.latest&&state.latest.service_date)||state.today; }
function defaultMonth(){ return defaultDate().slice(0,7); }

function reportHead(subtitle){
  const c=state.company||{};
  return `<div class="report-head">
    <div>
      <div class="company">${ui.esc(c.name||'Empresa Unión')}</div>
      <div class="meta">${ui.esc(c.legal_name||'De LS Transporte SRL')}${c.cuit?' · CUIT '+ui.esc(c.cuit):''}<br>${ui.esc(c.address||'')}</div>
    </div>
    <div class="stamp">
      <strong style="color:var(--text);font-size:12px">${ui.esc(subtitle)}</strong><br>
      Emitido ${new Date().toLocaleString('es-AR')}<br>
      Usuario: ${ui.esc(state.user?.full_name||'')}
    </div>
  </div>`;
}

function summary(cells){
  return `<div class="summary-strip">${cells.map(c=>`<div class="summary-cell"><div class="l">${ui.esc(c[0])}</div><div class="v money ${c[2]||''}">${c[1]}</div></div>`).join('')}</div>`;
}

export default {
  title:'Reportes',
  subtitle:'Reporte diario y mensual, listo para imprimir o exportar',
  async render(root){
    root.innerHTML=`
      <div class="page-head no-print">
        <div><div class="page-title">Reportes</div><div class="page-sub">Reporte diario y mensual, listo para imprimir o exportar</div></div>
        <div class="actions">
          <div class="segmented" id="tabs">
            <button class="active" data-tab="daily">Diario</button>
            <button data-tab="monthly">Mensual</button>
          </div>
        </div>
      </div>
      <div class="card no-print" style="margin-bottom:16px">
        <div class="filters" style="border-bottom:0">
          <div class="field" id="period-daily"><label>Fecha</label><input type="date" id="r-date" value="${defaultDate()}"></div>
          <div class="field" id="period-monthly" style="display:none"><label>Mes</label><input type="month" id="r-month" value="${defaultMonth()}"></div>
          <div class="spacer"></div>
          <button class="btn btn-secondary" id="btn-print">${ui.icon('print')} Imprimir / PDF</button>
          <button class="btn btn-secondary" id="btn-csv">${ui.icon('download')} Excel (CSV)</button>
        </div>
      </div>
      <div id="report" class="print-area"></div>`;

    const report=root.querySelector('#report');
    let tab='daily';
    const dateInput=root.querySelector('#r-date');
    const monthInput=root.querySelector('#r-month');

    async function load(){
      if(tab==='daily') await loadDaily(report,dateInput.value);
      else await loadMonthly(report,monthInput.value);
    }

    root.querySelectorAll('#tabs button').forEach(b=>b.onclick=()=>{
      tab=b.dataset.tab;
      root.querySelectorAll('#tabs button').forEach(x=>x.classList.toggle('active',x===b));
      root.querySelector('#period-daily').style.display=tab==='daily'?'flex':'none';
      root.querySelector('#period-monthly').style.display=tab==='monthly'?'flex':'none';
      load();
    });
    dateInput.onchange=load; monthInput.onchange=load;
    root.querySelector('#btn-print').onclick=()=>window.print();
    root.querySelector('#btn-csv').onclick=()=>tab==='daily'?api.exportDaily(dateInput.value):api.exportMonthly(monthInput.value);
    await load();
  }
};

async function loadDaily(report,date){
  ui.loading(report,8);
  try{
    const d=await api.daily(date);
    const t=d.totals||{}, ft=d.freight_totals||{}, c=d.consolidated||{};
    const services=d.services||[], freight=d.freight||[], maint=d.maintenance||[], general=d.general_expenses||[];
    const catLabels={oncology:'Oncológico',ticket_office:'Boleterías',mp:'Mercado Pago',other:'Otros'};
    const ded=Number(t.oncology_amount||0)+Number(t.ticket_office_amount||0)+Number(t.mp_amount||0)+Number(t.other_amount||0);
    const alerts=(d.alerts||[]).slice(0,6);

    report.innerHTML=`
      ${reportHead('REPORTE DIARIO DE OPERACIONES')}
      <div style="display:flex;justify-content:space-between;margin-bottom:12px;font-size:12px">
        <div><b>Fecha:</b> ${ui.dateDMY(d.date)}</div>
        <div><b>Servicios:</b> ${ui.integer(t.services)} · <b>Boletos:</b> ${ui.integer(t.tickets)} · <b>Km:</b> ${ui.integer(t.km)}</div>
      </div>
      ${summary([
        ['Recaudación',ui.money(t.revenue),''],
        ['Gasoil',ui.money(t.fuel_amount),''],
        ['Deducciones',ui.money(ded),''],
        ['Sobrante',ui.money(t.surplus),t.surplus<0?'neg':'pos'],
      ])}
      <div class="report-section">
        <h4>Colectivos · servicios del día</h4>
        <div class="table-wrap"><table class="data report-table">
          <thead><tr><th>Horario</th><th>Coche</th><th>Chofer</th><th>Guarda</th><th>Boletos</th><th class="num">Cant.</th><th class="num">Recaudación</th><th class="num">Gasoil</th><th class="num">Deducciones</th><th class="num">Sobró</th><th class="num">Km</th><th>Estado</th></tr></thead>
          <tbody>${services.length?services.map(s=>{
            const rowDed=Number(s.oncology_amount||0)+Number(s.ticket_office_amount||0)+Number(s.mp_amount||0)+Number(s.other_amount||0);
            return `<tr>
            <td>${ui.timeHM(s.departure_time)}<div class="sub">${ui.esc(s.schedule_label||'')}</div></td>
            <td>#${ui.esc(s.vehicle_no)}</td>
            <td>${ui.esc(s.driver_name||'—')}</td>
            <td>${ui.esc(s.guard_name||'—')}</td>
            <td class="num">${s.ticket_from??'—'}–${s.ticket_to??'—'}</td>
            <td class="num">${ui.integer(s.tickets_count)}</td>
            <td class="num">${ui.money(s.revenue)}</td>
            <td class="num">${ui.money(s.fuel_amount)}<div class="sub">${ui.num(s.fuel_liters)} L</div></td>
            <td class="num">${ui.money(rowDed)}</td>
            <td class="num ${Number(s.surplus)<0?'neg':''}"><strong>${ui.money(s.surplus)}</strong></td>
            <td class="num">${ui.integer(s.km)}</td>
            <td>${s.status==='closed'?'Cerrado':'Abierto'}</td>
          </tr>`;}).join(''):`<tr><td colspan="12" style="text-align:center;padding:18px;color:var(--muted)">Sin servicios</td></tr>`}</tbody>
          <tfoot><tr style="background:#f8fafc;font-weight:900">
            <td colspan="5">TOTALES</td><td class="num">${ui.integer(t.tickets)}</td><td class="num">${ui.money(t.revenue)}</td><td class="num">${ui.money(t.fuel_amount)} / ${ui.num(t.fuel_liters)} L</td><td class="num">${ui.money(ded)}</td><td class="num">${ui.money(t.surplus)}</td><td class="num">${ui.integer(t.km)}</td><td></td>
          </tr></tfoot>
        </table></div>
      </div>

      <div class="report-section">
        <h4>Camión · viajes y remitos</h4>
        <div class="table-wrap"><table class="data">
          <thead><tr><th>Viaje</th><th>Camión</th><th>Chofer</th><th class="num">Remitos</th><th class="num">Kilos</th><th class="num">Neto</th><th class="num">IVA</th><th class="num">Total</th><th class="num">Comisión</th><th class="num">Km</th></tr></thead>
          <tbody>${freight.length?freight.map(x=>`<tr>
            <td>#${x.id}</td><td>#${ui.esc(x.vehicle_no)}</td><td>${ui.esc(x.driver_name||'—')}</td>
            <td class="num">${ui.integer(x.items_count)}</td><td class="num">${ui.integer(x.kilos)}</td>
            <td class="num">${ui.money(x.net_amount)}</td><td class="num">${ui.money(x.vat_amount)}</td>
            <td class="num"><strong>${ui.money(x.total_amount)}</strong></td><td class="num">${ui.money(x.driver_commission)}</td><td class="num">${ui.integer(x.km)}</td>
          </tr>`).join(''):`<tr><td colspan="10" style="text-align:center;padding:18px;color:var(--muted)">Sin viajes</td></tr>`}</tbody>
          <tfoot><tr style="background:#f8fafc;font-weight:900"><td colspan="3">TOTALES</td><td class="num">${ui.integer(ft.trips)}</td><td class="num">${ui.integer(ft.kilos)}</td><td class="num">${ui.money(ft.net_amount)}</td><td class="num">${ui.money(ft.vat_amount)}</td><td class="num">${ui.money(ft.total_amount)}</td><td class="num">${ui.money(ft.driver_commission)}</td><td class="num">${ui.integer(ft.km)}</td></tr></tfoot>
        </table></div>
      </div>

      ${maint.length?`<div class="report-section"><h4>Mantenimiento del día</h4>
        <div class="table-wrap"><table class="data"><thead><tr><th>Coche</th><th>Rubro</th><th>Concepto</th><th>Medidas</th><th>Próximo cambio</th><th class="num">Costo</th></tr></thead>
        <tbody>${maint.map(m=>`<tr><td>#${ui.esc(m.vehicle_no)}</td><td>${ui.esc(m.category)}</td><td>${ui.esc(m.concept)}</td><td>${ui.esc(m.measures||'—')}</td><td>${m.next_due?ui.dateDMY(m.next_due):'—'}</td><td class="num">${ui.money(m.cost)}</td></tr>`).join('')}</tbody></table></div>
      </div>`:''}

      ${general.length?`<div class="report-section"><h4>Gastos generales del día</h4>
        <div class="table-wrap"><table class="data"><thead><tr><th>Categoría</th><th>Concepto</th><th>Vehículo</th><th class="num">Importe</th></tr></thead>
        <tbody>${general.map(g=>`<tr><td>${ui.esc(catLabels[g.category]||g.category)}</td><td>${ui.esc(g.description||'—')}</td><td>${g.vehicle_no?'#'+ui.esc(g.vehicle_no):'—'}</td><td class="num">${ui.money(g.amount)}</td></tr>`).join('')}</tbody>
        <tfoot><tr style="background:#f8fafc;font-weight:900"><td colspan="3">TOTAL</td><td class="num">${ui.money(d.general_total)}</td></tr></tfoot></table></div>
      </div>`:''}

      <div class="report-section">
        <h4>Consolidado del día</h4>
        <div class="summary-strip" style="grid-template-columns:repeat(4,1fr)">
          <div class="summary-cell"><div class="l">Ingreso neto</div><div class="v">${ui.money(c.total_income_net)}</div></div>
          <div class="summary-cell"><div class="l">Costos</div><div class="v">${ui.money(c.total_costs)}</div></div>
          <div class="summary-cell"><div class="l">Margen</div><div class="v ${Number(c.margin)<0?'neg':'pos'}">${ui.money(c.margin)}</div></div>
          <div class="summary-cell"><div class="l">Km totales</div><div class="v">${ui.integer(c.total_km)}</div></div>
        </div>
        <div class="tiny muted" style="margin-top:8px">
          Colectivos: ${ui.money(c.bus_revenue)} de recaudación · ${ui.money(c.bus_fuel)} de gasoil · ${ui.money(c.bus_deductions)} de deducciones · ${ui.num(c.bus_km_per_liter)} km/l.
          Camión: ${ui.money(c.freight_net)} neto · ${ui.money(c.freight_commission)} comisión chofer.
          Mantenimiento: ${ui.money(c.maintenance)}. Gastos generales: ${ui.money(c.general_expenses)}.
        </div>
      </div>
      ${alerts.length?`<div class="report-section"><h4>Alertas (${(d.alerts||[]).length})</h4><div class="alert-list card">${alerts.map(a=>`<div class="alert-item"><div class="alert-ico ${a.kind==='negative_surplus'?'red':(a.kind==='open_service'?'blue':'')}">${ui.icon(a.kind==='maintenance'?'wrench':'alert')}</div><div><strong>${ui.esc(a.message)}</strong><span>Coche #${ui.esc(a.reference)}</span></div><div class="when">${a.kind==='maintenance'?(Number(a.days_left)<0?'Vencido hace '+Math.abs(a.days_left)+' d':'En '+a.days_left+' d'):''}</div></div>`).join('')}${(d.alerts||[]).length>6?`<div class="alert-item"><div class="alert-ico blue">${ui.icon('alert')}</div><div><strong>Hay ${(d.alerts||[]).length-6} alertas más</strong><span>Consulte la sección Mantenimiento para verlas todas.</span></div></div>`:''}</div></div>`:''}
      <div class="tiny muted" style="text-align:right">Documento generado por UNION · ${new Date().toLocaleString('es-AR')}</div>`;
  }catch(ex){
    report.innerHTML=`<div class="card">${ui.emptyState('No se pudo generar el reporte',ex.message,'alert')}</div>`;
  }
}

async function loadMonthly(report,month){
  ui.loading(report,8);
  try{
    const m=await api.monthly(month);
    const t=m.totals||{}, ft=m.freight_totals||{}, c=m.consolidated||{};
    const days=(m.days||[]).filter(d=>Number(d.revenue)||Number(d.freight_net)||Number(d.maintenance)||Number(d.general));
    const chartDays=(m.days||[]).map(d=>({...d,label:ui.dateShort(d.date)}));
    report.innerHTML=`
      ${reportHead('REPORTE MENSUAL DE OPERACIONES')}
      <div style="display:flex;justify-content:space-between;margin-bottom:12px;font-size:12px">
        <div><b>Período:</b> ${ui.esc(ui.monthLabel(m.month))}</div>
        <div><b>Servicios:</b> ${ui.integer(t.services)} · <b>Boletos:</b> ${ui.integer(t.tickets)} · <b>Km:</b> ${ui.integer(c.total_km)}</div>
      </div>
      ${summary([
        ['Recaudación',ui.money(t.revenue),''],
        ['Sobrante',ui.money(t.surplus),Number(t.surplus)<0?'neg':'pos'],
        ['Camión neto',ui.money(ft.net_amount),''],
        ['Margen',ui.money(c.margin),Number(c.margin)<0?'neg':'pos'],
      ])}
      <div class="report-section">
        <h4>Evolución diaria</h4>
        <div class="card"><div class="card-body">${ui.lineChart(chartDays,[
          {key:'revenue',label:'Recaudación',cls:'line-rev',color:'#1d528d'},
          {key:'surplus',label:'Sobrante',cls:'line-sur',color:'#0ea5e9'}
        ],{height:220})}</div></div>
      </div>
      <div class="report-section">
        <h4>Por vehículo</h4>
        <div class="table-wrap"><table class="data"><thead><tr><th>Coche</th><th class="num">Servicios</th><th class="num">Boletos</th><th class="num">Km</th><th class="num">Recaudación</th><th class="num">Gasoil</th><th class="num">Sobrante</th></tr></thead>
        <tbody>${(m.vehicles||[]).map(v=>`<tr><td><strong>#${ui.esc(v.vehicle_no)}</strong></td><td class="num">${ui.integer(v.services)}</td><td class="num">${ui.integer(v.tickets)}</td><td class="num">${ui.integer(v.km)}</td><td class="num">${ui.money(v.revenue)}</td><td class="num">${ui.money(v.fuel)}</td><td class="num ${Number(v.surplus)<0?'neg':'pos'}">${ui.money(v.surplus)}</td></tr>`).join('')||`<tr><td colspan="7" style="text-align:center;padding:16px;color:var(--muted)">Sin datos</td></tr>`}</tbody></table></div>
      </div>
      <div class="report-section">
        <h4>Por chofer</h4>
        <div class="table-wrap"><table class="data"><thead><tr><th>Chofer</th><th class="num">Servicios</th><th class="num">Km</th><th class="num">Recaudación</th><th class="num">Sobrante</th></tr></thead>
        <tbody>${(m.drivers||[]).map(v=>`<tr><td>${ui.esc(v.driver_name)}</td><td class="num">${ui.integer(v.services)}</td><td class="num">${ui.integer(v.km)}</td><td class="num">${ui.money(v.revenue)}</td><td class="num">${ui.money(v.surplus)}</td></tr>`).join('')||`<tr><td colspan="5" style="text-align:center;padding:16px;color:var(--muted)">Sin datos</td></tr>`}</tbody></table></div>
      </div>
      <div class="report-section">
        <h4>Días con movimiento</h4>
        <div class="table-wrap"><table class="data"><thead><tr><th>Fecha</th><th class="num">Recaudación</th><th class="num">Gasoil</th><th class="num">Sobrante</th><th class="num">Boletos</th><th class="num">Km</th><th class="num">Camión neto</th><th class="num">Mantenimiento</th><th class="num">Gastos grales</th></tr></thead>
        <tbody>${days.map(d=>`<tr><td>${ui.dateDMY(d.date)}</td><td class="num">${ui.money(d.revenue)}</td><td class="num">${ui.money(d.fuel)}</td><td class="num ${Number(d.surplus)<0?'neg':''}">${ui.money(d.surplus)}</td><td class="num">${ui.integer(d.tickets)}</td><td class="num">${ui.integer(d.km)}</td><td class="num">${ui.money(d.freight_net)}</td><td class="num">${ui.money(d.maintenance)}</td><td class="num">${ui.money(d.general)}</td></tr>`).join('')||`<tr><td colspan="9" style="text-align:center;padding:16px;color:var(--muted)">Sin datos</td></tr>`}</tbody></table></div>
      </div>
      <div class="report-section">
        <h4>Consolidado del mes</h4>
        <div class="summary-strip" style="grid-template-columns:repeat(4,1fr)">
          <div class="summary-cell"><div class="l">Ingreso neto</div><div class="v">${ui.money(c.total_income_net)}</div></div>
          <div class="summary-cell"><div class="l">Costos</div><div class="v">${ui.money(c.total_costs)}</div></div>
          <div class="summary-cell"><div class="l">Margen</div><div class="v ${Number(c.margin)<0?'neg':'pos'}">${ui.money(c.margin)}</div></div>
          <div class="summary-cell"><div class="l">Km totales</div><div class="v">${ui.integer(c.total_km)}</div></div>
        </div>
      </div>
      <div class="tiny muted" style="text-align:right">Documento generado por UNION · ${new Date().toLocaleString('es-AR')}</div>`;
  }catch(ex){
    report.innerHTML=`<div class="card">${ui.emptyState('No se pudo generar el reporte',ex.message,'alert')}</div>`;
  }
}
