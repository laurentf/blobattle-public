import net from 'node:net';

const [listen, target] = process.argv.slice(2);
const [targetHost, targetPort] = target.split(':');
const [listenHost, listenPort] = listen.split(':');

net
  .createServer((client) => {
    const upstream = net.connect(Number(targetPort), targetHost);
    client.pipe(upstream).pipe(client);
    const close = () => {
      client.destroy();
      upstream.destroy();
    };
    client.on('error', close);
    upstream.on('error', close);
  })
  .listen(Number(listenPort), listenHost, () => console.log(`🔀 ${listen} → ${target}`));
