# Control de acceso por módulos

Cada usuario tiene una lista de módulos permitidos. Esa lista controla:

1. **Qué aparece en el menú** de la web.
2. **Qué endpoints puede usar** (el backend responde 403 si el módulo no está permitido).
3. **Qué pestañas ve** dentro de Maestros (Vehículos/Empleados/Rutas, Usuarios, Configuración).

## Módulos

| Módulo | Incluye |
|---|---|
| `dashboard` | Dashboard |
| `schedules` | Programación de servicios/horarios |
| `colectivos` | Libro diario de colectivos |
| `camion` | Viajes, remitos y fletes |
| `fuel` | Combustible |
| `expenses` | Gastos |
| `maintenance` | Mantenimiento |
| `masters` | Vehículos, empleados y rutas |
| `reports` | Reportes diario/mensual y exportaciones |
| `audit` | Auditoría |
| `users` | Usuarios |
| `settings` | Configuración de la empresa |

## Permisos por defecto según el rol

Si el usuario no tiene una lista explícita (`allowed_modules = NULL`), se usan estos valores:

| Rol | Módulos |
|---|---|
| `superadmin` | Todos |
| `admin` | Todos |
| `supervisor` | dashboard, schedules, colectivos, camion, fuel, expenses, maintenance, masters, reports |
| `operator` | dashboard, schedules, colectivos, camion, fuel, expenses, maintenance |
| `viewer` | dashboard, schedules, colectivos, camion, fuel, expenses, maintenance |

> Los roles siguen definiendo si el usuario puede **escribir** (`operator` o superior). El módulo define **a qué puede entrar**; el rol define **qué puede hacer** dentro.

## Permiso de importes y recaudación

Además de los módulos, cada usuario tiene el permiso **“Ver importes y recaudación”** (`users.can_view_financials`). Es independiente del módulo: un usuario puede operar Colectivos sin ver dinero.

| Rol | Valor por defecto |
|---|---|
| `superadmin` | Sí |
| `admin` | Sí |
| `supervisor` | Sí |
| `operator` | No |
| `viewer` | No |

Si `can_view_financials = NULL`, se usa el valor del rol. En **Maestros → Usuarios** se puede marcar o desmarcar por usuario.

Cuando el permiso está **desactivado**:

- La web oculta columnas, totales, gráficos y formularios de importes; en Colectivos solo se ven salidas, boletos, horarios y estado.
- El backend elimina del JSON los campos monetarios (`revenue`, `surplus`, `fare_total`, `fuel_amount`, `amount`, `cost`, `net_amount`, `vat_amount`, `total_amount`, `tariff`, `commission_pct`, etc.). No alcanza con ocultarlo en la pantalla.
- `/api/reports/*` y las exportaciones CSV responden **403**; solo queda disponible `/api/reports/latest`.
- El usuario sigue pudiendo cargar datos operativos (fechas, coche, chofer, boletos, kilómetros, litros), pero los importes quedan para un usuario con permiso.
- Los módulos `reports` no se asignan por defecto a `operator` ni `viewer`. Si se le da `reports`, también hay que habilitarle “Ver importes”.

## Asignación

En **Maestros → Usuarios**, al crear o editar un usuario:

- Se muestran los 12 módulos con checkboxes.
- Al elegir un rol se cargan los módulos y el permiso de importes por defecto.
- “Restablecer según rol” vuelve a los valores del rol.
- Se puede dejar cualquier combinación, incluso solo un módulo.
- Si se desmarca todo, el usuario no accede a ningún módulo.
- “Ver importes y recaudación” se puede activar aunque el rol sea `operator` o `viewer`.

## API

- `POST /api/auth/login` y `GET /api/auth/me` devuelven `modules` con la lista efectiva y `can_view_financials` con el permiso efectivo.
- `users.allowed_modules` es un `JSONB` con el array explícito o `NULL` para usar los defaults del rol.
- `users.can_view_financials` es `BOOLEAN`: `NULL` usa el default del rol; `TRUE`/`FALSE` lo fuerza.
- Los endpoints fuera de los módulos permitidos devuelven **403**.
- Los endpoints de reportes y exportaciones devuelven **403** si el usuario no tiene “Ver importes”.
- Las respuestas JSON de un usuario sin “Ver importes” se filtran en el backend antes de enviarse; no contienen campos monetarios.
- Las lecturas de catálogos (`vehicles`, `employees`, `routes`) y `/api/reports/latest` se permiten para no romper formularios; las escrituras sí exigen `masters`.
- `/api/schedules` GET se permite también a usuarios con `colectivos`, porque el formulario de colectivos necesita la programación.
- Los módulos `users` y `settings` siguen exigiendo rol administrador en el backend.

## Ejemplo

Un usuario con `allowed_modules = ["colectivos"]`:

- Menú: solo **Colectivos**.
- Puede ver/crear/editar servicios de colectivos.
- No puede ver dashboard, reportes, camión, maestros, auditoría ni usuarios.
- Si intenta entrar a `#/dashboard`, la web lo redirige a Colectivos.
- Si llama directamente a `/api/reports/daily`, recibe 403.

Para que además vea importes, hay que marcar **“Ver importes y recaudación”** en su usuario y asignarle el módulo `reports` si corresponde.
