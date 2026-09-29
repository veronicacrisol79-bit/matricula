# Guía para explicar el proyecto a estudiantes de primer ciclo

## 1. Qué estamos construyendo

Una aplicación de matrícula con tres tipos de usuario:

| Rol | Qué hace |
| --- | --- |
| Administrador | Crea planes, cursos, requisitos y periodos; asigna roles y registra notas. |
| Dirección | Organiza docentes, secciones, horarios, aulas, laboratorios y vacantes. |
| Estudiante | Consulta su plan, elige secciones, se retira y ve su horario. |

Un **plan de estudios** es la malla de una carrera y un año. Un **curso** pertenece a un plan y un ciclo. Una **sección** es un grupo concreto de un curso en un periodo, con horario, docente y vacantes. Una **matrícula** une a un estudiante con una sección. En **Cursos disponibles** se muestran las secciones publicadas para el periodo activo; Dirección las programa y publica en **Gestión académica**.

Administración crea cada cuenta de estudiante, asigna su plan y entrega una contraseña temporal única. Al entrar por primera vez, el estudiante debe cambiarla antes de usar la matrícula. Una Edge Function hace el alta con la clave secreta guardada en Supabase; el navegador nunca recibe esa clave. Los roles `DIRECCION` y `ADMINISTRADOR` se asignan solo desde una cuenta administradora. Para un sistema institucional real, el alta debería vincularse además con un padrón oficial.

## 2. Por qué son pocos archivos

- `index.html`: textos, formularios y tablas que ve el usuario.
- `styles.css`: colores, espacios y diseño para celular.
- `app.js`: acciones de la pantalla y llamadas a Supabase.
- `config.js`: URL y clave pública del proyecto nuevo.
- `schema.sql`: tablas, permisos y reglas de matrícula.
- `supabase/functions/gestionar-cuentas/index.ts`: crea cuentas y cambia contraseñas en el servidor.

Alpine.js actualiza la pantalla cuando cambian los datos. `supabase-js` envía las peticiones a Supabase. Ambas bibliotecas ya están copiadas en `vendor/`; no hay `npm install` ni `npm run build` para ejecutar la aplicación.

## 3. Cómo funciona una matrícula

```text
Estudiante pulsa «Matricularme»
             ↓
app.js llama a inscribir(seccion_id)
             ↓
Supabase comprueba identidad, plan, periodo, requisitos,
vacantes, horarios, créditos y duplicados
             ↓
Si todo está bien, guarda la matrícula y actualiza la pantalla
```

La pantalla es una ayuda visual. Las reglas se comprueban **también en la base**, porque una persona podría llamar a la API sin usar la pantalla. Supabase Auth identifica al usuario y las políticas RLS limitan qué datos puede leer o editar cada rol.

## 4. Ejercicio guiado

Para una explicación detallada de todos los archivos y funciones, usa [`EXPLICACION-CODIGO.md`](EXPLICACION-CODIGO.md). En el proyecto actual hay datos inventados cargados con [`datos-demo.sql`](datos-demo.sql); puedes revisarlos en lugar de crearlos desde cero.

1. Para repetir el proyecto desde cero, crear en Supabase un proyecto nuevo y ejecutar `schema.sql`.
2. Configurar `config.js` con la URL y la clave pública.
3. Crear la primera cuenta de Administrador y deshabilitar el registro público.
4. Crear un plan pequeño de prueba, con dos cursos de ciclo 1 y uno de ciclo 2.
5. Poner uno de los cursos de ciclo 1 como prerrequisito del de ciclo 2.
6. Crear un periodo activo, un docente y tres secciones.
7. Desde Administración, crear una cuenta de estudiante con contraseña temporal y asignarle el plan.
8. Entrar como estudiante y cambiar la contraseña temporal.
9. Intentar matricularse en el curso de ciclo 2. La base lo rechazará si falta la nota aprobatoria.
10. Registrar la nota del requisito desde Administración y volver a intentar.
11. Verificar que dos secciones del mismo horario se rechazan y que retirarse libera una vacante.

Usa datos inventados en esta práctica. Antes de cargar planes reales, coteja códigos, nombres, créditos y requisitos con el documento curricular oficial.

## 5. Cómo publicarlo

Primero funciona en local con `python -m http.server 8080`. Después se puede subir **esta carpeta a un repositorio nuevo** y conectarlo a Cloudflare Pages. Como es un sitio estático, no hay comando de compilación. Las actualizaciones de la rama elegida en GitHub se publican automáticamente.

La URL del sitio publicado debe añadirse a la configuración de redirección de Supabase Auth. La clave `service_role` y la contraseña de Postgres nunca van en `config.js` ni en GitHub.
