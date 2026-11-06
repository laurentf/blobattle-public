import { readdirSync } from 'node:fs';
import { checker } from './lib.mjs';

const only = process.argv[2];
const names = readdirSync(new URL('./scenarios/', import.meta.url))
  .filter((name) => name.endsWith('.mjs') && (!only || name.includes(only)))
  .sort();

let failures = 0;
for (const name of names) {
  const scenario = await import(`./scenarios/${name}`);
  console.log(`── ${scenario.title}`);
  const t = checker();
  try {
    await scenario.run(t);
  } catch (error) {
    t.check(`${name} ran to its end`, false, error?.stack ?? String(error));
  }
  if (t.checks === 0) t.check(`${name} checks something`, false);
  failures += t.failures;
}
if (names.length === 0) {
  console.log(`❌ no scenario matches ${only}`);
  failures += 1;
}
process.exit(failures === 0 ? 0 : 1);
