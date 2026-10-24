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
| `operator` | dashboard, schedules, colectivos, camion, fuel, expenses, maintenance, reports |
| `viewer` | dashboard, schedules, colectivos, camion, fuel, expenses, maintenance, reports |

> Los roles siguen definiendo si el usuario puede **escribir** (`operator` o superior). El módulo define **a qué puede entrar**; el rol define **qué puede hacer** dentro.

## Asignación

En **Maestros → Usuarios**, al crear o editar un usuario:

- Se muestran los 12 módulos con checkboxes.
- Al elegir un rol se cargan los módulos por defecto.
- “Restablecer según rol” vuelve a los valores del rol.
- Se puede dejar cualquier combinación, incluso solo un módulo.
- Si se desmarca todo, el usuario no accede a ningún módulo.

## API

- `POST /api/auth/login` y `GET /api/auth/me` devuelven `modules` con la lista efectiva.
- `users.allowed_modules` es un `JSONB` con el array explícito o `NULL` para usar los defaults del rol.
- Los endpoints fuera de los módulos permitidos devuelven **403**.
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
