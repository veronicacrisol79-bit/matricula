-- Protege los datos existentes cuando Administración corrige cursos,
-- periodos o secciones. Ejecutar una vez en una base con schema.sql.
begin;

create or replace function public.proteger_correccion_curso() returns trigger
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
drop trigger if exists antes_de_corregir_curso on public.cursos;
create trigger antes_de_corregir_curso before update on public.cursos
for each row execute function public.proteger_correccion_curso();

create or replace function public.proteger_correccion_periodo() returns trigger
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
drop trigger if exists antes_de_corregir_periodo on public.periodos;
create trigger antes_de_corregir_periodo before update on public.periodos
for each row execute function public.proteger_correccion_periodo();

create or replace function public.proteger_correccion_seccion() returns trigger
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
drop trigger if exists antes_de_corregir_seccion on public.secciones;
create trigger antes_de_corregir_seccion before update on public.secciones
for each row execute function public.proteger_correccion_seccion();

create or replace function public.proteger_correccion_nota() returns trigger
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
drop trigger if exists antes_de_corregir_nota on public.notas;
create trigger antes_de_corregir_nota before update or delete on public.notas
for each row execute function public.proteger_correccion_nota();

revoke all on function public.proteger_correccion_curso(),
  public.proteger_correccion_periodo(), public.proteger_correccion_seccion(),
  public.proteger_correccion_nota()
  from public, anon, authenticated;
commit;
