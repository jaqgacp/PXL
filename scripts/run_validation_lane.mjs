import { readFileSync } from 'node:fs';
import { resolve, relative, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const lane = process.argv[2];
const laneArgs = process.argv.slice(3);

const remediation = {
  'fresh-schema': 'Inspect the first failing migration, correct only the owning change, then rerun this lane from the start.',
  regression: 'Rerun the reported pgTAP file with test:db:focused, fix the failing assertion or fixture, then rerun the full regression lane.',
  focused: 'Use the reported pgTAP assertion and package ownership to make a bounded correction, then rerun the same focused file.',
  canonical: 'Correct the deterministic reset/seed/test failure, rerun the complete canonical lane, then rerun the regression lane.',
  docs: 'Reconcile the authoritative documents named by the checker, then rerun the documentation lane.',
  lint: 'Correct the reported static-analysis failure without suppressing a valid diagnostic, then rerun lint.',
  build: 'Correct the secret, typecheck, or bundle failure reported by the build, then rerun the build lane.',
  diff: 'Correct whitespace errors in the reported patch, then rerun the diff lane.',
  'hosted-read-only': 'Verify the approved read-only credential and hosted schema, then rerun without applying migrations, seeds, repairs, or writes.',
  'hosted-ui': 'Correct the failing read-only route/probe or its approved environment configuration, then rerun the complete hosted UI lane.',
};

function displayCommand(command, args) {
  return [command, ...args].map((part) => (/^[A-Za-z0-9_./:=@-]+$/.test(part) ? part : JSON.stringify(part))).join(' ');
}

function runStep(laneName, label, command, args, options = {}) {
  const shownCommand = options.display ?? displayCommand(command, args);
  process.stdout.write(`\n[${laneName}] START: ${label}\n[${laneName}] COMMAND: ${shownCommand}\n`);

  const result = spawnSync(command, args, {
    cwd: root,
    env: options.env ?? process.env,
    input: options.input,
    stdio: options.input === undefined ? 'inherit' : ['pipe', 'inherit', 'inherit'],
  });

  if (result.error) {
    process.stderr.write(`[${laneName}] FAIL: ${label}\n[${laneName}] ERROR: ${result.error.message}\n`);
    process.stderr.write(`[${laneName}] REMEDIATION: ${remediation[laneName]}\n`);
    process.exit(1);
  }

  if (result.status !== 0) {
    process.stderr.write(`[${laneName}] FAIL: ${label} (exit ${result.status ?? 'unknown'})\n`);
    process.stderr.write(`[${laneName}] FAILED COMMAND: ${shownCommand}\n`);
    process.stderr.write(`[${laneName}] REMEDIATION: ${remediation[laneName]}\n`);
    process.exit(result.status ?? 1);
  }

  process.stdout.write(`[${laneName}] PASS: ${label}\n`);
}

function freshSchema() {
  runStep('fresh-schema', 'Replay every local migration without seed data', 'supabase', ['db', 'reset', '--local', '--no-seed']);
}

function regression() {
  runStep('regression', 'Run the complete pgTAP regression suite', 'supabase', ['test', 'db', '--local', 'supabase/tests']);
}

function focused(paths) {
  if (paths.length === 0) {
    process.stderr.write('[focused] FAIL: provide one or more supabase/tests/*.sql paths.\n');
    process.stderr.write('[focused] EXAMPLE: npm run test:db:focused -- supabase/tests/074_mdp14_approval_matrix_integration_test.sql\n');
    process.exit(2);
  }

  for (const path of paths) {
    const absolute = resolve(root, path);
    const projectPath = relative(root, absolute);
    if (projectPath.startsWith(`..${sep}`) || !projectPath.startsWith(`supabase${sep}tests${sep}`) || !projectPath.endsWith('.sql')) {
      process.stderr.write(`[focused] FAIL: unsupported test path ${JSON.stringify(path)}; expected supabase/tests/*.sql.\n`);
      process.exit(2);
    }
    readFileSync(absolute);
  }

  runStep('focused', `Run ${paths.length} focused pgTAP file(s)`, 'supabase', ['test', 'db', '--local', ...paths]);
}

function canonical() {
  freshSchema();

  const seedFiles = [
    'supabase/seeds/canonical_demo_reset.sql',
    'supabase/seeds/canonical_demo_seed.sql',
    'supabase/seeds/canonical_phase3_enrichment.sql',
    'supabase/seeds/canonical_demo_volume.sql',
  ];
  const seedSql = [
    'BEGIN;',
    "SET pxl.allow_demo_reset = 'on';",
    ...seedFiles.flatMap((path) => [
      `\\echo [canonical] FILE: ${path}`,
      readFileSync(resolve(root, path), 'utf8'),
    ]),
    'COMMIT;',
    '',
  ].join('\n');

  runStep(
    'canonical',
    'Load the deterministic canonical reset, base seed, enrichment, and volume layers',
    'docker',
    ['exec', '-i', 'supabase_db_PXL', 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'],
    { input: seedSql },
  );
  runStep(
    'canonical',
    'Verify canonical base, Phase 3, and volume invariants',
    'supabase',
    [
      'test',
      'db',
      '--local',
      'supabase/tests/055_canonical_demo_dataset_test.sql',
      'supabase/tests/057_phase3_canonical_implementation_test.sql',
      'supabase/tests/058_canonical_demo_volume_test.sql',
      'supabase/tests/075_table_coverage_governance_test.sql',
      'supabase/tests/077_reporting_view_security_guard_test.sql',
      'supabase/tests/078_immutability_demo_reset_bypass_guard_test.sql',
      'supabase/tests/079_number_series_engine_certification_test.sql',
    ],
  );
}

function docs() {
  runStep('docs', 'Validate AI state and documentation consistency', 'npm', ['run', 'docs:check']);
}

function lint() {
  runStep('lint', 'Run static analysis', 'npm', ['run', 'lint']);
}

function build() {
  runStep('build', 'Run frontend secret guards, typecheck, and production bundle', 'npm', ['run', 'build']);
}

function diff() {
  runStep('diff', 'Check the working-tree patch for whitespace errors', 'git', ['diff', '--check']);
}

function requireHostedAuthorization() {
  if (process.env.PXL_ALLOW_HOSTED_READ_ONLY !== '1') {
    throw new Error('PXL_ALLOW_HOSTED_READ_ONLY=1 is required for an explicitly authorized hosted read-only run.');
  }
}

function hostedReadOnly() {
  try {
    requireHostedAuthorization();
    const rawUrl = process.env.PXL_HOSTED_READ_ONLY_DATABASE_URL;
    if (!rawUrl) throw new Error('PXL_HOSTED_READ_ONLY_DATABASE_URL is required.');

    const url = new URL(rawUrl);
    if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error('The hosted database URL must use postgres:// or postgresql://.');
    if (['localhost', '127.0.0.1', '0.0.0.0', '::1'].includes(url.hostname)) throw new Error('The hosted lane refuses local database targets.');

    const expectedRef = process.env.PXL_HOSTED_PROJECT_REF ?? 'bskjkogijpbhukjkagfj';
    if (!`${url.hostname} ${url.username}`.includes(expectedRef)) {
      throw new Error(`The database target does not match approved project ref ${expectedRef}.`);
    }

    const pgOptions = [process.env.PGOPTIONS, '-c default_transaction_read_only=on'].filter(Boolean).join(' ');
    runStep(
      'hosted-read-only',
      'Run canonical coverage verification with PostgreSQL default_transaction_read_only enabled',
      'psql',
      ['--no-psqlrc', '--set=ON_ERROR_STOP=1', '--file=supabase/verification/phase3_hosted_read_only.sql'],
      {
        display: 'psql [REDACTED_HOSTED_READ_ONLY_URL] --no-psqlrc --set=ON_ERROR_STOP=1 --file=supabase/verification/phase3_hosted_read_only.sql',
        env: { ...process.env, PGDATABASE: rawUrl, PGOPTIONS: pgOptions },
      },
    );
  } catch (error) {
    process.stderr.write(`[hosted-read-only] FAIL: ${error instanceof Error ? error.message : String(error)}\n`);
    process.stderr.write(`[hosted-read-only] REMEDIATION: ${remediation['hosted-read-only']}\n`);
    process.exit(2);
  }
}

function hostedUi() {
  try {
    requireHostedAuthorization();
    const baseUrl = process.env.AUDIT_BASE_URL;
    if (!baseUrl || !process.env.AUDIT_EMAIL || !process.env.AUDIT_PASSWORD) {
      throw new Error('AUDIT_BASE_URL, AUDIT_EMAIL, and AUDIT_PASSWORD are required; implicit demo credentials are not allowed by this lane.');
    }
    const url = new URL(baseUrl);
    if (url.protocol !== 'https:' || ['localhost', '127.0.0.1', '0.0.0.0', '::1'].includes(url.hostname)) {
      throw new Error('The hosted UI lane requires an explicit non-local HTTPS AUDIT_BASE_URL.');
    }
    runStep('hosted-ui', 'Run the hosted canonical UI and report probes', 'node', ['scripts/audit_phase3_hosted_ui.mjs']);
  } catch (error) {
    process.stderr.write(`[hosted-ui] FAIL: ${error instanceof Error ? error.message : String(error)}\n`);
    process.stderr.write(`[hosted-ui] REMEDIATION: ${remediation['hosted-ui']}\n`);
    process.exit(2);
  }
}

function releaseLocal() {
  freshSchema();
  regression();
  canonical();
  docs();
  lint();
  build();
  diff();
}

switch (lane) {
  case 'fresh-schema': freshSchema(); break;
  case 'regression': regression(); break;
  case 'focused': focused(laneArgs); break;
  case 'local': freshSchema(); regression(); break;
  case 'canonical': canonical(); break;
  case 'docs': docs(); break;
  case 'lint': lint(); break;
  case 'build': build(); break;
  case 'diff': diff(); break;
  case 'hosted-read-only': hostedReadOnly(); break;
  case 'hosted-ui': hostedUi(); break;
  case 'release-local': releaseLocal(); break;
  default:
    process.stderr.write('Usage: node scripts/run_validation_lane.mjs <fresh-schema|regression|focused|local|canonical|docs|lint|build|diff|hosted-read-only|hosted-ui|release-local> [focused test paths...]\n');
    process.exit(2);
}
