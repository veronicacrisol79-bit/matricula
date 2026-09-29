/* Interfaz de una sola página. Los permisos y reglas están en schema.sql. */
window.app = function () {
  const cfg = window.SUPABASE_CONFIG;
  const configured = cfg && cfg.url && !cfg.url.includes('REEMPLAZAR')
    && cfg.publishableKey && !cfg.publishableKey.includes('REEMPLAZAR');
  const db = configured ? window.supabase.createClient(cfg.url, cfg.publishableKey) : null;
  async function functionError(data, error) {
    if (data?.error) return data.error;
    try {
      const response = await error?.context?.json();
      if (response?.error) return response.error;
    } catch { /* La respuesta puede no ser JSON. */ }
    return error?.message || 'No se pudo completar la operación.';
  }
  return {
    configured, ready: false, busy: false, message: '', error: '',
    auth: { email: '', password: '' },
    newPassword: { current: '', value: '', confirm: '' },
    newStudent: { nombre: '', codigo: '', email: '', plan_id: '', password: '' },
    createdCredentials: null,
    user: null, profile: null, tab: 'inicio',
    data: { planes: [], cursos: [], requisitos: [], perfiles: [], periodos: [], docentes: [], secciones: [], notas: [], matriculas: [], cupos: [] },
    form: {
      plan: { nombre: '', anio: new Date().getFullYear() },
      curso: { plan_id: '', codigo: '', nombre: '', ciclo: 1, creditos: 3 },
      requisito: { curso_id: '', requisito_id: '' },
      periodo: { nombre: '', max_creditos: 24 },
      docente: { nombre: '', correo: '' },
      seccion: { periodo_id: '', curso_id: '', docente_id: '', codigo: 'A', dia: 1, inicio: '08:00', fin: '10:00', aula: '', laboratorio: '', vacantes: 30 },
      nota: { estudiante_id: '', curso_id: '', periodo_id: '', nota: 11 }
    },
    get role() { return this.profile?.rol || ''; },
    get activePeriod() { return this.data.periodos.find(p => p.activo); },
    get myPlan() { return this.data.planes.find(p => p.id === this.profile?.plan_id); },
    nameOf(list, id, field = 'nombre') { return list.find(x => x.id === id)?.[field] || '—'; },
    course(id) { return this.data.cursos.find(c => c.id === id); },
    section(id) { return this.data.secciones.find(s => s.id === id); },
    displaySection(s) { return `${this.course(s.curso_id)?.codigo || 'Curso'} · ${s.codigo}`; },
    day(n) { return ['','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][n] || '—'; },
    remaining(s) { return this.data.cupos.find(c => c.seccion_id === s.id)?.disponibles ?? s.vacantes; },
    get myCourses() { return this.data.cursos.filter(c => c.plan_id === this.profile?.plan_id).sort((a,b) => a.ciclo - b.ciclo || a.codigo.localeCompare(b.codigo)); },
    get offers() { return this.data.secciones.filter(s => s.publicada && s.periodo_id === this.activePeriod?.id && this.course(s.curso_id)?.plan_id === this.profile?.plan_id); },
    get myEnrollments() { return this.data.matriculas.filter(m => m.estudiante_id === this.user?.id && m.estado === 'ACTIVA' && this.section(m.seccion_id)?.periodo_id === this.activePeriod?.id); },
    get enrolledCredits() { return this.myEnrollments.reduce((sum,m) => sum + (this.course(this.section(m.seccion_id)?.curso_id)?.creditos || 0), 0); },
    requirements(id) { return this.data.requisitos.filter(r => r.curso_id === id).map(r => this.course(r.requisito_id)?.codigo).filter(Boolean).join(', ') || 'Ninguno'; },
    async init() {
      if (!this.configured) { this.ready = true; return; }
      const { data, error } = await db.auth.getSession();
      if (error) this.error = error.message;
      if (data?.session?.user) await this.enter(data.session.user);
      this.ready = true;
    },
    async enter(user) {
      const { data, error } = await db.from('perfiles').select('*').eq('id', user.id).single();
      if (error) { this.error = 'No se encontró tu perfil. Contacta a la administración.'; return false; }
      this.user = user;
      this.profile = data;
      this.tab = 'inicio';
      await this.refresh();
      return true;
    },
    async login() {
      this.error = ''; this.message = ''; this.busy = true;
      try {
        const { data, error } = await db.auth.signInWithPassword({ email: this.auth.email, password: this.auth.password });
        if (error) throw error;
        this.auth.password = '';
        await this.enter(data.user);
      } catch (e) {
        this.error = e.message === 'Email not confirmed' ? 'Confirma tu correo desde el enlace que recibiste antes de iniciar sesión.'
          : e.message === 'Invalid login credentials' ? 'Correo o contraseña incorrectos.' : e.message;
      }
      finally { this.busy = false; }
    },
    async logout() { await db.auth.signOut(); this.user = null; this.profile = null; this.tab = 'inicio'; this.createdCredentials = null; this.newPassword = { current: '', value: '', confirm: '' }; },
    async changePassword() {
      this.error = ''; this.message = '';
      if (this.newPassword.value !== this.newPassword.confirm) { this.error = 'Las contraseñas nuevas no coinciden.'; return; }
      if (this.newPassword.value.length < 10) { this.error = 'La nueva contraseña debe tener al menos 10 caracteres.'; return; }
      if (this.newPassword.value === this.newPassword.current) { this.error = 'La nueva contraseña debe ser diferente de la temporal.'; return; }
      this.busy = true;
      try {
        const { data, error } = await db.functions.invoke('gestionar-cuentas', { body: { accion: 'cambiar-clave', password_actual: this.newPassword.current, password: this.newPassword.value } });
        if (error || data?.error) throw new Error(await functionError(data, error));
        this.newPassword = { current: '', value: '', confirm: '' };
        await this.enter(this.user);
        this.message = 'Contraseña actualizada. Ya puedes usar el sistema.';
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    async createStudent() {
      this.error = ''; this.message = ''; this.busy = true; this.createdCredentials = null;
      const f = this.newStudent;
      try {
        const { data, error } = await db.functions.invoke('gestionar-cuentas', { body: {
          accion: 'crear-estudiante', nombre: f.nombre.trim(), codigo: f.codigo.trim(),
          email: f.email.trim().toLowerCase(), plan_id: Number(f.plan_id), password: f.password
        } });
        if (error || data?.error) throw new Error(await functionError(data, error));
        this.createdCredentials = { email: f.email.trim().toLowerCase(), password: f.password };
        this.newStudent = { nombre: '', codigo: '', email: '', plan_id: '', password: '' };
        this.message = 'Cuenta de estudiante creada. Entrega los datos de acceso por un canal privado.';
        await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    async refresh() {
      const tables = ['planes','cursos','prerrequisitos','perfiles','periodos','docentes','secciones','notas','matriculas'];
      const results = await Promise.all(tables.map(t => db.from(t).select('*')));
      results.forEach((r,i) => {
        if (r.error) this.error = `${tables[i]}: ${r.error.message}`;
        else this.data[tables[i] === 'prerrequisitos' ? 'requisitos' : tables[i]] = r.data || [];
      });
      const cupos = await db.rpc('cupos');
      if (cupos.error) this.error = `cupos: ${cupos.error.message}`;
      else this.data.cupos = cupos.data || [];
      if (this.user) this.profile = this.data.perfiles.find(p => p.id === this.user.id) || this.profile;
    },
    async save(table, value, success = 'Guardado') {
      this.busy = true; this.error = ''; this.message = '';
      try {
        const { error } = await db.from(table).insert(value);
        if (error) throw error;
        this.message = success;
        await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    async update(table, id, changes, success = 'Actualizado') {
      this.busy = true; this.error = ''; this.message = '';
      try {
        const { error } = await db.from(table).update(changes).eq('id', id);
        if (error) throw error;
        this.message = success;
        await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    addPlan() { this.save('planes', { nombre: this.form.plan.nombre.trim(), anio: Number(this.form.plan.anio) }, 'Plan creado'); },
    addCourse() { const f = this.form.curso; this.save('cursos', { plan_id: Number(f.plan_id), codigo: f.codigo.trim().toUpperCase(), nombre: f.nombre.trim(), ciclo: Number(f.ciclo), creditos: Number(f.creditos) }, 'Curso creado'); },
    addRequirement() { const f = this.form.requisito; this.save('prerrequisitos', { curso_id: Number(f.curso_id), requisito_id: Number(f.requisito_id) }, 'Prerrequisito agregado'); },
    addPeriod() { const f = this.form.periodo; this.save('periodos', { nombre: f.nombre.trim(), max_creditos: Number(f.max_creditos) }, 'Periodo creado'); },
    activatePeriod(id) { this.rpc('activar_periodo', { p_periodo_id: id }, 'Periodo activado'); },
    addTeacher() { const f = this.form.docente; this.save('docentes', { nombre: f.nombre.trim(), correo: f.correo.trim() || null }, 'Docente creado'); },
    addSection() {
      const f = this.form.seccion;
      this.save('secciones', { periodo_id: Number(f.periodo_id), curso_id: Number(f.curso_id), docente_id: f.docente_id ? Number(f.docente_id) : null, codigo: f.codigo.trim().toUpperCase(), dia: Number(f.dia), inicio: f.inicio, fin: f.fin, aula: f.aula.trim() || null, laboratorio: f.laboratorio.trim() || null, vacantes: Number(f.vacantes) }, 'Sección creada');
    },
    async addGrade() {
      const f = this.form.nota; this.busy = true; this.error = ''; this.message = '';
      try {
        const { error } = await db.from('notas').upsert({ estudiante_id: f.estudiante_id, curso_id: Number(f.curso_id), periodo_id: Number(f.periodo_id), nota: Number(f.nota) }, { onConflict: 'estudiante_id,curso_id,periodo_id' });
        if (error) throw error;
        this.message = 'Nota registrada'; await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    async rpc(name, args, success) {
      this.busy = true; this.error = ''; this.message = '';
      try {
        const { error } = await db.rpc(name, args);
        if (error) throw error;
        this.message = success; await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
    enroll(id) { this.rpc('inscribir', { p_seccion_id: id }, 'Matrícula realizada'); },
    withdraw(id) { if (confirm('¿Retirarte de esta sección?')) this.rpc('retirar', { p_matricula_id: id }, 'Retiro realizado'); }
  };
};
