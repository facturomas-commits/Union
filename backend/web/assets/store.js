export const state = {
  user: null,
  company: null,
  settings: {},
  latest: null,
  today: localISO(new Date()),
};

export function localISO(d){
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function canWrite(){
  return !!state.user && ['superadmin','admin','supervisor','operator'].includes(state.user.role);
}
export function isAdmin(){
  return !!state.user && ['superadmin','admin'].includes(state.user.role);
}
export function isSuper(){
  return !!state.user && state.user.role === 'superadmin';
}
