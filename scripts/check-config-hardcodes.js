#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { CONFIG_DEFINITIONS } = require('../config/config-definitions');

const ROOT = path.join(__dirname, '..');
const SCAN_DIRS = ['services', 'apps/mobile/lib', 'apps/admin-web/app', 'apps/agent-portal/app'];
const EXTENSIONS = new Set(['.js', '.ts', '.tsx', '.dart']);
const allowlist = require('../config/hardcode-allowlist.json');
const patterns = allowlist.banned_patterns.map(pattern => new RegExp(pattern));

function isAllowed(file, line) {
  const relative = path.relative(ROOT, file).replaceAll(path.sep, '/');
  return allowlist.allow.some(entry => {
    const allowedPath = typeof entry === 'string' ? entry : entry.path;
    const pathMatches = relative === allowedPath || relative.startsWith(allowedPath);
    if (!pathMatches) return false;
    return !entry.pattern || new RegExp(entry.pattern).test(line);
  });
}

function* walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (['node_modules', '.next', 'build', '.dart_tool'].includes(entry.name)) continue;
      yield* walk(file);
    } else if (EXTENSIONS.has(path.extname(entry.name))) {
      yield file;
    }
  }
}

const violations = [];
for (const dir of SCAN_DIRS) {
  for (const file of walk(path.join(ROOT, dir))) {
    const relative = path.relative(ROOT, file).replaceAll(path.sep, '/');
    if (/\.test\.[jt]sx?$|test-[^/]*\.[jt]s$/.test(relative)) continue;
    const text = fs.readFileSync(file, 'utf8');
    text.split(/\r?\n/).forEach((line, index) => {
      for (const pattern of patterns) {
        if (pattern.test(line) && !isAllowed(file, line)) {
          violations.push(`${path.relative(ROOT, file)}:${index + 1}: ${line.trim()}`);
          break;
        }
      }
    });
  }
}

const catalog = Object.values(CONFIG_DEFINITIONS).map(category => ({
  key: category.key,
  owner: category.owner,
  classification: category.classification,
  applyMode: category.applyMode,
  fields: Object.keys(category.fields),
}));
const nonAdminInventory = require('../config/non-admin-config-inventory.json');
fs.writeFileSync(
  path.join(ROOT, 'config/config-inventory.json'),
  `${JSON.stringify({
    generated_at: new Date().toISOString(),
    categories: catalog,
    non_admin_config: nonAdminInventory,
  }, null, 2)}\n`,
);

if (violations.length) {
  console.error('Runtime config hardcode violations:');
  violations.forEach(violation => console.error(`- ${violation}`));
  process.exit(1);
}
console.log(`Config inventory generated: ${catalog.length} categories`);
