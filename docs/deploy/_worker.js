// Cloudflare Pages advanced-mode worker.
// Sole job: 301-redirect the *.pages.dev alias to the canonical custom domain,
// preserving the path/query. All other hosts (brisc.run, www, preview builds)
// are served normally from static assets.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === "brisc-docs.pages.dev") {
      url.hostname = "brisc.run";
      return Response.redirect(url.toString(), 301);
    }
    return env.ASSETS.fetch(request);
  },
};
