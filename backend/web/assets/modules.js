export const MODULES = [
  { id:'dashboard',   label:'Dashboard',      icon:'dashboard' },
  { id:'schedules',   label:'Servicios',      icon:'calendar' },
  { id:'colectivos',  label:'Colectivos',     icon:'bus' },
  { id:'camion',      label:'Camión',         icon:'truck' },
  { id:'fuel',        label:'Combustible',    icon:'fuel' },
  { id:'expenses',    label:'Gastos',         icon:'receipt' },
  { id:'maintenance', label:'Mantenimiento',  icon:'wrench' },
  { id:'masters',     label:'Maestros',       icon:'settings' },
  { id:'reports',     label:'Reportes',       icon:'chart' },
  { id:'audit',       label:'Auditoría',      icon:'audit' },
  { id:'users',       label:'Usuarios',       icon:'users' },
  { id:'settings',    label:'Configuración',  icon:'settings' },
];

export const ALL_MODULES = MODULES.map(m => m.id);

export const ROLE_MODULES = {
  superadmin: ALL_MODULES,
  admin: ALL_MODULES,
  supervisor: ['dashboard','schedules','colectivos','camion','fuel','expenses','maintenance','masters','reports'],
  operator: ['dashboard','schedules','colectivos','camion','fuel','expenses','maintenance','reports'],
  viewer: ['dashboard','schedules','colectivos','camion','fuel','expenses','maintenance','reports'],
};

export function defaultModules(role){
  return ROLE_MODULES[role] || ROLE_MODULES.viewer;
}

export function moduleLabel(id){
  const m = MODULES.find(x => x.id === id);
  return m ? m.label : id;
}

export const VIEW_MODULE = {
  dashboard: 'dashboard',
  schedules: 'schedules',
  colectivos: 'colectivos',
  freight: 'camion',
  fuel: 'fuel',
  expenses: 'expenses',
  maintenance: 'maintenance',
  masters: 'masters',
  reports: 'reports',
  audit: 'audit',
};
