// Kalori AI proxy (Cloudflare Worker). The app sends the Gemini request body here; the worker adds the
// server's Gemini key (secret GEMINI_KEY), so app users need no key of their own.
// Guards against runaway cost: per-device daily cap + global daily cap (KV namespace bound as Q).
// It stores nothing but counters that expire after 2 days; photos/text are passed through, never logged.
const ALLOWED_ORIGINS = ['capacitor://localhost', 'http://localhost', 'https://toto45678.github.io'];
const DEVICE_DAY_CAP = 120, GLOBAL_DAY_CAP = 4000;
const MODEL_OK = /^gemini-[\w.-]*flash[\w.-]*$/;
function cors(req) {
  const o = req.headers.get('Origin') || '';
  return { 'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(o) ? o : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'content-type,x-device', 'Vary': 'Origin' };
}
const json = (req, obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json', ...cors(req) } });
async function bump(env, key, cap) {
  const n = parseInt((await env.Q.get(key)) || '0', 10);
  if (n >= cap) return false;
  await env.Q.put(key, String(n + 1), { expirationTtl: 172800 });
  return true;
}
export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: cors(req) });
    const url = new URL(req.url), day = new Date().toISOString().slice(0, 10);
    if (url.pathname === '/v1/ping') return json(req, { ok: true, key: !!env.GEMINI_KEY });
    if (!env.GEMINI_KEY) return json(req, { error: { message: 'server has no GEMINI_KEY' } }, 503);
    if (url.pathname === '/v1/models' && req.method === 'GET') {
      const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=' + env.GEMINI_KEY);
      return new Response(r.body, { status: r.status, headers: { 'content-type': 'application/json', ...cors(req) } });
    }
    const m = url.pathname.match(/^\/v1\/models\/([^/:]+):generateContent$/);
    if (m && req.method === 'POST') {
      const model = m[1], dev = (req.headers.get('x-device') || '').slice(0, 64);
      if (!MODEL_OK.test(model)) return json(req, { error: { message: 'model not allowed' } }, 400);
      if (!/^[a-z0-9-]{16,64}$/i.test(dev)) return json(req, { error: { message: 'no device id' } }, 400);
      const body = await req.text();
      if (body.length > 3_000_000) return json(req, { error: { message: 'too large' } }, 413);
      if (!(await bump(env, `g:${day}`, GLOBAL_DAY_CAP))) return json(req, { error: { message: 'daily server limit' } }, 429);
      if (!(await bump(env, `d:${day}:${dev}`, DEVICE_DAY_CAP))) return json(req, { error: { message: 'daily device limit' } }, 429);
      const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_KEY}`,
        { method: 'POST', headers: { 'content-type': 'application/json' }, body });
      return new Response(r.body, { status: r.status, headers: { 'content-type': 'application/json', ...cors(req) } });
    }
    return json(req, { error: { message: 'not found' } }, 404);
  }
};
