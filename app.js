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
  const fold = value => String(value ?? '').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').toLowerCase();
  return {
    configured, ready: false, busy: false, message: '', error: '',
    auth: { email: '', password: '' },
    newPassword: { current: '', value: '', confirm: '' },
    newStudent: { nombre: '', codigo: '', email: '', plan_id: '', password: '' },
    createdCredentials: null,
    user: null, profile: null, tab: 'inicio',
    drafts: { planes: {}, cursos: {}, periodos: {}, docentes: {}, perfiles: {} },
    editingSection: null, editingGrade: null,
    data: { planes: [], cursos: [], requisitos: [], perfiles: [], periodos: [], docentes: [], secciones: [], notas: [], matriculas: [], cupos: [] },
    lists: {
      planes: { search: '', page: 1, size: 10 },
      periodos: { search: '', page: 1, size: 10 },
      cursos: { search: '', plan: '', ciclo: '', tipo: '', page: 1, size: 10 },
      perfiles: { search: '', rol: 'ESTUDIANTE', plan: '', periodo: '', seccion: '', page: 1, size: 10 },
      notas: { search: '', plan: '', periodo: '', page: 1, size: 10 },
      matriculas: { search: '', plan: '', periodo: '', estado: 'ACTIVA', page: 1, size: 10 },
      docentes: { search: '', page: 1, size: 10 },
      secciones: { search: '', plan: '', periodo: '', seccion: '', ambiente: '', groupBy: 'plan', page: 1, size: 10 }
    },
    form: {
      plan: { nombre: '', anio: new Date().getFullYear() },
      curso: { plan_id: '', codigo: '', nombre: '', ciclo: 1, creditos: 3, grupo_electivo: '' },
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
    courseKind(c) { return c.grupo_electivo ? `Electivo ${c.grupo_electivo}` : 'Común'; },
    day(n) { return ['','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][n] || '—'; },
    remaining(s) { return this.data.cupos.find(c => c.seccion_id === s.id)?.disponibles ?? s.vacantes; },
    sectionLabel(s) {
      return `${this.displaySection(s)} · ${this.nameOf(this.data.periodos, s.periodo_id)} · ${s.laboratorio || s.aula || 'Sin ambiente'}`;
    },
    studentSectionSummary(studentId) {
      const periodId = Number(this.lists.perfiles.periodo) || this.activePeriod?.id;
      const names = this.data.matriculas
        .filter(m => m.estudiante_id === studentId && m.estado === 'ACTIVA')
        .map(m => this.section(m.seccion_id))
        .filter(s => s && (!periodId || s.periodo_id === periodId))
        .map(s => this.displaySection(s));
      return names.length ? names.join(', ') : 'Sin sección en el periodo';
    },
    resetPage(key) { this.lists[key].page = 1; },
    filteredRows(key) {
      const f = this.lists[key];
      const q = fold(f.search.trim());
      const plan = Number(f.plan) || null;
      const periodo = Number(f.periodo) || null;
      const seccion = Number(f.seccion) || null;
      const matches = values => !q || values.some(value => fold(value).includes(q));
      switch (key) {
        case 'planes':
          return this.data.planes.filter(p => matches([p.nombre, p.anio]));
        case 'periodos':
          return this.data.periodos.filter(p => matches([p.nombre]));
        case 'cursos':
          return (this.role === 'ESTUDIANTE' ? this.myCourses : this.data.cursos)
            .filter(c => (!plan || c.plan_id === plan) && (!f.ciclo || c.ciclo === Number(f.ciclo))
              && (!f.tipo || (f.tipo === 'comun' ? !c.grupo_electivo : c.grupo_electivo === Number(f.tipo)))
              && matches([c.codigo, c.nombre, this.nameOf(this.data.planes, c.plan_id)]))
            .slice().sort((a, b) => a.ciclo - b.ciclo || a.codigo.localeCompare(b.codigo, 'es'));
        case 'perfiles':
          return this.data.perfiles.filter(p => {
            if (f.rol && p.rol !== f.rol) return false;
            if (plan && p.plan_id !== plan) return false;
            if (!matches([p.nombre, p.codigo])) return false;
            if (!periodo && !seccion) return true;
            return this.data.matriculas.some(m => m.estudiante_id === p.id && m.estado === 'ACTIVA'
              && (!seccion || m.seccion_id === seccion)
              && (!periodo || this.section(m.seccion_id)?.periodo_id === periodo));
          }).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
        case 'notas':
          return this.data.notas.filter(n => {
            const c = this.course(n.curso_id);
            return (!plan || c?.plan_id === plan) && (!periodo || n.periodo_id === periodo)
              && matches([this.nameOf(this.data.perfiles, n.estudiante_id), c?.codigo, c?.nombre]);
          }).sort((a, b) => this.nameOf(this.data.perfiles, a.estudiante_id)
            .localeCompare(this.nameOf(this.data.perfiles, b.estudiante_id), 'es'));
        case 'matriculas':
          return this.data.matriculas.filter(m => {
            const s = this.section(m.seccion_id);
            const c = this.course(s?.curso_id);
            return (!f.estado || m.estado === f.estado) && (!plan || c?.plan_id === plan)
              && (!periodo || s?.periodo_id === periodo)
              && matches([this.nameOf(this.data.perfiles, m.estudiante_id), c?.codigo, c?.nombre, s?.codigo, s?.aula, s?.laboratorio]);
          }).sort((a, b) => String(b.creada_en).localeCompare(String(a.creada_en)));
        case 'docentes':
          return this.data.docentes.filter(d => matches([d.nombre, d.correo]))
            .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
        case 'secciones':
          return this.data.secciones.filter(s => {
            const c = this.course(s.curso_id);
            return (!plan || c?.plan_id === plan) && (!periodo || s.periodo_id === periodo)
              && (!f.seccion || fold(s.codigo) === fold(f.seccion))
              && (!f.ambiente || fold(s.laboratorio || s.aula) === fold(f.ambiente))
              && matches([c?.codigo, c?.nombre, s.codigo, this.nameOf(this.data.docentes, s.docente_id), s.aula, s.laboratorio]);
          }).sort((a, b) => this.sectionGroupLabel(a).localeCompare(this.sectionGroupLabel(b), 'es')
            || this.nameOf(this.data.periodos, b.periodo_id).localeCompare(this.nameOf(this.data.periodos, a.periodo_id), 'es')
            || this.displaySection(a).localeCompare(this.displaySection(b), 'es'));
        default: return [];
      }
    },
    pageCount(key) { return Math.max(1, Math.ceil(this.filteredRows(key).length / Number(this.lists[key].size))); },
    currentPage(key) { return Math.min(this.lists[key].page, this.pageCount(key)); },
    pageRows(key) {
      const f = this.lists[key];
      const start = (this.currentPage(key) - 1) * Number(f.size);
      return this.filteredRows(key).slice(start, start + Number(f.size));
    },
    pageSummary(key) {
      const total = this.filteredRows(key).length;
      if (!total) return '0 resultados';
      const start = (this.currentPage(key) - 1) * Number(this.lists[key].size) + 1;
      return `${start}-${Math.min(start + Number(this.lists[key].size) - 1, total)} de ${total}`;
    },
    movePage(key, step) { this.lists[key].page = Math.max(1, Math.min(this.pageCount(key), this.currentPage(key) + step)); },
    sectionGroupLabel(s) {
      if (this.lists.secciones.groupBy === 'ambiente') return s.laboratorio || s.aula || 'Sin ambiente';
      if (this.lists.secciones.groupBy === 'seccion') return `Sección ${s.codigo}`;
      const planId = this.course(s.curso_id)?.plan_id;
      const p = this.data.planes.find(item => item.id === planId);
      return p ? `${p.nombre} (${p.anio})` : 'Sin plan';
    },
    sectionGroups() {
      const groups = new Map();
      for (const section of this.pageRows('secciones')) {
        const label = this.sectionGroupLabel(section);
        if (!groups.has(label)) groups.set(label, []);
        groups.get(label).push(section);
      }
      return [...groups].map(([label, rows]) => ({ label, rows }));
    },
    get myCourses() { return this.data.cursos.filter(c => c.plan_id === this.profile?.plan_id).sort((a,b) => a.ciclo - b.ciclo || a.codigo.localeCompare(b.codigo)); },
    get offers() { return this.data.secciones.filter(s => s.publicada && s.periodo_id === this.activePeriod?.id && this.course(s.curso_id)?.plan_id === this.profile?.plan_id); },
    get myEnrollments() { return this.data.matriculas.filter(m => m.estudiante_id === this.user?.id && m.estado === 'ACTIVA' && this.section(m.seccion_id)?.periodo_id === this.activePeriod?.id); },
    chosenElective(s) {
      const group = this.course(s.curso_id)?.grupo_electivo;
      if (!group) return false;
      return this.data.notas.some(n => n.estudiante_id === this.user?.id && n.nota >= 11
        && this.course(n.curso_id)?.grupo_electivo === group)
        || this.data.matriculas.some(m => m.estudiante_id === this.user?.id && m.estado === 'ACTIVA'
          && this.course(this.section(m.seccion_id)?.curso_id)?.grupo_electivo === group);
    },
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
      const load = async table => {
        const rows = [];
        for (let offset = 0; ; offset += 1000) {
          const result = await db.from(table).select('*').range(offset, offset + 999);
          if (result.error) return result;
          rows.push(...(result.data || []));
          if ((result.data || []).length < 1000) return { data: rows, error: null };
        }
      };
      const results = await Promise.all(tables.map(load));
      results.forEach((r,i) => {
        if (r.error) this.error = `${tables[i]}: ${r.error.message}`;
        else this.data[tables[i] === 'prerrequisitos' ? 'requisitos' : tables[i]] = r.data || [];
      });
      for (const table of ['planes', 'cursos', 'periodos', 'docentes', 'perfiles']) {
        this.drafts[table] = Object.fromEntries(this.data[table].map(row => [row.id, { ...row }]));
      }
      const cupos = await db.rpc('cupos');
      if (cupos.error) this.error = `cupos: ${cupos.error.message}`;
      else this.data.cupos = cupos.data || [];
      if (this.user) this.profile = this.data.perfiles.find(p => p.id === this.user.id) || this.profile;
      window.syncSearchableSelects?.();
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
    addCourse() { const f = this.form.curso; this.save('cursos', { plan_id: Number(f.plan_id), codigo: f.codigo.trim().toUpperCase(), nombre: f.nombre.trim(), ciclo: Number(f.ciclo), creditos: Number(f.creditos), grupo_electivo: f.grupo_electivo ? Number(f.grupo_electivo) : null }, 'Curso creado'); },
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
      const grupo_electivo = draft.grupo_electivo ? Number(draft.grupo_electivo) : null;
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
      if ((hasGrade && (plan_id !== course.plan_id || grupo_electivo !== course.grupo_electivo)) ||
          (hasEnrollment && (plan_id !== course.plan_id || creditos !== course.creditos || grupo_electivo !== course.grupo_electivo))) {
        this.error = 'Este curso ya tiene notas o matrículas. No se puede cambiar su plan ni su grupo electivo; tampoco los créditos si hay matrículas activas.'; return;
      }
      return this.update('cursos', course.id, { plan_id, codigo, nombre, ciclo, creditos, grupo_electivo }, 'Curso actualizado');
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
    saveProfileChanges(profile) {
      const draft = this.drafts.perfiles[profile.id];
      const nombre = draft.nombre?.trim() || '';
      const codigo = draft.codigo?.trim() || null;
      const rol = draft.rol;
      const plan_id = draft.plan_id ? Number(draft.plan_id) : null;
      if (!nombre || !['ESTUDIANTE', 'DIRECCION', 'ADMINISTRADOR'].includes(rol)
        || (plan_id && !this.data.planes.some(p => p.id === plan_id))) {
        this.error = 'Revisa el nombre, rol y plan de la cuenta.'; return;
      }
      return this.update('perfiles', profile.id, { nombre, codigo, rol, plan_id }, 'Cuenta actualizada');
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
