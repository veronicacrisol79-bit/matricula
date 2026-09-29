-- Ejecutar una vez en el proyecto donde schema.sql ya se ejecutó.
-- El script completo schema.sql ya incluye este ajuste para proyectos futuros.
revoke all on function public.crear_perfil(), public.validar_prerrequisito()
  from public, anon, authenticated;
revoke all on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) from public, anon, authenticated;
grant execute on function public.tiene_rol(text), public.es_personal(),
  public.inscribir(bigint), public.retirar(bigint), public.cupos(),
  public.activar_periodo(bigint) to authenticated;
