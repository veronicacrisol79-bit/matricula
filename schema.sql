-- Ejecutar una vez en el SQL Editor de un proyecto Supabase nuevo.
-- Todos los cambios de matrícula se hacen con funciones: el navegador no escribe
-- directamente en matriculas.

create table public.planes (
  id bigint generated always as identity primary key,
  nombre text not null,
  anio integer not null check (anio between 2000 and 2100),
  unique (nombre, anio)
);

create table public.cursos (
  id bigint generated always as identity primary key,
  plan_id bigint not null references public.planes(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  ciclo integer not null check (ciclo between 1 and 12),
  creditos integer not null check (creditos between 1 and 10),
  unique (plan_id, codigo)
);

create table public.prerrequisitos (
  curso_id bigint not null references public.cursos(id) on delete cascade,
  requisito_id bigint not null references public.cursos(id) on delete cascade,
  primary key (curso_id, requisito_id),
  check (curso_id <> requisito_id)
);

-- Un requisito debe ser de la misma malla y de un ciclo anterior. Esto
-- también impide cadenas circulares de requisitos.
create function public.validar_prerrequisito() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_curso public.cursos%rowtype;
  v_requisito public.cursos%rowtype;
begin
  select * into v_curso from public.cursos where id = new.curso_id;
  select * into v_requisito from public.cursos where id = new.requisito_id;
  if v_curso.plan_id is distinct from v_requisito.plan_id
    or v_requisito.ciclo >= v_curso.ciclo then
    raise exception 'El prerrequisito debe pertenecer al mismo plan y a un ciclo anterior';
  end if;
  return new;
end;
$$;
create trigger antes_de_prerrequisito before insert or update on public.prerrequisitos
for each row execute function public.validar_prerrequisito();

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null default '',
  codigo text unique,
  rol text not null default 'ESTUDIANTE'
    check (rol in ('ADMINISTRADOR', 'DIRECCION', 'ESTUDIANTE')),
  plan_id bigint references public.planes(id),
  clave_temporal boolean not null default true
);

create table public.periodos (
  id bigint generated always as identity primary key,
  nombre text not null unique,
  activo boolean not null default false,
  max_creditos integer not null default 24 check (max_creditos between 1 and 40)
);
create unique index solo_un_periodo_activo on public.periodos (activo) where activo;

create table public.docentes (
  id bigint generated always as identity primary key,
  nombre text not null,
  correo text
);

-- Una sección tiene un bloque semanal. Una segunda sesión requiere otra versión
-- del esquema y de la comprobación de cruces.
create table public.secciones (
  id bigint generated always as identity primary key,
  periodo_id bigint not null references public.periodos(id),
  curso_id bigint not null references public.cursos(id),
  docente_id bigint references public.docentes(id),
  codigo text not null,
  dia integer not null check (dia between 1 and 7),
  inicio time not null,
  fin time not null,
  aula text,
  laboratorio text,
  vacantes integer not null check (vacantes between 1 and 500),
  publicada boolean not null default false,
  check (inicio < fin),
  unique (periodo_id, curso_id, codigo)
);

create table public.notas (
  id bigint generated always as identity primary key,
  estudiante_id uuid not null references public.perfiles(id) on delete cascade,
  curso_id bigint not null references public.cursos(id),
  periodo_id bigint not null references public.periodos(id),
  nota numeric(4,1) not null check (nota between 0 and 20),
  unique (estudiante_id, curso_id, periodo_id)
);

create table public.matriculas (
  id bigint generated always as identity primary key,
  estudiante_id uuid not null references public.perfiles(id) on delete cascade,
  seccion_id bigint not null references public.secciones(id),
  estado text not null default 'ACTIVA' check (estado in ('ACTIVA', 'RETIRADA')),
  creada_en timestamptz not null default now(),
  unique (estudiante_id, seccion_id)
);
create index matriculas_activas_seccion on public.matriculas(seccion_id) where estado = 'ACTIVA';
create index matriculas_activas_estudiante on public.matriculas(estudiante_id) where estado = 'ACTIVA';
create index notas_aprobadas on public.notas(estudiante_id, curso_id) where nota >= 11;

-- Una cuenta con contraseña temporal aún no puede modificar matrículas.
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
create function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nombre', split_part(new.email, '@', 1)));
  return new;
end;
$$;
create trigger al_crear_usuario after insert on auth.users
for each row execute function public.crear_perfil();

create function public.tiene_rol(p_rol text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol = p_rol and not clave_temporal
  );
$$;
create function public.es_personal() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol in ('ADMINISTRADOR', 'DIRECCION')
      and not clave_temporal
  );
$$;

alter table public.planes enable row level security;
alter table public.cursos enable row level security;
alter table public.prerrequisitos enable row level security;
alter table public.perfiles enable row level security;
alter table public.periodos enable row level security;
alter table public.docentes enable row level security;
alter table public.secciones enable row level security;
alter table public.notas enable row level security;
alter table public.matriculas enable row level security;

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
create policy leer_perfiles on public.perfiles for select to authenticated
  using (id = (select auth.uid()) or (select public.es_personal()));
create policy editar_perfiles on public.perfiles for update to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
create policy leer_periodos on public.periodos for select to authenticated using (true);
create policy editar_periodos on public.periodos for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
create policy leer_docentes on public.docentes for select to authenticated using (true);
create policy editar_docentes on public.docentes for all to authenticated
  using ((select public.es_personal())) with check ((select public.es_personal()));
create policy leer_secciones on public.secciones for select to authenticated
  using (publicada or (select public.es_personal()));
create policy editar_secciones on public.secciones for all to authenticated
  using ((select public.es_personal())) with check ((select public.es_personal()));
create policy leer_notas on public.notas for select to authenticated
  using (estudiante_id = (select auth.uid()) or (select public.es_personal()));
create policy editar_notas on public.notas for all to authenticated
  using ((select public.tiene_rol('ADMINISTRADOR')))
  with check ((select public.tiene_rol('ADMINISTRADOR')));
create policy leer_matriculas on public.matriculas for select to authenticated
  using (estudiante_id = (select auth.uid()) or (select public.es_personal()));

-- Las claves con alcance autenticado respetan las políticas anteriores.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.planes, public.cursos,
  public.prerrequisitos, public.perfiles, public.periodos, public.docentes,
  public.secciones, public.notas to authenticated;
grant select on public.matriculas to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Serializa operaciones del mismo estudiante y bloquea la sección para evitar
-- sobreventa de vacantes incluso con solicitudes simultáneas.
create function public.inscribir(p_seccion_id bigint) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_usuario uuid := auth.uid();
  v_perfil public.perfiles%rowtype;
  v_seccion public.secciones%rowtype;
  v_periodo public.periodos%rowtype;
  v_curso public.cursos%rowtype;
  v_id bigint;
  v_creditos integer;
begin
  if v_usuario is null then raise exception 'Debes iniciar sesión'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario::text, 0));
  select * into v_perfil from public.perfiles where id = v_usuario;
  if v_perfil.rol is distinct from 'ESTUDIANTE' then
    raise exception 'Solo los estudiantes pueden matricularse';
  end if;
  select * into v_seccion from public.secciones where id = p_seccion_id for update;
  if not found or not v_seccion.publicada then raise exception 'Sección no disponible'; end if;
  select * into v_periodo from public.periodos where id = v_seccion.periodo_id;
  if not v_periodo.activo then raise exception 'El periodo no está activo'; end if;
  select * into v_curso from public.cursos where id = v_seccion.curso_id;
  if v_perfil.plan_id is distinct from v_curso.plan_id then
    raise exception 'El curso no pertenece a tu plan';
  end if;
  if exists (select 1 from public.notas n where n.estudiante_id = v_usuario
      and n.curso_id = v_curso.id and n.nota >= 11) then
    raise exception 'Ya aprobaste este curso';
  end if;
  if exists (
    select 1 from public.prerrequisitos r
    where r.curso_id = v_curso.id and not exists (
      select 1 from public.notas n where n.estudiante_id = v_usuario
      and n.curso_id = r.requisito_id and n.nota >= 11
    )
  ) then raise exception 'Falta aprobar un prerrequisito'; end if;
  if exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id and s.curso_id = v_curso.id
  ) then raise exception 'Ya estás matriculado en este curso'; end if;
  if (select count(*) from public.matriculas m
      where m.seccion_id = v_seccion.id and m.estado = 'ACTIVA') >= v_seccion.vacantes then
    raise exception 'No hay vacantes';
  end if;
  if exists (
    select 1 from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id and s.dia = v_seccion.dia
      and s.inicio < v_seccion.fin and v_seccion.inicio < s.fin
  ) then raise exception 'El horario se cruza con otro curso'; end if;
  select coalesce(sum(c.creditos), 0) into v_creditos
    from public.matriculas m
    join public.secciones s on s.id = m.seccion_id
    join public.cursos c on c.id = s.curso_id
    where m.estudiante_id = v_usuario and m.estado = 'ACTIVA'
      and s.periodo_id = v_periodo.id;
  if v_creditos + v_curso.creditos > v_periodo.max_creditos then
    raise exception 'Superas el límite de créditos';
  end if;
  insert into public.matriculas(estudiante_id, seccion_id)
    values (v_usuario, v_seccion.id)
    on conflict (estudiante_id, seccion_id) do update
      set estado = 'ACTIVA', creada_en = now()
    returning id into v_id;
  return v_id;
end;
$$;

create function public.retirar(p_matricula_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_usuario uuid := auth.uid();
  v_seccion_id bigint;
begin
  if v_usuario is null then raise exception 'Debes iniciar sesión'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_usuario::text, 0));
  select m.seccion_id into v_seccion_id
    from public.matriculas m join public.secciones s on s.id = m.seccion_id
    join public.periodos p on p.id = s.periodo_id
    where m.id = p_matricula_id and m.estudiante_id = v_usuario
      and m.estado = 'ACTIVA' and p.activo;
  if v_seccion_id is null then raise exception 'No puedes retirar esta matrícula'; end if;
  perform 1 from public.secciones where id = v_seccion_id for update;
  update public.matriculas set estado = 'RETIRADA' where id = p_matricula_id;
end;
$$;

-- Cuenta pública de cupos sin mostrar la identidad de otros estudiantes.
create function public.cupos() returns table(seccion_id bigint, disponibles integer)
language sql stable security definer set search_path = '' as $$
  select s.id, (s.vacantes - count(m.id))::integer
  from public.secciones s
  left join public.matriculas m on m.seccion_id = s.id and m.estado = 'ACTIVA'
  where auth.uid() is not null and (s.publicada or public.es_personal())
  group by s.id, s.vacantes;
$$;

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

revoke all on function public.crear_perfil() from public;
revoke all on function public.validar_prerrequisito() from public;
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
revoke all on function public.crear_perfil(), public.validar_prerrequisito(),
  public.exigir_clave_definitiva()
  from anon, authenticated;
revoke all on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) from anon, authenticated;
grant execute on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) to authenticated;

-- Las correcciones no deben invalidar matrículas o prerrequisitos ya existentes.
create function public.proteger_correccion_curso() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.plan_id is distinct from old.plan_id
    and exists (select 1 from public.notas where curso_id = old.id) then
    raise exception 'No puedes mover de plan un curso que ya tiene notas';
  end if;
  if (new.plan_id, new.creditos) is distinct from (old.plan_id, old.creditos)
    and exists (
      select 1 from public.matriculas m
      join public.secciones s on s.id = m.seccion_id
      where s.curso_id = old.id and m.estado = 'ACTIVA'
    ) then
    raise exception 'No puedes cambiar plan ni créditos de un curso con matrículas activas';
  end if;
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

create function public.proteger_correccion_nota() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_quita_aprobacion boolean;
begin
  if tg_op = 'DELETE' then
    v_quita_aprobacion := true;
  else
    v_quita_aprobacion := old.estudiante_id is distinct from new.estudiante_id
      or old.curso_id is distinct from new.curso_id or new.nota < 11;
  end if;
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

revoke all on function public.proteger_correccion_curso(),
  public.proteger_correccion_periodo(), public.proteger_correccion_seccion(),
  public.proteger_correccion_nota()
  from public, anon, authenticated;
