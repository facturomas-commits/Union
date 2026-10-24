import { api } from '../api.js';
import { hasModule } from '../store.js';
import * as ui from '../ui.js';

const ACTIONS={login:'Ingreso',login_failed:'Ingreso fallido',logout:'Salida',create:'Alta',update:'Modificación',delete:'Baja',close:'Cierre',reopen:'Reapertura',change_password:'Cambio de clave'};

export default {
  title:'Auditoría',
  subtitle:'Trazabilidad de accesos y cambios',
  async render(root){
    if(!hasModule('audit')){
      root.innerHTML=`<div class="card">${ui.emptyState('Acceso restringido','No tiene permiso para ver la auditoría.','lock')}</div>`;
      return;
    }
    root.innerHTML=`
      <div class="page-head">
        <div><div class="page-title">Auditoría</div><div class="page-sub">Trazabilidad de accesos y cambios</div></div>
        <div class="actions">
          <div class="field" style="min-width:120px"><label>Registros</label><select id="limit"><option>100</option><option selected>200</option><option>500</option><option>1000</option></select></div>
          <button class="btn btn-secondary" id="reload">${ui.icon('refresh')} Actualizar</button>
        </div>
      </div>
      <div class="card"><div class="table-wrap"><table class="data">
        <thead><tr><th>Fecha / hora</th><th>Usuario</th><th>Acción</th><th>Entidad</th><th>ID</th><th>Detalle</th></tr></thead>
        <tbody id="tbody"></tbody>
      </table></div></div>`;
    const tbody=root.querySelector('#tbody');
    async function load(){
      ui.loading(tbody,6);
      try{
        const rows=await api.audit(root.querySelector('#limit').value);
        tbody.innerHTML=rows.length?rows.map(r=>`<tr>
          <td class="nowrap">${ui.dateTime(r.created_at)}</td>
          <td><strong>${ui.esc(r.username||'—')}</strong></td>
          <td><span class="badge ${r.action==='delete'?'red':(r.action==='create'?'green':(r.action.includes('login')?'blue':'gray'))}">${ui.esc(ACTIONS[r.action]||r.action)}</span></td>
          <td>${ui.esc(r.entity||'—')}</td>
          <td class="num">${r.entity_id||'—'}</td>
          <td class="sub" style="max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${ui.esc(JSON.stringify(r.details))}">${ui.esc(JSON.stringify(r.details||{}))}</td>
        </tr>`).join(''):`<tr><td colspan="6">${ui.emptyState('Sin registros','La actividad aparecerá acá.','audit')}</td></tr>`;
      }catch(ex){ tbody.innerHTML=`<tr><td colspan="6">${ui.emptyState('No se pudo cargar',ex.message,'alert')}</td></tr>`; }
    }
    root.querySelector('#reload').onclick=load;
    root.querySelector('#limit').onchange=load;
    await load();
  }
};
