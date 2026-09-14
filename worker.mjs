const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'},
});

const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
})[char]);
const validEmail = value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? '').trim());

async function supabaseRequest(env, path) {
  return fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {headers: {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    accept: 'application/json',
  }});
}

async function sendEmail(env, {to, subject, html}) {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json'},
    body: JSON.stringify({from: env.EMAIL_FROM || 'Recicle+ Trairi <solicitacoes@inciclo.com.br>', reply_to: env.REPLY_TO || 'recicle.trairi@gmail.com', to: [to], subject, html}),
  });
  if (!response.ok) throw new Error(`Resend respondeu ${response.status}`);
}

async function readBody(request) {
  if (!request.headers.get('content-type')?.includes('application/json')) throw new Error('invalid_content_type');
  const text = await request.text();
  if (text.length > 4000) throw new Error('payload_too_large');
  return JSON.parse(text);
}

async function notifyRequest(request, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY || !env.RESEND_API_KEY) return json({error:'service_not_configured'}, 503);
  const {protocol, email} = await readBody(request);
  if (!validEmail(email) || !/^SOL-\d{4}-[A-F0-9]{6,12}$/.test(String(protocol ?? '').toUpperCase())) return json({error:'invalid_request'}, 400);
  const filter = `collection_requests?select=protocol,requester_name,email&protocol=eq.${encodeURIComponent(String(protocol).toUpperCase())}&email=eq.${encodeURIComponent(String(email).toLowerCase())}&limit=1`;
  const lookup = await supabaseRequest(env, filter);
  if (!lookup.ok) return json({error:'lookup_failed'}, 502);
  const [saved] = await lookup.json();
  if (!saved) return json({sent:true});
  const safeProtocol = escapeHtml(saved.protocol);
  const safeName = escapeHtml(saved.requester_name);
  const site = (env.SITE_URL || new URL(request.url).origin).replace(/\/$/, '');
  await Promise.all([
    sendEmail(env, {to: env.TEAM_EMAIL || 'recicle.trairi@gmail.com', subject:`Nova solicitação de coleta - ${saved.protocol}`, html:`<h2>Nova solicitação</h2><p>Protocolo: <b>${safeProtocol}</b></p><p><a href="${site}/?modo=manager">Abrir no sistema</a></p>`}),
    sendEmail(env, {to: saved.email, subject:`Recebemos sua solicitação - ${saved.protocol}`, html:`<h2>Olá, ${safeName}!</h2><p>Seu código de acompanhamento é <b>${safeProtocol}</b>.</p><p><a href="${site}/?modo=track">Acompanhar solicitação</a></p>`}),
  ]);
  return json({sent:true});
}

async function recoverProtocol(request, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY || !env.RESEND_API_KEY) return json({error:'service_not_configured'}, 503);
  const {email} = await readBody(request);
  if (!validEmail(email)) return json({error:'invalid_email'}, 400);
  const normalized = String(email).trim().toLowerCase();
  const filter = `collection_requests?select=protocol,created_at&email=eq.${encodeURIComponent(normalized)}&order=created_at.desc&limit=10`;
  const lookup = await supabaseRequest(env, filter);
  if (!lookup.ok) return json({error:'lookup_failed'}, 502);
  const rows = await lookup.json();
  const list = rows.length ? rows.map(item => `<p><b>${escapeHtml(item.protocol)}</b> — ${new Date(item.created_at).toLocaleDateString('pt-BR')}</p>`).join('') : '<p>Nenhuma solicitação encontrada para este e-mail.</p>';
  await sendEmail(env, {to: normalized, subject:'Seus códigos de coleta', html:`<h2>Seus códigos de acompanhamento</h2>${list}`});
  return json({sent:true});
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST' && url.pathname === '/api/notify-request') {
      try { return await notifyRequest(request, env); } catch (error) { console.error('notify-request', error); return json({error:'notification_failed'}, 500); }
    }
    if (request.method === 'POST' && url.pathname === '/api/recover-protocol') {
      try { return await recoverProtocol(request, env); } catch (error) { console.error('recover-protocol', error); return json({error:'recovery_failed'}, 500); }
    }
    if (url.pathname.startsWith('/api/')) return json({error:'not_found'}, 404);
    return env.ASSETS.fetch(request);
  }
};
