'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');

const port = Number(process.argv[2]);
const root = fs.realpathSync(process.argv[3]);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Port must be an integer from 1024 to 65535.');

const server = http.createServer((request, response) => {
  const requestPath = new URL(request.url, `http://${request.headers.host}`).pathname;
  if (requestPath !== '/' && requestPath !== '/index.html') {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }
  const file = path.join(root, 'index.html');
  response.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  fs.createReadStream(file).pipe(response);
});

server.listen(port, '127.0.0.1', () => process.stdout.write(`READY ${port}\n`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
