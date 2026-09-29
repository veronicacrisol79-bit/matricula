# Matrícula

Una SPA de HTML, CSS y JavaScript con Alpine.js para la interfaz y Supabase para usuarios y datos. No necesita Next.js, React, Node.js ni compilación. Las bibliotecas de navegador están incluidas en `vendor/` para que la interfaz no dependa de un CDN.

Para entender cada archivo, cada módulo y el recorrido completo de una matrícula, lee [`EXPLICACION-CODIGO.md`](EXPLICACION-CODIGO.md).

## Qué hace

- **Administrador:** crea planes de estudio, cursos, prerrequisitos y periodos; asigna roles a usuarios existentes; registra notas y consulta matrículas.
- **Dirección:** registra docentes y secciones, horarios, aulas, laboratorios y vacantes; publica los cursos disponibles para matrícula.
- **Estudiante:** consulta su malla y los cursos disponibles, se matricula, se retira y ve su horario y notas.
- **Administración crea las cuentas** con una contraseña temporal única y asigna el plan. El estudiante cambia la contraseña obligatoriamente en su primer ingreso. El registro público debe permanecer deshabilitado en Supabase.
- La base verifica plazas, prerrequisitos aprobados, horarios cruzados, límite de créditos y duplicados dentro de una transacción.

## Instalar en una base nueva de Supabase

1. Crea un proyecto vacío en Supabase.
2. Abre **SQL Editor** y ejecuta [`schema.sql`](schema.sql) completo una sola vez. En el proyecto actual `anfishncoxydlojunwvf` ya se ejecutó y se verificaron las nueve tablas; no lo ejecutes de nuevo allí.
3. En **Authentication > Sign In / Providers**, deshabilita **Allow new users to sign up** después de crear la primera cuenta administradora. El alta de estudiantes se hará desde el panel de Administración.
4. [`config.js`](config.js) ya contiene la URL y la clave **publishable** del proyecto `anfishncoxydlojunwvf`. Son datos públicos del cliente. No copies la clave `service_role`, el password de Postgres ni `DATABASE_URL`.
5. Crea tu propia cuenta inicial en Supabase Auth. Para darle rol Administrador, ejecuta en SQL Editor, reemplazando el correo:

   ```sql
   update public.perfiles p
   set rol = 'ADMINISTRADOR', clave_temporal = false
   from auth.users u
   where p.id = u.id and u.email = 'TU_CORREO';
   ```

6. Si la base ya tiene el esquema anterior, ejecuta [`migracion-clave-temporal.sql`](migracion-clave-temporal.sql) una sola vez; en una base nueva el cambio ya está en `schema.sql`. En `anfishncoxydlojunwvf` la migración ya está aplicada.
7. Publica [`supabase/functions/gestionar-cuentas/index.ts`](supabase/functions/gestionar-cuentas/index.ts) como Edge Function `gestionar-cuentas`. Usa la autenticación de usuario de `@supabase/server`; en la configuración de la función deja desactivada la opción heredada **Verify JWT with legacy secret**. En `anfishncoxydlojunwvf` ya está publicada. La función valida el rol Administrador en la base y usa la clave secreta solo dentro de Supabase; nunca la pongas en el navegador. La opción «crear estudiante» confirma el correo bajo responsabilidad del administrador, quien debe comprobar la dirección y entregar la contraseña de forma privada.
8. Sirve esta carpeta con un servidor HTTP estático, por ejemplo `python -m http.server 8080`, y abre `http://localhost:8080`. Abrir `index.html` con `file://` no es recomendable.

## Despliegue

Sube el contenido de esta carpeta al repositorio de GitHub `matricula`, de modo que `index.html` quede en la raíz. En Render, crea un **Static Site** conectado a la rama `main` y configura:

| Campo | Valor |
|---|---|
| Root Directory | Vacío |
| Build Command | Vacío; si el formulario lo exige, `echo "No build required"` |
| Publish Directory | `.` |

El sitio no necesita servidor Node.js ni variables de entorno en Render. Cuando Render entregue la URL pública, configúrala en **Supabase Auth > URL Configuration > Site URL** y agrégala a **Redirect URLs**. Los cambios posteriores se publican al actualizar `main`.

## Orden para cargar datos

El proyecto actual `anfishncoxydlojunwvf` ya tiene los datos ficticios de [`datos-demo.sql`](datos-demo.sql): un plan DEMO, cinco cursos, dos prerrequisitos, un periodo activo, dos docentes y cinco secciones publicadas. **No es la malla oficial de la UNFV.** El archivo puede ejecutarse de nuevo sin duplicar esos registros. No crea cuentas, notas ni matrículas.

1. Administrador crea el plan y sus cursos. Los códigos, créditos y requisitos deben verificarse con el plan curricular oficial antes de publicarlo. Los PDF proporcionados no se han convertido automáticamente en datos.
2. Administrador crea un periodo activo y asigna un plan a cada estudiante.
3. Dirección crea docentes y secciones y las publica.
4. Administrador registra notas aprobatorias de periodos anteriores cuando hay prerrequisitos.
5. Estudiante se matricula.

## Límites de esta versión

La matrícula está limitada a una sección por curso y a un solo bloque semanal por sección. No incluye pagos, equivalencias entre planes, actas, auditoría institucional ni múltiples carreras. Las decisiones académicas y los datos del plan deben validarse antes de usarla con alumnos reales.

## Bibliotecas incluidas

- `vendor/supabase.js`: `@supabase/supabase-js` 2.117.2, licencia MIT en `vendor/supabase-LICENSE`.
- `vendor/alpine.min.js`: Alpine.js 3.17.4, licencia MIT en `vendor/alpine-LICENSE`.
