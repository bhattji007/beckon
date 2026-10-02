// Forces HTTPS and adds HSTS, then serves the static assets (which still honour _redirects and _headers).
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }
    const res = await env.ASSETS.fetch(request);
    const out = new Response(res.body, res);
    out.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    return out;
  },
};
