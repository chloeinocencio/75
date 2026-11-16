/* Static file server for the 75 web app. Replit sets PORT; default 3000 locally.
 *
 * Hardened for a public deploy:
 * - A malformed URL ("%E0%A4%A") makes decodeURIComponent throw. Uncaught inside the
 *   request handler, that crashed the whole process — one request took the site down.
 *   It now answers 400.
 * - Only files with a known static type are served, never dotfiles, never this file.
 * - Security headers: CSP, no sniffing, no framing, no referrer, camera for this origin only.
 */
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const PORT = process.env.PORT || 3000;

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webmanifest": "application/manifest+json"
};

const NEVER_SERVE = new Set(["server.js"]);

const SECURITY_HEADERS = {
  "Content-Security-Policy": [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "media-src 'self' blob:",
    "connect-src 'self'",
    "worker-src 'self'",
    "manifest-src 'self'",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'"
  ].join("; "),
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
  "Permissions-Policy": "camera=(self), microphone=(), geolocation=(), payment=(), usb=()",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Resource-Policy": "same-origin",
  // Ignored over plain http (localhost); enforced on Replit's https domain.
  "Strict-Transport-Security": "max-age=31536000"
};

function send(res, status, body, headers = {}, method = "GET") {
  res.writeHead(status, { ...SECURITY_HEADERS, ...headers });
  res.end(method === "HEAD" ? undefined : body);
}

function serveShell(res, method) {
  fs.readFile(path.join(ROOT, "index.html"), (err, shell) => {
    if (err) return send(res, 404, "Not found", { "Content-Type": "text/plain; charset=utf-8" }, method);
    send(res, 200, shell, { "Content-Type": TYPES[".html"], "Cache-Control": "no-cache" }, method);
  });
}

const server = http.createServer((req, res) => {
  try {
    const method = req.method || "GET";
    if (method !== "GET" && method !== "HEAD") {
      return send(res, 405, "Method not allowed", { Allow: "GET, HEAD", "Content-Type": "text/plain; charset=utf-8" });
    }

    let urlPath;
    try {
      urlPath = decodeURIComponent((req.url || "/").split("?")[0].split("#")[0]);
    } catch (_) {
      return send(res, 400, "Bad request", { "Content-Type": "text/plain; charset=utf-8" }, method);
    }
    if (urlPath.includes("\0") || urlPath.length > 512) {
      return send(res, 400, "Bad request", { "Content-Type": "text/plain; charset=utf-8" }, method);
    }

    const rel = urlPath === "/" ? "index.html" : urlPath.replace(/^\/+/, "");
    const filePath = path.resolve(ROOT, rel);
    const relative = path.relative(ROOT, filePath);

    // Never serve outside the web directory, dotfiles, or the server's own source.
    const segments = relative.split(path.sep);
    if (relative.startsWith("..") || path.isAbsolute(relative) || segments.some((s) => s.startsWith("."))
        || NEVER_SERVE.has(relative)) {
      return send(res, 404, "Not found", { "Content-Type": "text/plain; charset=utf-8" }, method);
    }

    const ext = path.extname(filePath).toLowerCase();
    if (!ext) return serveShell(res, method);   // client-side route → app shell
    const type = TYPES[ext];
    if (!type) return send(res, 404, "Not found", { "Content-Type": "text/plain; charset=utf-8" }, method);

    fs.readFile(filePath, (err, data) => {
      if (err) {
        if (ext === ".html") return serveShell(res, method);
        return send(res, 404, "Not found", { "Content-Type": "text/plain; charset=utf-8" }, method);
      }
      send(res, 200, data, {
        "Content-Type": type,
        "Cache-Control": ext === ".html" || relative === "sw.js" ? "no-cache" : "public, max-age=3600"
      }, method);
    });
  } catch (err) {
    console.error("request failed:", err && err.message);
    if (!res.headersSent) send(res, 500, "Server error", { "Content-Type": "text/plain; charset=utf-8" });
    else res.end();
  }
});

server.headersTimeout = 15000;
server.requestTimeout = 30000;
server.listen(PORT, () => {
  console.log(`75 listening on http://localhost:${PORT}`);
});
