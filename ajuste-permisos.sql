-- Ejecutar una vez en el proyecto donde schema.sql ya se ejecutó.
-- El script completo schema.sql ya incluye este ajuste para proyectos futuros.
-- Este archivo corrige permisos de una base antigua, sin tocar datos.
-- REVOKE cierra el acceso directo a funciones; PUBLIC significa cualquiera,
-- anon una visita sin sesión y authenticated una persona que inició sesión.
-- Los triggers siguen funcionando porque PostgreSQL los invoca internamente.
revoke all on function public.crear_perfil(), public.validar_prerrequisito()
  from public, anon, authenticated;
revoke all on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) from public, anon, authenticated;
-- GRANT abre únicamente las funciones que el usuario conectado necesita.
-- Cada una conserva sus validaciones internas y las tablas conservan RLS.
grant execute on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) to authenticated;
