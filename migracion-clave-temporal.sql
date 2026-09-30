-- Ejecutar UNA VEZ en el proyecto Supabase que ya tiene schema.sql.
-- Las cuentas existentes conservan acceso; las nuevas cambian su clave al entrar.
-- Una migración modifica una base ya creada sin borrar sus tablas ni datos.
-- Este archivo agrega la obligación de cambiar la clave inicial al entrar.
-- Las filas que ya existían reciben FALSE; las cuentas futuras reciben TRUE.
alter table public.perfiles
  add column if not exists clave_temporal boolean not null default false;
alter table public.perfiles alter column clave_temporal set default true;

-- Reemplazamos las funciones de permisos para que una cuenta con clave temporal
-- todavía no pueda actuar como Administrador o Dirección.
-- auth.uid() es la persona conectada; EXISTS responde sí o no.
create or replace function public.tiene_rol(p_rol text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol = p_rol and not clave_temporal
  );
$$;

-- Esta función responde si la persona es parte del personal académico.
create or replace function public.es_personal() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol in ('ADMINISTRADOR', 'DIRECCION')
      and not clave_temporal
  );
$$;

-- Esta función es el portero de matrículas: impide escribirlas mientras el
-- estudiante mantenga la contraseña temporal.
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

-- Quitamos el trigger anterior, si existía, y conectamos la nueva función a
-- cada intento de INSERT o UPDATE en matrículas.
drop trigger if exists antes_de_matricula on public.matriculas;
create trigger antes_de_matricula before insert or update on public.matriculas
for each row execute function public.exigir_clave_definitiva();

-- La función se ejecuta automáticamente por el trigger, no desde el navegador.
revoke all on function public.exigir_clave_definitiva() from public, anon, authenticated;
