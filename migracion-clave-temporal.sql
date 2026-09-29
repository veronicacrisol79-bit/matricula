-- Ejecutar UNA VEZ en el proyecto Supabase que ya tiene schema.sql.
-- Las cuentas existentes conservan acceso; las nuevas cambian su clave al entrar.
alter table public.perfiles
  add column if not exists clave_temporal boolean not null default false;
alter table public.perfiles alter column clave_temporal set default true;

create or replace function public.tiene_rol(p_rol text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol = p_rol and not clave_temporal
  );
$$;

create or replace function public.es_personal() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol in ('ADMINISTRADOR', 'DIRECCION')
      and not clave_temporal
  );
$$;

create or replace function public.exigir_clave_definitiva() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.perfiles
             where id = new.estudiante_id and clave_temporal) then
    raise exception 'Debes cambiar tu contraseña temporal antes de matricularte';
  end if;
  return new;
end;
$$;

drop trigger if exists antes_de_matricula on public.matriculas;
create trigger antes_de_matricula before insert or update on public.matriculas
for each row execute function public.exigir_clave_definitiva();

revoke all on function public.exigir_clave_definitiva() from public, anon, authenticated;
