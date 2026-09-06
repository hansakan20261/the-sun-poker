const { spawnSync } = require('child_process');

function run(cmd, args) {
  const result = spawnSync(cmd, args, { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr || `Command failed: ${cmd} ${args.join(' ')}`);
  }
  return result.stdout;
}

const vars = JSON.parse(run('railway', ['variable', 'list', '--service', 'Postgres', '--json']));
const proxies = JSON.parse(run('railway', ['tcp-proxy', 'list', '--service', 'Postgres', '--json']));
const proxy = proxies.proxies[0];

const password = vars.POSTGRES_PASSWORD || vars.PGPASSWORD;
const user = vars.POSTGRES_USER || 'postgres';
const db = vars.POSTGRES_DB || 'railway';
const publicUrl = `postgresql://${user}:${password}@${proxy.domain}:${proxy.proxyPort}/${db}?sslmode=no-verify`;

const env = { ...process.env, DATABASE_URL: publicUrl };

console.log('Running migrations...');
let r = spawnSync('node', ['scripts/migrate.cjs'], { env, stdio: 'inherit' });
if (r.status !== 0) process.exit(r.status);

console.log('Running backfill...');
r = spawnSync('node', ['scripts/backfill-room-snapshots.cjs'], { env, stdio: 'inherit' });
process.exit(r.status);
