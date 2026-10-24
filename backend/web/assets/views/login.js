import { api } from '../api.js';
import { icon } from '../ui.js';

export function renderLogin(root, onSuccess){
  root.innerHTML = `
  <div class="login-screen">
    <section class="login-hero">
      <div class="login-brand">
        <div class="mark">U</div>
        <div><h1>UNIÓN</h1><p>Gestión de Transporte</p></div>
      </div>
      <div class="login-copy">
        <h2>Todo el día.<br><span>En un solo lugar.</span></h2>
        <p>Colectivos, camión, recaudación, combustible y mantenimiento. Reportes diarios profesionales, con trazabilidad y control de cada viaje.</p>
      </div>
      <div class="login-features">
        <div class="login-feature"><strong>Operación diaria</strong><span>Colectivos, boletos y cierre</span></div>
        <div class="login-feature"><strong>Flota</strong><span>Mantenimiento y combustible</span></div>
        <div class="login-feature"><strong>Reportes</strong><span>Diarios, mensuales y CSV</span></div>
      </div>
    </section>
    <section class="login-panel">
      <div class="login-card">
        <h3>Ingresar</h3>
        <p class="sub">Acceso al sistema de gestión de la empresa.</p>
        <div class="form-error" id="login-error"></div>
        <form id="login-form" novalidate>
          <div class="field" style="margin-bottom:12px">
            <label for="lu">Usuario</label>
            <input id="lu" name="username" autocomplete="username" placeholder="Usuario" required>
          </div>
          <div class="field" style="margin-bottom:16px">
            <label for="lp">Contraseña</label>
            <input id="lp" name="password" type="password" autocomplete="current-password" placeholder="••••••••" required>
          </div>
          <button class="btn" type="submit" style="width:100%;height:42px" id="login-btn">${icon('lock')} Ingresar</button>
        </form>
      </div>
    </section>
  </div>`;

  const form = root.querySelector('#login-form');
  const err = root.querySelector('#login-error');
  const btn = root.querySelector('#login-btn');
  form.onsubmit = async (e) => {
    e.preventDefault();
    err.classList.remove('show');
    btn.disabled = true;
    try {
      const data = await api.login(form.username.value.trim(), form.password.value);
      await onSuccess(data);
    } catch (ex) {
      err.textContent = ex.message || 'No se pudo iniciar sesión';
      err.classList.add('show');
    } finally {
      btn.disabled = false;
    }
  };
  setTimeout(() => form.username.focus(), 40);
}

