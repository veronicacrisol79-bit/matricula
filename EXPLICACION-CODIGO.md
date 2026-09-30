# Explicación completa del sistema de matrícula

Esta guía sirve para presentar el proyecto a estudiantes de primer ciclo. Los registros con la palabra **DEMO** son inventados; no son cursos ni reglas oficiales de la UNFV.

## 1. La idea en una frase

Una persona inicia sesión, ve lo que le corresponde según su rol y usa una página para consultar o registrar información. **Supabase guarda los datos y comprueba las reglas importantes.**

No usamos MVC formal. Es una **SPA con arquitectura cliente–servidor**: el navegador contiene HTML, CSS, JavaScript y Alpine.js; Supabase ofrece autenticación, PostgreSQL y una función de servidor.

```text
Usuario → index.html + Alpine.js → app.js → Supabase
                                          ├─ Auth: inicio de sesión
                                          ├─ PostgreSQL: planes, cursos y matrículas
                                          └─ Edge Function: creación de cuentas
```

**Por qué explicarlo así:** primero se entiende el recorrido de los datos; después es fácil ubicar cada archivo.

## 2. Vocabulario antes de mostrar código

| Término         | Significado                                       | Ejemplo DEMO                                 |
| ---------------- | ------------------------------------------------- | -------------------------------------------- |
| Plan de estudios | Lista de cursos de una carrera y año             | Plan DEMO de Ingeniería de Sistemas (2026)  |
| Curso            | Asignatura dentro de un plan                      | DEM-INF101: Introducción a la Programación |
| Prerrequisito    | Curso que debe aprobarse antes de otro            | DEM-INF101 antes de DEM-INF201               |
| Periodo          | Semestre en el que se abren grupos                | DEMO-2026-II                                 |
| Sección         | Grupo de un curso con horario, docente y vacantes | DEM-INF101, sección A, martes 08:00         |
| Matrícula       | Inscripción de un estudiante en una sección     | Estudiante inscrito en DEM-INF101 A          |
| Rol              | Permisos de una cuenta                            | Administrador, Dirección o Estudiante       |

**Curso y sección no son iguales.** Un curso pertenece a la malla; una sección es una forma concreta de dictarlo durante un periodo. La pestaña **Cursos disponibles** muestra secciones publicadas.

## 3. Archivos y responsabilidad de cada uno

### `index.html`: lo que aparece en pantalla

Contiene la cabecera, el logo, formularios, tablas, tarjetas y pestañas. Carga las bibliotecas, `config.js`, `app.js` y `styles.css`. En `<body x-data="app()" x-init="init()">`, Alpine crea el estado de la aplicación y ejecuta la carga inicial.

La pantalla tiene tres situaciones principales: inicio de sesión; cambio obligatorio de contraseña temporal; y panel de trabajo. En el panel, **Inicio** muestra cifras, **Malla** deja al administrador corregir planes, cursos, prerrequisitos y periodos, **Personas y notas** gestiona cuentas y permite corregir notas, **Docentes y secciones** permite corregir docentes y horarios, **Cursos disponibles** muestra lo publicado y **Mi matrícula** muestra las inscripciones del estudiante.

Algunas instrucciones de Alpine que conviene mostrar en clase:

| Instrucción                  | Qué hace en palabras sencillas                                       |
| ----------------------------- | --------------------------------------------------------------------- |
| `x-data="app()"`            | Conecta el HTML con los datos y funciones de`app.js`.               |
| `x-init="init()"`           | Recupera la sesión al abrir la página.                              |
| `x-model="auth.email"`      | Guarda lo escrito en un campo dentro del estado.                      |
| `x-show="tab === 'malla'"`  | Muestra u oculta una parte de la página.                             |
| `x-if="user && profile"`    | Crea una parte de la pantalla solo cuando corresponde.                |
| `x-for="c in data.cursos"`  | Repite una fila por cada curso.                                       |
| `x-text="c.nombre"`         | Coloca un dato como texto visible.                                    |
| `@submit.prevent="login()"` | Ejecuta una función al enviar un formulario sin recargar la página. |
| `:disabled="busy"`          | Desactiva un botón mientras se procesa una acción.                  |

**Por qué existe este archivo:** separa la estructura visual de las reglas y evita crear una página distinta para cada pestaña.

### `styles.css` y `assets/unfv-logo.png`: apariencia

El CSS define tamaños, espacios, tarjetas, tablas, formularios, avisos, colores naranja y negro, y ajustes para pantallas pequeñas mediante `@media`. La imagen del logo se carga desde `assets/`. El CSS comienza con reglas generales y al final contiene los ajustes visuales de identidad UNFV; las reglas posteriores prevalecen cuando tienen igual especificidad.

**Por qué existen:** permiten cambiar el diseño sin tocar la lógica de matrícula. El CSS ayuda a que las tablas y formularios se adapten a celulares.

### `config.js`: conexión pública

Indica la URL del proyecto Supabase y su clave **publishable**. El navegador necesita ambas para conectarse. Esa clave es pública y sus peticiones quedan sujetas a las políticas RLS y a la sesión del usuario. La contraseña de PostgreSQL y la clave `service_role` nunca se escriben aquí.

**Por qué existe:** cambiar de proyecto Supabase requiere modificar la conexión en un solo lugar.

### `app.js`: comportamiento de la página

La función `app()` crea un objeto con datos, estado y acciones. Los grupos más importantes son:

| Grupo                  | Funciones o variables                                                                                                                                                                     | Explicación                                                                                                                             |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Estado                 | `user`, `profile`, `tab`, `data`, `form`, `busy`, `message`, `error`                                                                                                      | Recuerdan quién está conectado, qué pestaña se ve y qué datos llegaron.                                                             |
| Datos calculados       | `role`, `activePeriod`, `myPlan`, `myCourses`, `offers`, `myEnrollments`, `enrolledCredits`                                                                                 | Obtienen información útil a partir de los datos cargados.`offers` filtra las secciones publicadas del periodo y plan del estudiante. |
| Ayudas visuales        | `nameOf`, `course`, `section`, `day`, `remaining`, `requirements`                                                                                                             | Transforman IDs y números en textos como nombres, días y vacantes.                                                                     |
| Sesión                | `init`, `enter`, `login`, `logout`                                                                                                                                                | Recuperan la sesión, leen el perfil y permiten entrar o salir.                                                                          |
| Cuentas                | `createStudent`, `changePassword`                                                                                                                                                     | Llaman a la Edge Function para crear un estudiante o sustituir su contraseña temporal.                                                  |
| Lectura                | `refresh`                                                                                                                                                                               | Lee las tablas en paralelo y consulta la función`cupos`; RLS decide qué filas puede ver cada usuario.                                |
| Escritura simple       | `save`, `update`, `addPlan`, `addCourse`, `savePlanChanges`, `saveCourseChanges`, `savePeriodChanges`, `saveTeacherChanges`, `saveSectionChanges`, `saveGradeChanges` | Crean o corrigen registros y luego actualizan la pantalla.                                                                               |
| Operaciones con reglas | `rpc`, `activatePeriod`, `enroll`, `withdraw`                                                                                                                                     | Invocan funciones SQL para operaciones que requieren comprobaciones y transacciones.                                                     |

Ejemplo: al pulsar **Matricularme**, el HTML llama a `enroll(s.id)`. `app.js` llama a la función SQL `inscribir` y, si todo sale bien, ejecuta `refresh()` para mostrar la matrícula actualizada.

**Por qué existe:** concentra la interacción del navegador en un archivo corto. Alpine escucha los cambios de ese estado y actualiza la pantalla sin recargarla.

### `schema.sql`: datos, relaciones y seguridad

Es el esquema de PostgreSQL para una base nueva. Las nueve tablas son:

| Tabla              | Guarda                                             | Relación principal                                 |
| ------------------ | -------------------------------------------------- | --------------------------------------------------- |
| `planes`         | Nombre y año de la malla                          | Tiene muchos cursos.                                |
| `cursos`         | Código, nombre, ciclo y créditos                 | Pertenece a un plan.                                |
| `prerrequisitos` | Pares de cursos                                    | Une un curso con otro anterior del mismo plan.      |
| `perfiles`       | Nombre, código, rol, plan y estado de contraseña | Su`id` corresponde a un usuario de Supabase Auth. |
| `periodos`       | Semestres y límite de créditos                   | Solo uno puede estar activo.                        |
| `docentes`       | Datos del profesorado                              | Se asignan a secciones.                             |
| `secciones`      | Horario, aula, vacantes y publicación             | Une periodo, curso y docente.                       |
| `notas`          | Calificación de un estudiante en un curso         | Permite saber si aprobó un prerrequisito.          |
| `matriculas`     | Inscripciones y retiros                            | Une estudiante y sección.                          |

Las **claves foráneas** impiden referencias a datos inexistentes. Las restricciones `unique` y `check` impiden duplicados y valores fuera de rango. Por ejemplo, una sección exige `inicio < fin` y vacantes entre 1 y 500.

El esquema también activa **RLS** (seguridad por filas). El administrador edita planes y periodos; el personal académico gestiona docentes y secciones; el estudiante ve sus propias notas y matrículas. Ocultar un botón en HTML ayuda a la interfaz, pero **la protección real está en la base**.

Funciones SQL que debes conocer:

| Función                        | Para qué sirve                                                           |
| ------------------------------- | ------------------------------------------------------------------------- |
| `crear_perfil`                | Crea el perfil cuando Auth crea un usuario.                               |
| `validar_prerrequisito`       | Rechaza un requisito de otro plan o de un ciclo no anterior.              |
| `tiene_rol` / `es_personal` | Apoyan las políticas RLS según la cuenta conectada.                     |
| `exigir_clave_definitiva`     | Impide modificar matrículas con contraseña temporal.                    |
| `activar_periodo`             | Desactiva el periodo anterior y activa el elegido.                        |
| `cupos`                       | Cuenta matrículas activas sin revelar la identidad de otros estudiantes. |
| `inscribir`                   | Valida y guarda una matrícula.                                           |
| `retirar`                     | Marca una matrícula activa como retirada.                                |

`inscribir` comprueba, en este orden, que la persona sea estudiante; que la sección esté publicada en un periodo activo; que el curso pertenezca a su plan; que no lo haya aprobado; que cumpla los prerrequisitos; que no esté duplicado; que queden vacantes; que no se cruce el horario; y que no exceda los créditos. Usa bloqueos para que dos solicitudes simultáneas no ocupen la última vacante. Si una comprobación falla, la operación completa se revierte.

**Por qué existe:** un usuario podría enviar peticiones directamente a Supabase sin pasar por nuestros botones. Las reglas críticas deben cumplirse en el servidor.

### `supabase/functions/gestionar-cuentas/index.ts`: altas y contraseñas

Es una **Edge Function** que se ejecuta en Supabase. Recibe una petición `POST`, identifica al usuario autenticado y lee su rol. La acción `crear-estudiante` solo admite un administrador: valida datos, crea el usuario en Supabase Auth y asigna código, plan y contraseña temporal. Si falla la asignación del perfil, elimina la cuenta recién creada. La acción `cambiar-clave` comprueba la contraseña temporal actual, asigna una nueva diferente y quita la marca `clave_temporal`.

La función usa la clave secreta **en el servidor**. `app.js` solo le envía la petición con la sesión del usuario. No hay contraseña general predeterminada para todos.

**Por qué existe:** el navegador no debe recibir una clave con permisos para crear usuarios o cambiar las contraseñas de otras personas.

### `datos-demo.sql`, migraciones y bibliotecas

`datos-demo.sql` inserta un plan inventado, cinco cursos, dos requisitos, un periodo, dos docentes y cinco secciones. Usa `on conflict ... do nothing`, de modo que repetirlo no duplica estos registros. No crea cuentas ni matrículas.

`migracion-clave-temporal.sql` añadió el cambio obligatorio de contraseña a una base que ya existía. `ajuste-permisos.sql` corrige permisos de funciones en instalaciones anteriores. En una base nueva, basta `schema.sql`; estos archivos de migración **no se ejecutan otra vez** sobre el proyecto actual.

`migracion-correcciones.sql` añadió cuatro validaciones al proyecto actual: un curso con notas no cambia de plan; una sección con matrículas activas no cambia de curso, horario, vacantes ni publicación; no se puede bajar el límite de créditos de un periodo por debajo de matrículas existentes; y una nota aprobatoria no se quita si es el único requisito que sostiene una matrícula activa. También se comprueba que al cambiar el ciclo de un curso sus prerrequisitos sigan siendo de ciclos anteriores. Una base nueva ya incluye estas reglas en `schema.sql`.

`vendor/alpine.min.js` actualiza la interfaz. `vendor/supabase.js` conecta con Auth, tablas y funciones de Supabase. Los archivos `*-LICENSE` contienen sus licencias. No hay React, Next.js, compilación ni servidor Node para servir la página.

## 4. Recorridos que conviene mostrar en vivo

### Inicio de sesión

1. La persona escribe correo y contraseña en `index.html`.
2. `login()` de `app.js` pide a Supabase Auth que valide las credenciales.
3. `enter()` lee `perfiles` para conocer el rol y si falta cambiar la contraseña temporal.
4. `refresh()` obtiene los datos permitidos por RLS.
5. Alpine muestra el panel que corresponde a ese estado.

### Alta de estudiante

1. Administración abre **Personas y notas** y escribe nombre, código, correo, plan y contraseña temporal.
2. `createStudent()` llama a `gestionar-cuentas`.
3. La función comprueba el rol y crea la cuenta y el perfil.
4. El estudiante inicia sesión y `changePassword()` le exige una contraseña personal.

### Matrícula

1. Dirección publica una sección en **Docentes y secciones**.
2. El estudiante la ve en **Cursos disponibles** y pulsa **Matricularme**.
3. `enroll()` llama a `inscribir` en PostgreSQL.
4. La base valida requisitos, horario, vacantes y créditos y guarda la matrícula.
5. La pantalla se actualiza; el estudiante ve el resultado en **Mi matrícula**.

## 5. Demostración con los datos ficticios

Los datos DEMO ya están cargados en el proyecto Supabase `anfishncoxydlojunwvf`. Hay un periodo activo llamado `DEMO-2026-II` con **14 créditos máximos**. Las cinco secciones están publicadas. Matemática y Comunicación se cruzan el lunes entre 09:00 y 10:00 para mostrar la validación de horario. Los dos cursos de ciclo 2 requieren aprobar sus cursos de ciclo 1.

1. Recarga la aplicación local en `http://localhost:8080/` e inicia sesión como Administrador.
2. Abre **Malla** y señala los cinco cursos y los dos prerrequisitos.
3. Abre **Docentes y secciones** y muestra los horarios y el estado publicado.
4. Abre **Cursos disponibles** y explica que son grupos abiertos para el periodo activo.
5. Para probar la matrícula, crea desde **Personas y notas** una cuenta de prueba con un correo de prueba bajo tu control, asígnale el plan DEMO y entrégale una contraseña temporal única. No uses datos reales de un alumno.
6. Inicia sesión con esa cuenta, cambia la contraseña y prueba matricularte en un curso del ciclo 2: la base debe rechazarlo por faltar el prerrequisito.
7. Prueba dos secciones superpuestas: la segunda debe rechazarse por cruce de horario.
8. Si deseas demostrar la aprobación, vuelve a Administración y registra una nota de al menos 11 en el curso requisito. Al intentar otra vez, esa comprobación ya se cumple.

## 6. Guion breve para exponer

1. **Problema:** “Necesitamos organizar planes, cursos, horarios, usuarios y matrículas.”
2. **Modelo:** muestra la diferencia entre plan, curso, sección y matrícula con la tabla del apartado 2.
3. **Tecnologías:** “HTML dibuja, CSS da estilo, Alpine conecta la pantalla con JavaScript, Supabase Auth identifica y PostgreSQL guarda y valida.”
4. **Roles:** “Administración configura y crea cuentas; Dirección prepara secciones; Estudiante elige y consulta.”
5. **Código:** abre `index.html`, `app.js`, `schema.sql` y la Edge Function, en ese orden.
6. **Demostración:** sigue el recorrido de matrícula y provoca un rechazo por requisito o cruce.
7. **Cierre:** “La pantalla orienta; la base de datos hace cumplir las reglas.”

**Por qué debes explicar cada módulo:** quien te escuche necesita saber dónde cambiar una pantalla, dónde cambiar una acción y dónde cambiar una regla académica. También debe entender por qué un usuario no puede obtener permisos extra simplemente cambiando el HTML desde su navegador.

## 7. Preguntas frecuentes

- **¿Por qué Alpine.js?** Para repetir datos y mostrar cambios sin escribir muchas instrucciones de manipulación del DOM.
- **¿Por qué no usamos MVC?** La aplicación es pequeña y `app.js` reúne estado y acciones; separar controladores y modelos en más archivos aumentaría el código de esta versión.
- **¿Por qué usar funciones SQL para matricular?** Varias comprobaciones deben suceder juntas y en el servidor, incluso si llegan dos solicitudes a la vez.
- **¿La clave pública de `config.js` da acceso a todo?** No. Los permisos dependen de la sesión, RLS y las funciones autorizadas.
- **¿Los cursos DEMO son oficiales?** No. Son inventados para aprender y probar el programa.
