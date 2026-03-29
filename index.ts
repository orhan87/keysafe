// ============================================================
// Supabase Edge Function: invite-user
// Dosya yolu: supabase/functions/invite-user/index.ts
//
// Kurulum:
//   1. supabase/functions/invite-user/ klasörü oluştur
//   2. Bu dosyayı index.ts olarak kaydet
//   3. Supabase Dashboard → Edge Functions → Deploy
//      VEYA: supabase functions deploy invite-user
//
// Gerekli Environment Variables (Supabase → Settings → Edge Functions):
//   RESEND_API_KEY   → Resend API anahtarın (ibkbsorgulama'dan aynısı)
//   SITE_URL         → https://govdag.com veya GitHub Pages URL'i
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ── İSTEK DOĞRULAMA ──────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Yetki başlığı eksik')

    // Admin Supabase client (service role — RLS'i atlar)
    const sbAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Normal client — isteği yapan kullanıcıyı doğrula
    const sbUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: userErr } = await sbUser.auth.getUser()
    if (userErr || !user) throw new Error('Oturum geçersiz')

    // ── PARAMETRELER ─────────────────────────────────────────
    const { bureau_id, email, role } = await req.json()
    if (!bureau_id || !email || !role) throw new Error('Eksik parametre: bureau_id, email, role gerekli')
    if (!['admin','member'].includes(role)) throw new Error('Geçersiz rol')

    // ── YETKİ KONTROLÜ ───────────────────────────────────────
    const { data: myMembership } = await sbAdmin
      .from('bureau_members')
      .select('role')
      .eq('bureau_id', bureau_id)
      .eq('user_id', user.id)
      .single()

    if (!myMembership || !['owner','admin'].includes(myMembership.role)) {
      throw new Error('Bu işlem için yetkiniz yok')
    }

    // ── BÜRO BİLGİSİ ─────────────────────────────────────────
    const { data: bureau } = await sbAdmin
      .from('bureaus')
      .select('name')
      .eq('id', bureau_id)
      .single()

    // ── KULLANICI ZATEN VAR MI? ───────────────────────────────
    const { data: { users } } = await sbAdmin.auth.admin.listUsers()
    const existingUser = users?.find(u => u.email === email)

    if (existingUser) {
      // Zaten büro üyesi mi?
      const { data: alreadyMember } = await sbAdmin
        .from('bureau_members')
        .select('id')
        .eq('bureau_id', bureau_id)
        .eq('user_id', existingUser.id)
        .single()

      if (alreadyMember) {
        return new Response(
          JSON.stringify({ success: false, message: 'Bu kullanıcı zaten büro üyesi' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
        )
      }

      // Direkt ekle
      await sbAdmin.from('bureau_members').insert({
        bureau_id,
        user_id: existingUser.id,
        role,
        invited_by: user.id,
      })

      // Bildirim e-postası gönder
      await sendEmail({
        to: email,
        subject: `${bureau?.name} sizi Gövdağ'a ekledi`,
        html: buildAddedEmail(bureau?.name, role),
      })

      return new Response(
        JSON.stringify({ success: true, message: 'Kullanıcı büroya eklendi', type: 'added' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ── KULLANICI YOK — DAVET TOKEN OLUŞTUR ──────────────────
    // Önceki süresi dolmamış daveti iptal et
    await sbAdmin
      .from('invite_tokens')
      .update({ used: true })
      .eq('bureau_id', bureau_id)
      .eq('email', email)
      .eq('used', false)

    // Yeni token oluştur
    const { data: invite, error: inviteErr } = await sbAdmin
      .from('invite_tokens')
      .insert({ bureau_id, invited_by: user.id, email, role })
      .select()
      .single()

    if (inviteErr) throw inviteErr

    const siteUrl  = Deno.env.get('SITE_URL') || 'https://govdag.com'
    const inviteUrl = `${siteUrl}/register.html?token=${invite.token}&email=${encodeURIComponent(email)}`

    // ── DAVET E-POSTASI ───────────────────────────────────────
    await sendEmail({
      to: email,
      subject: `${bureau?.name} sizi Gövdağ'a davet etti`,
      html: buildInviteEmail(bureau?.name, role, inviteUrl),
    })

    return new Response(
      JSON.stringify({ success: true, message: 'Davet e-postası gönderildi', type: 'invited' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, message: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})

// ── E-POSTA GÖNDER (Resend) ───────────────────────────────────
async function sendEmail({ to, subject, html }: { to: string; subject: string; html: string }) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Gövdağ <destek@govdag.com>',
      to: [to],
      subject,
      html,
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    throw new Error('E-posta gönderilemedi: ' + err)
  }
}

// ── E-POSTA ŞABLONLARı ───────────────────────────────────────
function buildInviteEmail(bureauName: string, role: string, inviteUrl: string): string {
  const roleTr = role === 'admin' ? 'Admin' : 'Üye'
  return `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0a0b12;font-family:'Segoe UI',sans-serif;">
  <div style="max-width:520px;margin:40px auto;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.12);border-radius:20px;overflow:hidden;">
    <div style="background:linear-gradient(135deg,#4a2db5,#0e5c9e);padding:32px 40px;text-align:center;">
      <div style="font-size:28px;font-weight:700;color:#fff;letter-spacing:-0.02em;">gövda<span style="color:#7eeaad;">ğ</span></div>
      <div style="font-size:12px;color:rgba(255,255,255,0.6);margin-top:4px;letter-spacing:0.06em;">güvenli parola kasası</div>
    </div>
    <div style="padding:36px 40px;">
      <h1 style="font-size:20px;font-weight:700;color:#fff;margin:0 0 8px;">${bureauName} sizi davet etti</h1>
      <p style="font-size:14px;color:rgba(255,255,255,0.6);line-height:1.6;margin:0 0 24px;">
        <strong style="color:#7eeaad;">${bureauName}</strong> bürosuna <strong style="color:#fff;">${roleTr}</strong> olarak katılmaya davet edildiniz.
        Gövdağ, ekibinizin site parolalarını güvenle yönettiği bir parola kasasıdır.
      </p>
      <div style="text-align:center;margin:28px 0;">
        <a href="${inviteUrl}" style="display:inline-block;padding:14px 32px;background:rgba(126,234,173,0.18);border:1px solid rgba(126,234,173,0.38);border-radius:50px;color:#7eeaad;font-size:13px;font-weight:700;text-decoration:none;letter-spacing:0.06em;">
          Daveti Kabul Et →
        </a>
      </div>
      <p style="font-size:11px;color:rgba(255,255,255,0.3);text-align:center;margin:0;">
        Bu davet 7 gün geçerlidir. Daveti siz talep etmediyseniz bu e-postayı görmezden gelebilirsiniz.
      </p>
    </div>
    <div style="padding:20px 40px;border-top:1px solid rgba(255,255,255,0.07);text-align:center;">
      <p style="font-size:11px;color:rgba(255,255,255,0.3);margin:0;">© 2026 Gövdağ — Tüm hakları saklıdır</p>
    </div>
  </div>
</body>
</html>`
}

function buildAddedEmail(bureauName: string, role: string): string {
  const roleTr = role === 'admin' ? 'Admin' : 'Üye'
  return `<!DOCTYPE html>
<html lang="tr">
<head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#0a0b12;font-family:'Segoe UI',sans-serif;">
  <div style="max-width:520px;margin:40px auto;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.12);border-radius:20px;overflow:hidden;">
    <div style="background:linear-gradient(135deg,#4a2db5,#0e5c9e);padding:32px 40px;text-align:center;">
      <div style="font-size:28px;font-weight:700;color:#fff;">gövda<span style="color:#7eeaad;">ğ</span></div>
    </div>
    <div style="padding:36px 40px;">
      <h1 style="font-size:20px;font-weight:700;color:#fff;margin:0 0 12px;">${bureauName} bürosuna eklendiniz</h1>
      <p style="font-size:14px;color:rgba(255,255,255,0.6);line-height:1.6;margin:0 0 24px;">
        <strong style="color:#7eeaad;">${bureauName}</strong> bürosuna <strong style="color:#fff;">${roleTr}</strong> olarak eklendiniz.
        Giriş yaparak kasaya erişebilirsiniz.
      </p>
      <div style="text-align:center;">
        <a href="${Deno.env.get('SITE_URL') || 'https://govdag.com'}/login.html" style="display:inline-block;padding:14px 32px;background:rgba(126,234,173,0.18);border:1px solid rgba(126,234,173,0.38);border-radius:50px;color:#7eeaad;font-size:13px;font-weight:700;text-decoration:none;letter-spacing:0.06em;">
          Giriş Yap →
        </a>
      </div>
    </div>
  </div>
</body>
</html>`
}
