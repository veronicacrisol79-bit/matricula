-- Ejecutar una vez en el SQL Editor de un proyecto Supabase nuevo.
-- Todos los cambios de matrícula se hacen con funciones: el navegador no escribe
-- directamente en matriculas.
-- Piensa en cada tabla como una hoja de cálculo: cada fila es un registro y
-- cada columna guarda un dato. "public" es el esquema donde viven esas hojas.
-- CREATE crea, REFERENCES conecta tablas, CHECK limita valores y UNIQUE evita duplicados.
-- BIGINT es un número entero grande; UUID es un identificador largo de Auth;
-- TEXT guarda palabras; BOOLEAN guarda TRUE/FALSE; TIME guarda una hora.
-- NOT NULL obliga a tener valor y DEFAULT pone uno si no se indicó ninguno.

-- PLANES: una fila representa una malla curricular de un año determinado.
create table public.planes (
  -- ID es el número único que PostgreSQL asigna automáticamente a cada plan.
  id bigint generated always as identity primary key,
  nombre text not null,
  anio integer not null check (anio between 2000 and 2100),
  -- No puede haber dos planes con el mismo nombre y año.
  unique (nombre, anio)
);

-- CURSOS: cada asignatura pertenece exactamente a un plan.
create table public.cursos (
  id bigint generated always as identity primary key,
  -- plan_id apunta al ID de planes; al borrar ese plan se borran sus cursos.
  plan_id bigint not null references public.planes(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  ciclo integer not null check (ciclo between 1 and 12),
  creditos integer not null check (creditos between 1 and 10),
  -- NULL = curso común; 1, 2 o 3 = opción del grupo electivo indicado.
  grupo_electivo smallint check (grupo_electivo between 1 and 3),
  -- Un código puede repetirse en planes diferentes, pero no en el mismo plan.
  unique (plan_id, codigo)
);

-- PRERREQUISITOS: cada fila dice "para llevar curso_id, aprueba requisito_id".
create table public.prerrequisitos (
  curso_id bigint not null references public.cursos(id) on delete cascade,
  requisito_id bigint not null references public.cursos(id) on delete cascade,
  -- La pareja es única y un curso no puede ser requisito de sí mismo.
  primary key (curso_id, requisito_id),
  check (curso_id <> requisito_id)
);

-- Un requisito debe ser de la misma malla y de un ciclo anterior. Esto
-- también impide cadenas circulares de requisitos.
-- Un trigger es una alarma automática: PostgreSQL llama a esta función antes
-- de insertar o cambiar una pareja de cursos.
create function public.validar_prerrequisito() returns trigger
language plpgsql set search_path = '' as $$
declare
  -- %rowtype significa "una fila completa" de la tabla indicada.
  v_curso public.cursos%rowtype;
  v_requisito public.cursos%rowtype;
begin
  -- NEW es la fila que alguien intenta guardar.
  select * into v_curso from public.cursos where id = new.curso_id;
  select * into v_requisito from public.cursos where id = new.requisito_id;
  -- Si son de distinto plan o el requisito no es anterior, detenemos el guardado.
  if v_curso.plan_id is distinct from v_requisito.plan_id
    or v_requisito.ciclo >= v_curso.ciclo then
    raise exception 'El prerrequisito debe pertenecer al mismo plan y a un ciclo anterior';
  end if;
  -- RETURN NEW permite continuar con la fila válida.
  return new;
end;
$$;
create trigger antes_de_prerrequisito before insert or update on public.prerrequisitos
for each row execute function public.validar_prerrequisito();

-- PERFILES: datos académicos y rol de cada cuenta de Supabase Auth.
-- Su ID es el mismo UUID de auth.users; así sabemos a quién pertenece la fila.
create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null default '',
  codigo text unique,
  -- Solo se aceptan estos tres roles; al crear una cuenta empieza como estudiante.
  rol text not null default 'ESTUDIANTE'
    check (rol in ('ADMINISTRADOR', 'DIRECCION', 'ESTUDIANTE')),
  plan_id bigint references public.planes(id),
  -- TRUE obliga al usuario a cambiar la contraseña entregada por Administración.
  clave_temporal boolean not null default true
);

-- PERIODOS: por ejemplo, "2026-II" y su máximo de créditos por estudiante.
create table public.periodos (
  id bigint generated always as identity primary key,
  nombre text not null unique,
  activo boolean not null default false,
  max_creditos integer not null default 24 check (max_creditos between 1 and 40)
);
-- Índice parcial: entre las filas con activo=true solo puede existir una.
create unique index solo_un_periodo_activo on public.periodos (activo) where activo;

-- DOCENTES: nombres y correos de quienes dictan las secciones.
create table public.docentes (
  id bigint generated always as identity primary key,
  nombre text not null,
  correo text
);

-- Una sección tiene un bloque semanal. Una segunda sesión requiere otra versión
-- del esquema y de la comprobación de cruces.
-- SECCIONES: grupos concretos de un curso en un periodo, con horario y cupos.
create table public.secciones (
  id bigint generated always as identity primary key,
  periodo_id bigint not null references public.periodos(id),
  curso_id bigint not null references public.cursos(id),
  -- Una sección puede quedar sin docente mientras se termina de programar.
  docente_id bigint references public.docentes(id),
  codigo text not null,
  -- Día: 1 a 7; la hora de inicio debe ser anterior a la de fin.
  dia integer not null check (dia between 1 and 7),
  inicio time not null,
  fin time not null,
  aula text,
  laboratorio text,
  vacantes integer not null check (vacantes between 1 and 500),
  -- Solo las secciones publicadas aparecen en la oferta del estudiante.
  publicada boolean not null default false,
  check (inicio < fin),
  -- Una misma asignatura no repite el código de sección en un periodo.
  unique (periodo_id, curso_id, codigo)
);

-- NOTAS: calificación obtenida por un estudiante en un curso y periodo.
create table public.notas (
  id bigint generated always as identity primary key,
  estudiante_id uuid not null references public.perfiles(id) on delete cascade,
  curso_id bigint not null references public.cursos(id),
  periodo_id bigint not null references public.periodos(id),
  -- La escala va de 0 a 20; en este sistema se aprueba desde 11.
  nota numeric(4,1) not null check (nota between 0 and 20),
  unique (estudiante_id, curso_id, periodo_id)
);

-- MATRÍCULAS: une a un estudiante con una sección concreta.
create table public.matriculas (
  id bigint generated always as identity primary key,
  estudiante_id uuid not null references public.perfiles(id) on delete cascade,
  seccion_id bigint not null references public.secciones(id),
  -- Retirar no borra la fila: cambia su estado y conserva el historial.
  estado text not null default 'ACTIVA' check (estado in ('ACTIVA', 'RETIRADA')),
  creada_en timestamptz not null default now(),
  unique (estudiante_id, seccion_id)
);
-- Estos índices aceleran búsquedas frecuentes de cupos, matrículas y aprobados.
create index matriculas_activas_seccion on public.matriculas(seccion_id) where estado = 'ACTIVA';
create index matriculas_activas_estudiante on public.matriculas(estudiante_id) where estado = 'ACTIVA';
create index notas_aprobadas on public.notas(estudiante_id, curso_id) where nota >= 11;

-- Solo se puede aprobar o llevar una opción de cada grupo electivo del plan.
create function public.validar_grupo_electivo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_curso public.cursos%rowtype;
begin
  if new.estado <> 'ACTIVA' then return new; end if;
  select c.* into v_curso from public.secciones s
    join public.cursos c on c.id = s.curso_id where s.id = new.seccion_id;
  if v_curso.grupo_electivo is null then return new; end if;
  if exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    join public.cursos c on c.id = s.curso_id
    where m.estudiante_id = new.estudiante_id and m.estado = 'ACTIVA'
      and m.id is distinct from new.id and c.plan_id = v_curso.plan_id
      and c.grupo_electivo = v_curso.grupo_electivo
  ) or exists (
    select 1 from public.notas n join public.cursos c on c.id = n.curso_id
    where n.estudiante_id = new.estudiante_id and n.nota >= 11
      and c.plan_id = v_curso.plan_id and c.grupo_electivo = v_curso.grupo_electivo
  ) then
    raise exception 'Ya elegiste o aprobaste un curso de este grupo electivo';
  end if;
  return new;
end;
$$;
create trigger antes_de_grupo_electivo before insert or update on public.matriculas
for each row execute function public.validar_grupo_electivo();

-- El grupo de un curso con historial no puede cambiarse después.
create function public.proteger_grupo_electivo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.grupo_electivo is distinct from old.grupo_electivo
    and (exists (select 1 from public.notas where curso_id = old.id)
      or exists (select 1 from public.matriculas m
        join public.secciones s on s.id = m.seccion_id
        where s.curso_id = old.id and m.estado = 'ACTIVA')) then
    raise exception 'No puedes cambiar el grupo electivo de un curso con historial';
  end if;
  return new;
end;
$$;
create trigger antes_de_corregir_grupo before update of grupo_electivo on public.cursos
for each row execute function public.proteger_grupo_electivo();

-- Una cuenta con contraseña temporal aún no puede modificar matrículas.
-- Funciona como portero de la tabla: si la clave sigue siendo temporal, rechaza
-- cualquier inserción o actualización de matrícula.
create function public.exigir_clave_definitiva() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.perfiles
             where id = new.estudiante_id and clave_temporal) then
    raise exception 'Debes cambiar tu contraseña temporal antes de matricularte';
  end if;
  return new;
end;
$$;
create trigger antes_de_matricula before insert or update on public.matriculas
for each row execute function public.exigir_clave_definitiva();

-- Todo usuario nuevo comienza como estudiante. Un administrador otorga otros roles.
-- El trigger escucha altas en auth.users y crea automáticamente el perfil público.
create function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Si Auth no trae nombre, usamos la parte del correo anterior a @.
  insert into public.perfiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nombre', split_part(new.email, '@', 1)));
  return new;
end;
$$;
create trigger al_crear_usuario after insert on auth.users
for each row execute function public.crear_perfil();

-- Estas dos funciones contestan preguntas de permisos para las políticas RLS.
-- auth.uid() es el ID de quien inició sesión; clave_temporal impide operar
-- con funciones privilegiadas hasta cambiar la contraseña.
-- SECURITY DEFINER ejecuta con los permisos del dueño de la función;
-- search_path vacío exige nombres completos (public.tabla) y evita ambigüedad.
create function public.tiene_rol(p_rol text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol = p_rol and not clave_temporal
  );
$$;
-- "es_personal" agrupa Administrador y Dirección.
create function public.es_personal() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol in ('ADMINISTRADOR', 'DIRECCION')
      and not clave_temporal
  );
$$;

-- RLS es un filtro de seguridad dentro de la base, independiente del HTML.
-- Al activarlo, cada tabla necesita políticas explícitas para permitir accesos.
-- En las políticas, USING decide qué filas existentes puedes ver o modificar;
-- WITH CHECK decide qué filas nuevas o cambiadas puedes guardar.
alter table public.planes enable row level security;
alter table public.cursos enable row level security;
alter table public.prerrequisitos enable row level security;
alter table public.perfiles enable row level security;
alter table public.periodos enable row level security;
alter table public.docentes enable row level security;
alter table public.secciones enable row level security;
alter table public.notas enable row level security;
alter table public.matriculas enable row level security;

-- Planes, cursos y prerrequisitos: cualquier usuario conectado puede leerlos;
-- solo Administración puede crear, editar o borrar registros.
create policy leer_planes on public.planes for select to authenticated using (true);
create policy editar_planes on public.planes for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
create policy leer_cursos on public.cursos for select to authenticated using (true);
create policy editar_cursos on public.cursos for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
create policy leer_prerrequisitos on public.prerrequisitos for select to authenticated using (true);
create policy editar_prerrequisitos on public.prerrequisitos for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
-- Perfiles: cada quien ve el suyo; el personal ve todos. Solo Administración edita.
create policy leer_perfiles on public.perfiles for select to authenticated
  using (id = (select auth.uid()) or (select public.es_personal()));
create policy editar_perfiles on public.perfiles for update to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
-- Periodos: visibles a usuarios conectados; solo Administración los modifica.
create policy leer_periodos on public.periodos for select to authenticated using (true);
create policy editar_periodos on public.periodos for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
-- Docentes: visibles a usuarios conectados; Administración y Dirección editan.
create policy leer_docentes on public.docentes for select to authenticated using (true);
create policy editar_docentes on public.docentes for all to authenticated
  using ((select public.es_personal())) with check ((select public.es_personal()));
-- Secciones: el estudiante ve las publicadas; el personal ve también borradores.
create policy leer_secciones on public.secciones for select to authenticated
  using (publicada or (select public.es_personal()));
create policy editar_secciones on public.secciones for all to authenticated
  using ((select public.es_personal())) with check ((select public.es_personal()));
-- Notas: cada estudiante ve las suyas; el personal las consulta y solo
-- Administración puede corregirlas.
create policy leer_notas on public.notas for select to authenticated
  using (estudiante_id = (select auth.uid()) or (select public.es_personal()));
create policy editar_notas on public.notas for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
-- Matrículas: cada estudiante ve las suyas. No hay política de escritura
-- directa: para inscribirse o retirarse hay que pasar por las funciones de abajo.
create policy leer_matriculas on public.matriculas for select to authenticated
  using (estudiante_id = (select auth.uid()) or (select public.es_personal()));

-- Las claves con alcance autenticado respetan las políticas anteriores.
-- GRANT concede permiso general; RLS decide qué filas permite usar realmente.
-- En particular, la app solo puede leer matrículas directamente.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.planes, public.cursos,
  public.prerrequisitos, public.perfiles, public.periodos, public.docentes,
  public.secciones, public.notas to authenticated;
grant select on public.matriculas to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Serializa operaciones del mismo estudiante y bloquea la sección para evitar
-- sobreventa de vacantes incluso con solicitudes simultáneas.
-- INSCRIBIR es el único camino para crear o reactivar una matrícula.
-- SECURITY DEFINER permite que la función escriba donde el navegador no puede;
-- por eso la función verifica identidad, reglas académicas y cupos por sí sola.
create function public.inscribir(p_seccion_id bigint) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  -- Variables temporales: guardan el usuario y las filas necesarias mientras
  -- se ejecutan todas las comprobaciones de esta matrícula.
  v_usuario uuid := auth.uid();
  v_perfil public.perfiles%rowtype;
  v_seccion public.secciones%rowtype;
  v_periodo public.periodos%rowtype;
  v_curso public.cursos%rowtype;
  v_id bigint;
  v_creditos integer;
begin
  -- Paso 1: exige sesión y bloquea otras solicitudes simultáneas del mismo
  -- estudiante hasta terminar esta operación.
  if v_usuario is null then raise exception 'Debes iniciar sesión'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario::text, 0));
  -- Paso 2: confirma que es estudiante y que la sección existe y está publicada.
  -- FOR UPDATE bloquea esa sección mientras se revisan sus vacantes.
  select * into v_perfil from public.perfiles where id = v_usuario;
  if v_perfil.rol is distinct from 'ESTUDIANTE' then
    raise exception 'Solo los estudiantes pueden matricularse';
  end if;
  select * into v_seccion from public.secciones where id = p_seccion_id for update;
  if not found or not v_seccion.publicada then raise exception 'Sección no disponible'; end if;
  -- Paso 3: comprueba periodo activo y que el curso sea de su propia malla.
  select * into v_periodo from public.periodos where id = v_seccion.periodo_id;
  if not v_periodo.activo then raise exception 'El periodo no está activo'; end if;
  select * into v_curso from public.cursos where id = v_seccion.curso_id;
  if v_perfil.plan_id is distinct from v_curso.plan_id then
    raise exception 'El curso no pertenece a tu plan';
  end if;
  -- Paso 4: evita repetir un curso ya aprobado.
  if exists (select 1 from public.notas n where n.estudiante_id = v_usuario
      and n.curso_id = v_curso.id and n.nota >= 11) then
    raise exception 'Ya aprobaste este curso';
  end if;
  -- Paso 5: NOT EXISTS busca algún requisito sin una nota aprobatoria.
  -- Si aparece uno, todavía no puede llevar este curso.
  if exists (
    select 1 from public.prerrequisitos r
    where r.curso_id = v_curso.id and not exists (
      select 1 from public.notas n where n.estudiante_id = v_usuario
      and n.curso_id = r.requisito_id and n.nota >= 11
    )
  ) then raise exception 'Falta aprobar un prerrequisito'; end if;
  -- Paso 6: evita llevar dos secciones del mismo curso en el mismo periodo.
  if exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id and s.curso_id = v_curso.id
  ) then raise exception 'Ya estás matriculado en este curso'; end if;
  -- Paso 7: cuenta solo matrículas ACTIVAS; las retiradas ya no ocupan cupo.
  if (select count(*) from public.matriculas m
      where m.seccion_id = v_seccion.id and m.estado = 'ACTIVA') >= v_seccion.vacantes then
    raise exception 'No hay vacantes';
  end if;
  -- Paso 8: dos horarios se cruzan cuando cada uno empieza antes de que el
  -- otro termine, siempre que sean del mismo día y periodo.
  if exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id and s.dia = v_seccion.dia
      and s.inicio < v_seccion.fin and v_seccion.inicio < s.fin
  ) then raise exception 'El horario se cruza con otro curso'; end if;
  -- Paso 9: suma créditos actuales y comprueba que el nuevo curso no exceda
  -- el máximo configurado para el periodo.
  select coalesce(sum(c.creditos), 0) into v_creditos
    from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    join public.cursos c on c.id = s.curso_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id;
  if v_creditos + v_curso.creditos > v_periodo.max_creditos then
    raise exception 'Superas el límite de créditos';
  end if;
  -- Paso 10: crea la matrícula. Si ya existía pero estaba RETIRADA, la reactiva.
  -- RETURNING entrega el ID de la matrícula para responder a la aplicación.
  insert into public.matriculas(estudiante_id, seccion_id)
    values (v_usuario, v_seccion.id)
    on conflict (estudiante_id, seccion_id) do update
      set estado = 'ACTIVA', creada_en = now()
    returning id into v_id;
  return v_id;
end;
$$;

-- RETIRAR conserva el historial y libera una vacante. Solo la propia persona
-- puede retirarse y únicamente mientras el periodo esté activo.
create function public.retirar(p_matricula_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_usuario uuid := auth.uid();
  v_seccion_id bigint;
begin
  -- Reutiliza el bloqueo por estudiante para no cruzarse con una inscripción.
  if v_usuario is null then raise exception 'Debes iniciar sesión'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario::text, 0));
  -- Busca una matrícula activa, propia y de un periodo activo.
  select m.seccion_id into v_seccion_id
    from public.matriculas m join public.secciones s on s.id = m.seccion_id
    join public.periodos p on p.id = s.periodo_id
    where m.id = p_matricula_id and m.estudiante_id = v_usuario
      and m.estado = 'ACTIVA' and p.activo;
  if v_seccion_id is null then raise exception 'No puedes retirar esta matrícula'; end if;
  -- Bloquea la sección y cambia el estado; la fila no desaparece.
  perform 1 from public.secciones where id = v_seccion_id for update;
  update public.matriculas set estado = 'RETIRADA' where id = p_matricula_id;
end;
$$;

-- Cuenta pública de cupos sin mostrar la identidad de otros estudiantes.
-- LEFT JOIN incluye también secciones sin matrículas; GROUP BY cuenta sus filas.
-- El resultado muestra solo cuántos lugares quedan, nunca quiénes se inscribieron.
create function public.cupos() returns table(seccion_id bigint, disponibles integer)
language sql stable security definer set search_path = '' as $$
  select s.id, (s.vacantes - count(m.id))::integer
  from public.secciones s
  left join public.matriculas m on m.seccion_id = s.id and m.estado = 'ACTIVA'
  where auth.uid() is not null and (s.publicada or public.es_personal())
  group by s.id, s.vacantes;
$$;

-- ACTIVAR PERIODO es una operación de Administración: apaga el actual y
-- enciende el elegido. El índice de arriba garantiza que no queden dos activos.
create function public.activar_periodo(p_periodo_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.tiene_rol('ADMINISTRADOR') then
    raise exception 'Solo Administración puede activar periodos';
  end if;
  if not exists (select 1 from public.periodos where id = p_periodo_id) then
    raise exception 'Periodo inexistente';
  end if;
  update public.periodos set activo = false where activo;
  update public.periodos set activo = true where id = p_periodo_id;
end;
$$;

-- REVOKE cierra la ejecución de funciones; GRANT abre solo las que necesita
-- una persona autenticada. Las funciones de triggers se ejecutan desde la base,
-- no se llaman directamente desde el navegador.
revoke all on function public.crear_perfil() from public;
revoke all on function public.validar_prerrequisito() from public;
revoke all on function public.validar_grupo_electivo() from public;
revoke all on function public.proteger_grupo_electivo() from public;
revoke all on function public.exigir_clave_definitiva() from public;
revoke all on function public.tiene_rol(text) from public;
revoke all on function public.es_personal() from public;
revoke all on function public.inscribir(bigint) from public;
revoke all on function public.retirar(bigint) from public;
revoke all on function public.cupos() from public;
revoke all on function public.activar_periodo(bigint) from public;
-- Supabase puede otorgar EXECUTE a anon y authenticated mediante privilegios
-- predeterminados. Revocamos ambos explícitamente antes de abrir solo las RPC
-- que usa la aplicación para los usuarios autenticados.
revoke all on function public.crear_perfil(), public.validar_prerrequisito(), public.validar_grupo_electivo(), public.proteger_grupo_electivo(),
  public.exigir_clave_definitiva()
  from anon, authenticated;
revoke all on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) from anon, authenticated;
grant execute on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) to authenticated;

-- Las correcciones no deben invalidar matrículas o prerrequisitos ya existentes.
-- OLD es la fila antes de editarla; NEW es la versión propuesta.
-- Si la corrección rompe una regla, RAISE EXCEPTION cancela el cambio.
create function public.proteger_correccion_curso() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Un curso con notas conserva su plan para que las notas sigan teniendo
  -- sentido dentro de la malla original.
  if new.plan_id is distinct from old.plan_id
    and exists (select 1 from public.notas where curso_id = old.id) then
    raise exception 'No puedes mover de plan un curso que ya tiene notas';
  end if;
  -- Con matrículas activas tampoco se cambia el plan ni los créditos del curso.
  if (new.plan_id, new.creditos) is distinct from (old.plan_id, old.creditos)
    and exists (
      select 1 from public.matriculas m
      join public.secciones s on s.id = m.seccion_id
      where s.curso_id = old.id and m.estado = 'ACTIVA'
    ) then
    raise exception 'No puedes cambiar plan ni créditos de un curso con matrículas activas';
  end if;
  -- Verifica los dos lados de cada prerrequisito cuando cambian plan o ciclo.
  if exists (
    select 1 from public.prerrequisitos r
    join public.cursos otro on otro.id = case
      when r.curso_id = old.id then r.requisito_id else r.curso_id end
    where (r.curso_id = old.id and
      (new.plan_id is distinct from otro.plan_id or otro.ciclo >= new.ciclo))
      or (r.requisito_id = old.id and
      (new.plan_id is distinct from otro.plan_id or new.ciclo >= otro.ciclo))
  ) then
    raise exception 'El cambio dejaría un prerrequisito fuera del plan o del ciclo anterior';
  end if;
  return new;
end;
$$;
create trigger antes_de_corregir_curso before update on public.cursos
for each row execute function public.proteger_correccion_curso();

-- El límite de créditos de un periodo no puede bajar por debajo de lo que
-- algún estudiante ya tiene matriculado en ese periodo.
create function public.proteger_correccion_periodo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.max_creditos < old.max_creditos and exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    join public.cursos c on c.id = s.curso_id
    where s.periodo_id = old.id and m.estado = 'ACTIVA'
    group by m.estudiante_id
    having sum(c.creditos) > new.max_creditos
  ) then
    raise exception 'El nuevo límite dejaría matrículas existentes por encima del máximo de créditos';
  end if;
  return new;
end;
$$;
create trigger antes_de_corregir_periodo before update on public.periodos
for each row execute function public.proteger_correccion_periodo();

-- Una sección con estudiantes inscritos conserva curso, periodo, horario,
-- vacantes, código y publicación; docente, aula y laboratorio sí se corrigen.
create function public.proteger_correccion_seccion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.matriculas
             where seccion_id = old.id and estado = 'ACTIVA')
    and (new.periodo_id, new.curso_id, new.codigo, new.dia, new.inicio,
         new.fin, new.vacantes, new.publicada)
      is distinct from
        (old.periodo_id, old.curso_id, old.codigo, old.dia, old.inicio,
         old.fin, old.vacantes, old.publicada) then
    raise exception 'La sección tiene matrículas activas; solo puedes corregir docente, aula o laboratorio';
  end if;
  return new;
end;
$$;
create trigger antes_de_corregir_seccion before update on public.secciones
for each row execute function public.proteger_correccion_seccion();

-- Una nota aprobatoria puede ser la razón por la que se permitió matricular
-- al estudiante en un curso posterior. No se elimina ni desaprueba si es la
-- única aprobación que sostiene una matrícula activa.
create function public.proteger_correccion_nota() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_quita_aprobacion boolean;
begin
  -- DELETE elimina una nota; UPDATE también puede quitar la aprobación si
  -- cambia de estudiante, de curso o baja de 11.
  if tg_op = 'DELETE' then
    v_quita_aprobacion := true;
  else
    v_quita_aprobacion := old.estudiante_id is distinct from new.estudiante_id
      or old.curso_id is distinct from new.curso_id or new.nota < 11;
  end if;
  -- Si hay otra nota aprobatoria del mismo curso, esta corrección no quita
  -- el requisito. Si no la hay, buscamos una matrícula dependiente activa.
  if old.nota >= 11
    and v_quita_aprobacion
    and not exists (
      select 1 from public.notas n
      where n.id <> old.id and n.estudiante_id = old.estudiante_id
        and n.curso_id = old.curso_id and n.nota >= 11
    )
    and exists (
      select 1 from public.prerrequisitos r
      join public.secciones s on s.curso_id = r.curso_id
      join public.matriculas m on m.seccion_id = s.id and m.estado = 'ACTIVA'
      where r.requisito_id = old.curso_id and m.estudiante_id = old.estudiante_id
    ) then
    raise exception 'La nota aprobatoria sostiene una matrícula activa; revisa esa matrícula antes de corregirla';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger antes_de_corregir_nota before update or delete on public.notas
for each row execute function public.proteger_correccion_nota();

-- Los triggers se ejecutan automáticamente; nadie necesita invocar estas
-- cuatro funciones manualmente desde la aplicación.
revoke all on function public.proteger_correccion_curso(),
  public.proteger_correccion_periodo(), public.proteger_correccion_seccion(),
  public.proteger_correccion_nota()
  from public, anon, authenticated;
