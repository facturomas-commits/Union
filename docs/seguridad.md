# Seguridad

## Autenticación y sesiones

- Contraseñas con **bcrypt** (`gen_salt('bf', 12)`) mediante `pgcrypto`.
- Mínimo **10 caracteres** para claves nuevas; se rechazan las claves iniciales conocidas.
- Los usuarios con `must_change_password = TRUE` no pueden usar el resto de la API hasta cambiar la clave. La web muestra una pantalla bloqueante.
- Cookie de sesión `union_session`:
  - `HttpOnly`
  - `SameSite=Lax`
  - `Secure` cuando la petición llega por HTTPS (`X-Forwarded-Proto`/`CF-Visitor`)
  - expiración configurable (`UNION_SESSION_HOURS`, por defecto 12 h)
- El token de sesión **no se devuelve al JavaScript**; solo viaja en la cookie.
- Al cambiar la contraseña se eliminan las demás sesiones del usuario.
- Al resetear una clave desde Usuarios, se cierran todas las sesiones y se obliga a cambiarla.
- Bloqueo temporal: después de **10 intentos fallidos por usuario o IP** en 15 minutos, `/api/auth/login` responde **429** con `Retry-After`.

## Autorización

- Roles: `superadmin`, `admin`, `supervisor`, `operator`, `viewer`.
- Módulos por usuario (`allowed_modules`) y permiso independiente de importes (`can_view_financials`).
- Los endpoints de escritura exigen rol con escritura y módulo habilitado.
- Solo un `superadmin` puede crear, modificar o eliminar superadmins.
- Los reportes y exportaciones requieren permiso de importes.
- Las respuestas JSON de usuarios sin importes se filtran en el backend.

## Protección de la aplicación

- SQL con parámetros; no se concatenan valores del usuario en las consultas.
- La interfaz escapa los datos dinámicos con `ui.esc` antes de insertarlos en HTML.
- Cabeceras en HTML/estáticos:
  - `Content-Security-Policy` con `script-src 'self'`
  - `X-Frame-Options: DENY` y `frame-ancestors 'none'`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: same-origin`
  - `Permissions-Policy` sin cámara, micrófono ni geolocalización
  - `Strict-Transport-Security`
- Respuestas de API con `Cache-Control: no-store`.
- Servidor escuchando en **127.0.0.1** por defecto; no debe abrirse el puerto al público.
- Servido de archivos estáticos con validación de nombre y bloqueo de `..`, `/` y `\`.
- Auditoría de accesos, altas, cambios, bajas, cierres e intentos fallidos.

## Cloudflared

1. Ejecutar el backend con `UNION_HOST=127.0.0.1` (default) y `UNION_PORT=9020`.
2. Configurar el túnel hacia `http://127.0.0.1:9020`.
3. En Cloudflare:
   - **Always Use HTTPS**
   - WAF activado
   - Rate limiting para `/api/auth/login`
   - Bot Fight / Managed Challenge si hay ataques
   - HSTS (opcional, si todos los subdominios son HTTPS)
4. No publicar el puerto 9020 en el router ni en el firewall de Windows.
5. Proteger el archivo de credenciales del túnel.
6. Para mayor seguridad, usar **Cloudflare Access** delante del panel.
7. PostgreSQL debe escuchar solo en localhost y usar una clave fuerte distinta de `postgres`.

## Límites conocidos / próximos pasos

- No hay MFA/2FA todavía.
- El bloqueo por intentos es temporal y en base a auditoría; para ataques distribuidos conviene rate limiting en Cloudflare.
- La auditoría no es inmutable a nivel base de datos.
- No hay CSRF token explícito; se mitiga con `SameSite=Lax`, API JSON y mismo origen. Si se agregan formularios cross-site, revisar.
- Mantener actualizados Delphi, PostgreSQL, Horse y el sistema operativo.
- Programar backups cifrados y probar restauración.
