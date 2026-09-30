-- Datos inventados para practicar. No representan la malla oficial de la UNFV.
-- Se puede ejecutar de nuevo: los registros existentes no se duplican ni se sobrescriben.
-- No crea usuarios, notas ni matrículas.
-- Uso sugerido: ejecutarlo DESPUÉS de schema.sql para tener ejemplos que
-- puedas mostrar en clase. No lo ejecutes para cargar una malla oficial.

-- BEGIN/COMMIT agrupan las inserciones: se guardan juntas si todo sale bien.
begin;

-- DO ejecuta una pequeña receta de SQL; DECLARE guarda los IDs que necesitamos.
-- "v_" significa variable temporal de esta receta, no columna de una tabla.
do $$
declare
  v_plan_id bigint;
  v_periodo_id bigint;
  v_docente_a bigint;
  v_docente_b bigint;
begin
  -- Si el plan DEMO fue renombrado desde la aplicación, conserva su ID.
  -- Buscamos primero un curso conocido para encontrar su plan sin depender
  -- del nombre actual del plan.
  select min(plan_id) into v_plan_id from public.cursos where codigo = 'DEM-MAT101';
  if v_plan_id is null then
    -- Si todavía no existe el curso, creamos el plan de ejemplo.
    -- ON CONFLICT DO NOTHING significa "si ya existe, no lo dupliques".
    insert into public.planes (nombre, anio)
    values ('Plan DEMO de Ingeniería de Sistemas', 2026)
    on conflict (nombre, anio) do nothing;

    -- INTO STRICT exige encontrar exactamente una fila y guarda su ID.
    select id into strict v_plan_id from public.planes
    where nombre = 'Plan DEMO de Ingeniería de Sistemas' and anio = 2026;
  end if;

  -- Agrega cinco cursos inventados. El número tras DEM identifica el ciclo
  -- del ejemplo, pero la columna ciclo es la regla que usa la aplicación.
  insert into public.cursos (plan_id, codigo, nombre, ciclo, creditos)
  values
    (v_plan_id, 'DEM-MAT101', 'Fundamentos de Matemática', 1, 4),
    (v_plan_id, 'DEM-INF101', 'Introducción a la Programación', 1, 4),
    (v_plan_id, 'DEM-COM101', 'Comunicación Académica', 1, 3),
    (v_plan_id, 'DEM-MAT201', 'Matemática Discreta', 2, 4),
    (v_plan_id, 'DEM-INF201', 'Programación I', 2, 4)
  on conflict (plan_id, codigo) do nothing;

  -- Forma dos parejas curso/requisito usando los códigos legibles; JOIN
  -- busca los IDs reales que necesita la tabla prerrequisitos.
  insert into public.prerrequisitos (curso_id, requisito_id)
  select curso.id, requisito.id
  from (values
    ('DEM-MAT201', 'DEM-MAT101'),
    ('DEM-INF201', 'DEM-INF101')
  ) as pares(curso_codigo, requisito_codigo)
  join public.cursos curso on curso.plan_id = v_plan_id and curso.codigo = pares.curso_codigo
  join public.cursos requisito on requisito.plan_id = v_plan_id and requisito.codigo = pares.requisito_codigo
  on conflict (curso_id, requisito_id) do nothing;

  -- Crea un semestre ficticio con máximo de 14 créditos, sin duplicarlo.
  insert into public.periodos (nombre, max_creditos)
  values ('DEMO-2026-II', 14)
  on conflict (nombre) do nothing;

  select id into strict v_periodo_id from public.periodos
  where nombre = 'DEMO-2026-II';

  -- Solo activa el periodo DEMO si no existe otro periodo activo.
  -- Así no cambia la configuración de un semestre real ya activo.
  update public.periodos set activo = true
  where id = v_periodo_id
    and not exists (select 1 from public.periodos where activo);

  -- Registra dos nombres ficticios. WHERE NOT EXISTS evita duplicados porque
  -- la tabla docentes no exige que el nombre sea único.
  insert into public.docentes (nombre)
  select 'Docente DEMO A'
  where not exists (select 1 from public.docentes where nombre = 'Docente DEMO A');
  insert into public.docentes (nombre)
  select 'Docente DEMO B'
  where not exists (select 1 from public.docentes where nombre = 'Docente DEMO B');

  -- Recupera el ID de cada docente para enlazarlo a sus secciones.
  select id into strict v_docente_a from public.docentes
  where nombre = 'Docente DEMO A' order by id limit 1;
  select id into strict v_docente_b from public.docentes
  where nombre = 'Docente DEMO B' order by id limit 1;

  -- VALUES contiene cinco grupos de clase inventados. CASE decide qué
  -- docente asignar; ::time convierte textos como 08:00 a horas de PostgreSQL.
  -- TRUE los deja publicados; ON CONFLICT evita crear el mismo grupo otra vez.
  insert into public.secciones
    (periodo_id, curso_id, docente_id, codigo, dia, inicio, fin, aula, laboratorio, vacantes, publicada)
  select v_periodo_id, curso.id,
    case when datos.docente = 'A' then v_docente_a else v_docente_b end,
    datos.seccion, datos.dia, datos.inicio::time, datos.fin::time,
    datos.aula, datos.laboratorio, datos.vacantes, true
  from (values
    ('DEM-MAT101', 'A', 'A', 1, '08:00', '10:00', 'Aula DEMO 101', null::text, 25),
    ('DEM-INF101', 'A', 'B', 2, '08:00', '10:00', null::text, 'Lab DEMO 1', 20),
    ('DEM-COM101', 'A', 'A', 1, '09:00', '11:00', 'Aula DEMO 102', null::text, 25),
    ('DEM-MAT201', 'A', 'B', 3, '08:00', '10:00', 'Aula DEMO 201', null::text, 25),
    ('DEM-INF201', 'A', 'B', 4, '08:00', '10:00', null::text, 'Lab DEMO 2', 20)
  ) as datos(curso_codigo, seccion, docente, dia, inicio, fin, aula, laboratorio, vacantes)
  join public.cursos curso on curso.plan_id = v_plan_id and curso.codigo = datos.curso_codigo
  on conflict (periodo_id, curso_id, codigo) do nothing;
end;
$$;

-- Terminó la receta: guarda todas sus inserciones.
commit;

-- Recuento del ejemplo para verificarlo después de ejecutar el archivo.
-- Cada subconsulta cuenta una tabla y el resultado sale en una sola fila.
select
  (select count(distinct plan_id) from public.cursos where codigo like 'DEM-%') as planes_demo,
  (select count(*) from public.cursos where codigo like 'DEM-%') as cursos_demo,
  (select count(*) from public.prerrequisitos r join public.cursos c on c.id = r.curso_id where c.codigo like 'DEM-%') as prerrequisitos_demo,
  (select count(*) from public.periodos where nombre = 'DEMO-2026-II' and activo) as periodos_demo_activos,
  (select count(*) from public.docentes where nombre in ('Docente DEMO A', 'Docente DEMO B')) as docentes_demo,
  (select count(*) from public.secciones s join public.cursos c on c.id = s.curso_id where c.codigo like 'DEM-%' and s.publicada) as secciones_demo_publicadas;
