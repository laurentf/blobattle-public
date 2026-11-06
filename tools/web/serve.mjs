import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'out/web/Blobattle');
const port = Number(process.argv[3] || 5373);
const host = process.argv[4] || '127.0.0.1';
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.arcd': 'application/octet-stream',
  '.arci': 'application/octet-stream',
  '.dmanifest': 'application/octet-stream',
  '.projectc': 'application/octet-stream',
};

http
  .createServer((req, res) => {
    let p;
    try {
      p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    } catch {
      res.writeHead(400);
      res.end();
      return;
    }
    if (p.endsWith('/')) p += 'index.html';
    const f = path.join(root, p);
    if (!f.startsWith(root + path.sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    fs.stat(f, (err, st) => {
      if (err || !st.isFile()) {
        res.writeHead(404);
        res.end();
        return;
      }
      res.writeHead(200, {
        'Content-Type': types[path.extname(f)] || 'application/octet-stream',
        'Content-Length': st.size,
        'Cache-Control': 'no-store',
      });
      fs.createReadStream(f).pipe(res);
    });
  })
  .listen(port, host, () => console.log(`🌐 serving ${root} on http://${host}:${port}/`));
