import { withSupabase } from 'npm:@supabase/server@^1'

// La clave secreta vive solo en Supabase. El navegador envía el JWT del usuario.
export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ error: 'Método no permitido' }, { status: 405 })

    let body
    try { body = await req.json() } catch {
      return Response.json({ error: 'Solicitud inválida' }, { status: 400 })
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return Response.json({ error: 'Solicitud inválida' }, { status: 400 })
    }

    const { data: actor, error: actorError } = await ctx.supabase
      .from('perfiles').select('rol, clave_temporal').eq('id', ctx.userClaims.id).single()
    if (actorError || !actor) return Response.json({ error: 'Perfil no encontrado' }, { status: 403 })

    if (body.accion === 'cambiar-clave') {
      if (!actor.clave_temporal) return Response.json({ error: 'La contraseña ya fue cambiada' }, { status: 409 })
      const password = String(body.password || '')
      const actual = String(body.password_actual || '')
      if (!actual || password === actual || password.length < 10 || password.length > 128) {
        return Response.json({ error: 'La nueva contraseña debe tener entre 10 y 128 caracteres' }, { status: 400 })
      }
      const { data: verified, error: verifyError } = await ctx.supabase.auth.signInWithPassword({
        email: ctx.userClaims.email, password: actual
      })
      if (verifyError || verified.user?.id !== ctx.userClaims.id) {
        return Response.json({ error: 'La contraseña temporal es incorrecta' }, { status: 403 })
      }
      const { error } = await ctx.supabaseAdmin.auth.admin.updateUserById(ctx.userClaims.id, { password })
      if (error) return Response.json({ error: error.message }, { status: 400 })
      const { error: profileError } = await ctx.supabaseAdmin.from('perfiles')
        .update({ clave_temporal: false }).eq('id', ctx.userClaims.id)
      if (profileError) return Response.json({ error: 'Contraseña cambiada, pero no se pudo habilitar la cuenta. Intenta de nuevo.' }, { status: 500 })
      return Response.json({ ok: true })
    }

    if (body.accion === 'crear-estudiante') {
      if (actor.rol !== 'ADMINISTRADOR' || actor.clave_temporal) {
        return Response.json({ error: 'Solo Administración puede crear estudiantes' }, { status: 403 })
      }
      const nombre = String(body.nombre || '').trim()
      const codigo = String(body.codigo || '').trim()
      const email = String(body.email || '').trim().toLowerCase()
      const password = String(body.password || '')
      const planId = Number(body.plan_id)
      if (!nombre || nombre.length > 120 || !codigo || codigo.length > 30 ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 8 ||
          password.length > 128 || !Number.isSafeInteger(planId) || planId < 1) {
        return Response.json({ error: 'Revisa nombre, código, correo, plan y contraseña temporal' }, { status: 400 })
      }

      const { data, error } = await ctx.supabaseAdmin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { nombre }
      })
      if (error || !data.user) return Response.json({ error: error?.message || 'No se pudo crear el usuario' }, { status: 400 })

      const { error: profileError } = await ctx.supabaseAdmin.from('perfiles')
        .update({ nombre, codigo, plan_id: planId, clave_temporal: true })
        .eq('id', data.user.id).select('id').single()
      if (profileError) {
        await ctx.supabaseAdmin.auth.admin.deleteUser(data.user.id)
        return Response.json({ error: 'No se pudo asignar el plan o el código. Comprueba que no estén duplicados.' }, { status: 400 })
      }
      return Response.json({ ok: true, id: data.user.id })
    }

    return Response.json({ error: 'Acción no reconocida' }, { status: 400 })
  }),
}
