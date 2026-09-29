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
    drafts: { planes: {}, cursos: {}, periodos: {}, docentes: {} },
    editingSection: null, editingGrade: null,
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
    async logout() {
      await db.auth.signOut();
      this.user = null; this.profile = null; this.tab = 'inicio';
      this.createdCredentials = null; this.editingSection = null; this.editingGrade = null;
      this.newPassword = { current: '', value: '', confirm: '' };
      for (const table of Object.keys(this.data)) this.data[table] = [];
      for (const table of Object.keys(this.drafts)) this.drafts[table] = {};
    },
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
      for (const table of ['planes', 'cursos', 'periodos', 'docentes']) {
        this.drafts[table] = Object.fromEntries(this.data[table].map(row => [row.id, { ...row }]));
      }
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
        const { error } = await db.from(table).update(changes).eq('id', id).select('id').single();
        if (error) throw error;
        this.message = success;
        await this.refresh();
        return true;
      } catch (e) { this.error = e.code === '23505' ? 'Ya existe otro registro con esos datos.' : e.message; return false; }
      finally { this.busy = false; }
    },
    addPlan() { this.save('planes', { nombre: this.form.plan.nombre.trim(), anio: Number(this.form.plan.anio) }, 'Plan creado'); },
    addCourse() { const f = this.form.curso; this.save('cursos', { plan_id: Number(f.plan_id), codigo: f.codigo.trim().toUpperCase(), nombre: f.nombre.trim(), ciclo: Number(f.ciclo), creditos: Number(f.creditos) }, 'Curso creado'); },
    savePlanChanges(plan) {
      const draft = this.drafts.planes[plan.id];
      const nombre = draft.nombre.trim();
      const anio = Number(draft.anio);
      if (!nombre || !Number.isInteger(anio) || anio < 2000 || anio > 2100) {
        this.error = 'Escribe un nombre y un año válido para el plan.'; return;
      }
      return this.update('planes', plan.id, { nombre, anio }, 'Plan actualizado');
    },
    saveCourseChanges(course) {
      const draft = this.drafts.cursos[course.id];
      const plan_id = Number(draft.plan_id);
      const codigo = draft.codigo.trim().toUpperCase();
      const nombre = draft.nombre.trim();
      const ciclo = Number(draft.ciclo);
      const creditos = Number(draft.creditos);
      if (!this.data.planes.some(p => p.id === plan_id) || !codigo || !nombre ||
          !Number.isInteger(ciclo) || ciclo < 1 || ciclo > 12 ||
          !Number.isInteger(creditos) || creditos < 1 || creditos > 10) {
        this.error = 'Revisa plan, código, nombre, ciclo y créditos del curso.'; return;
      }
      const invalidRequirement = this.data.requisitos.some(r => {
        const dependent = r.curso_id === course.id ? { plan_id, ciclo } : this.course(r.curso_id);
        const required = r.requisito_id === course.id ? { plan_id, ciclo } : this.course(r.requisito_id);
        return (r.curso_id === course.id || r.requisito_id === course.id) &&
          (dependent.plan_id !== required.plan_id || required.ciclo >= dependent.ciclo);
      });
      if (invalidRequirement) {
        this.error = 'El cambio dejaría un prerrequisito fuera del plan o del ciclo anterior.'; return;
      }
      const hasGrade = this.data.notas.some(n => n.curso_id === course.id);
      const hasEnrollment = this.data.matriculas.some(m => m.estado === 'ACTIVA' && this.section(m.seccion_id)?.curso_id === course.id);
      if ((hasGrade && plan_id !== course.plan_id) ||
          (hasEnrollment && (plan_id !== course.plan_id || creditos !== course.creditos))) {
        this.error = 'Este curso ya tiene notas o matrículas. Puedes corregir código, nombre y ciclo, pero no cambiar su plan ni los créditos de matrículas activas.'; return;
      }
      return this.update('cursos', course.id, { plan_id, codigo, nombre, ciclo, creditos }, 'Curso actualizado');
    },
    savePeriodChanges(period) {
      const draft = this.drafts.periodos[period.id];
      const nombre = draft.nombre.trim();
      const max_creditos = Number(draft.max_creditos);
      if (!nombre || !Number.isInteger(max_creditos) || max_creditos < 1 || max_creditos > 40) {
        this.error = 'Revisa el nombre y el máximo de créditos del periodo.'; return;
      }
      return this.update('periodos', period.id, { nombre, max_creditos }, 'Periodo actualizado');
    },
    saveTeacherChanges(teacher) {
      const draft = this.drafts.docentes[teacher.id];
      const nombre = draft.nombre.trim();
      const correo = draft.correo?.trim() || null;
      if (!nombre || (correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo))) {
        this.error = 'Revisa el nombre y el correo del docente.'; return;
      }
      return this.update('docentes', teacher.id, { nombre, correo }, 'Docente actualizado');
    },
    editSection(section) { this.editingSection = { ...section }; },
    async saveSectionChanges() {
      const draft = this.editingSection;
      if (!draft) return;
      const changes = {
        periodo_id: Number(draft.periodo_id), curso_id: Number(draft.curso_id),
        docente_id: draft.docente_id ? Number(draft.docente_id) : null,
        codigo: draft.codigo.trim().toUpperCase(), dia: Number(draft.dia),
        inicio: draft.inicio, fin: draft.fin, aula: draft.aula?.trim() || null,
        laboratorio: draft.laboratorio?.trim() || null,
        vacantes: Number(draft.vacantes), publicada: Boolean(draft.publicada)
      };
      if (!this.data.periodos.some(p => p.id === changes.periodo_id) ||
          !this.data.cursos.some(c => c.id === changes.curso_id) ||
          (changes.docente_id && !this.data.docentes.some(d => d.id === changes.docente_id)) ||
          !changes.codigo || !Number.isInteger(changes.dia) || changes.dia < 1 || changes.dia > 7 ||
          !changes.inicio || !changes.fin || changes.inicio >= changes.fin ||
          !Number.isInteger(changes.vacantes) || changes.vacantes < 1 || changes.vacantes > 500) {
        this.error = 'Revisa periodo, curso, docente, código, horario y vacantes de la sección.'; return;
      }
      const original = this.section(draft.id);
      if (!original) { this.error = 'La sección ya no existe. Actualiza la página.'; return; }
      const hasEnrollment = this.data.matriculas.some(m => m.seccion_id === draft.id && m.estado === 'ACTIVA');
      const structuralFields = ['periodo_id', 'curso_id', 'codigo', 'dia', 'inicio', 'fin', 'vacantes', 'publicada'];
      if (hasEnrollment && structuralFields.some(field => {
        const current = field === 'inicio' || field === 'fin' ? String(original[field]).slice(0, 5) : String(original[field]);
        const next = field === 'inicio' || field === 'fin' ? String(changes[field]).slice(0, 5) : String(changes[field]);
        return current !== next;
      })) {
        this.error = 'Esta sección tiene matrículas activas. Solo puedes corregir docente, aula o laboratorio.'; return;
      }
      if (await this.update('secciones', draft.id, changes, 'Sección actualizada')) this.editingSection = null;
    },
    editGrade(grade) { this.editingGrade = { ...grade }; },
    async saveGradeChanges() {
      const draft = this.editingGrade;
      if (!draft) return;
      const estudiante_id = draft.estudiante_id;
      const curso_id = Number(draft.curso_id);
      const periodo_id = Number(draft.periodo_id);
      const nota = Number(draft.nota);
      const student = this.data.perfiles.find(p => p.id === estudiante_id && p.rol === 'ESTUDIANTE');
      if (!student || !this.data.cursos.some(c => c.id === curso_id && c.plan_id === student.plan_id) ||
          !this.data.periodos.some(p => p.id === periodo_id) || draft.nota === '' || draft.nota === null ||
          !Number.isFinite(nota) || nota < 0 || nota > 20) {
        this.error = 'Revisa estudiante, curso, periodo y nota.'; return;
      }
      if (await this.update('notas', draft.id, { estudiante_id, curso_id, periodo_id, nota }, 'Nota actualizada')) this.editingGrade = null;
    },
    async removeRequirement(requirement) {
      if (!confirm('¿Quitar este prerrequisito? Puedes agregar el correcto después.')) return;
      this.busy = true; this.error = ''; this.message = '';
      try {
        const { error } = await db.from('prerrequisitos').delete()
          .eq('curso_id', requirement.curso_id).eq('requisito_id', requirement.requisito_id)
          .select('curso_id').single();
        if (error) throw error;
        this.message = 'Prerrequisito quitado';
        await this.refresh();
      } catch (e) { this.error = e.message; }
      finally { this.busy = false; }
    },
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
