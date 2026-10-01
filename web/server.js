/* Static file server for the 75 web app. Replit sets PORT; default 3000 locally. */
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

http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  const rel = urlPath === "/" ? "index.html" : urlPath.replace(/^\/+/, "");
  const filePath = path.join(ROOT, rel);

  // Never serve outside the web directory.
  if (!filePath.startsWith(ROOT + path.sep) && filePath !== path.join(ROOT, "index.html")) {
    res.writeHead(403).end("Forbidden");
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Single-page app: unknown paths fall back to the shell.
      fs.readFile(path.join(ROOT, "index.html"), (e2, shell) => {
        if (e2) { res.writeHead(404).end("Not found"); return; }
        res.writeHead(200, { "Content-Type": TYPES[".html"] }).end(shell);
      });
      return;
    }
    const type = TYPES[path.extname(filePath).toLowerCase()] || "application/octet-stream";
    res.writeHead(200, {
      "Content-Type": type,
      "Cache-Control": rel === "index.html" ? "no-cache" : "public, max-age=3600"
    }).end(data);
  });
}).listen(PORT, () => {
  console.log(`75 listening on http://localhost:${PORT}`);
});
