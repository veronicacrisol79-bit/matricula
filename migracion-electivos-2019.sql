-- Ejecutar una vez antes de cargar plan-2019-sistemas.sql.
-- Conserva planes, cursos, usuarios, notas y matrículas existentes.
begin;

alter table public.cursos
  add column if not exists grupo_electivo smallint;

alter table public.cursos
  drop constraint if exists cursos_grupo_electivo_check;
alter table public.cursos
  add constraint cursos_grupo_electivo_check
  check (grupo_electivo between 1 and 3);

create or replace function public.validar_grupo_electivo() returns trigger
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

drop trigger if exists antes_de_grupo_electivo on public.matriculas;
create trigger antes_de_grupo_electivo before insert or update on public.matriculas
for each row execute function public.validar_grupo_electivo();

create or replace function public.proteger_grupo_electivo() returns trigger
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

drop trigger if exists antes_de_corregir_grupo on public.cursos;
create trigger antes_de_corregir_grupo before update of grupo_electivo on public.cursos
for each row execute function public.proteger_grupo_electivo();

revoke all on function public.validar_grupo_electivo(), public.proteger_grupo_electivo()
  from public, anon, authenticated;

commit;
