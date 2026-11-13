import assert from 'node:assert/strict'
import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const REPO = resolve(import.meta.dirname, '../..')
const TOOL = join(REPO, 'release/tools/kshift-release.mjs')
const COMMIT = 'a'.repeat(40)
const DIGEST = 'b'.repeat(64)

function run(args, expected = 0) {
  const result = spawnSync(process.execPath, [TOOL, ...args], {
    cwd: REPO,
    encoding: 'utf8',
  })
  assert.equal(
    result.status,
    expected,
    `unexpected exit ${result.status}\nstdout=${result.stdout}\nstderr=${result.stderr}`,
  )
  return result
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`)
}

function tempRoot() {
  const root = join(tmpdir(), `kshift-release-test-${process.pid}-${Math.random().toString(16).slice(2)}`)
  mkdirSync(root, { recursive: true })
  return root
}

function approvedPolicy(root) {
  const path = join(root, 'policy.json')
  writeJson(path, {
    schema_version: '1',
    decision_status: 'approved',
    decision_owner: 'test',
    decision_deadline: '2026-11-20',
    stable_required_platforms: ['server', 'macos', 'ios', 'source'],
    stable_required_roles: {
      server: ['server-bundle'],
      macos: ['application'],
      ios: ['application'],
      source: ['source'],
    },
    stable_required_gates: {
      server: ['build', 'health'],
      macos: ['build', 'signature'],
      ios: ['build', 'distribution-signature'],
      source: ['source-archive'],
    },
    stable_signing: {
      server: ['not-applicable'],
      macos: ['signed', 'notarized'],
      ios: ['signed', 'testflight'],
      source: ['not-applicable'],
    },
    stable_signing_global: ['signed', 'testflight'],
  })
  return path
}

function candidate(root, channel = 'stable') {
  const path = join(root, `${channel}-candidate.json`)
  writeJson(path, {
    schema_version: '1',
    product: 'Kshift',
    version: '0.1.0',
    channel,
    source_commit: COMMIT,
    tag: channel === 'preview' ? 'v0.1.0-preview.1' : 'v0.1.0',
    minimum_os: { macos: '26.0', ios: '26.0' },
    database: {
      engine: 'postgresql',
      major: 18,
      exact_version: '18.7',
      schema_version: '0003',
      migration_digest: DIGEST,
    },
    provenance: {
      workflow: 'release-orchestrate.yml',
      run_id: '1001',
      run_attempt: 1,
      artifact_id: 'release-candidate-1001',
    },
    rollback: {
      strategy: 'new-patch-release',
      notes: 'Publish a new patch release.',
    },
    required_platforms: ['server', 'macos', 'ios', 'source'],
    limitations: ['Internal network only.'],
  })
  return path
}

function fragment(root, platform, options = {}) {
  const platformDir = join(root, `${platform}-assets`)
  mkdirSync(platformDir, { recursive: true })
  const assetName = options.assetName ?? `kshift-0.1.0-${platform}.bin`
  writeFileSync(join(platformDir, assetName), `fixture-${platform}`)
  const gates = (options.gates ?? ['build']).map((name) => ({
    name,
    status: options.gateStatus ?? 'passed',
    evidence: `${name} evidence`,
  }))
  const spec = {
    schema_version: '1',
    product: 'Kshift',
    version: '0.1.0',
    channel: options.channel ?? 'stable',
    source_commit: options.sourceCommit ?? COMMIT,
    platform,
    architecture: 'arm64',
    signing: {
      status: options.signingStatus ?? 'unsigned',
      identity: options.signingStatus === 'signed' ? 'developer-id-digest' : null,
      notarization: options.notarization ?? (options.signingStatus === 'signed' ? 'passed' : 'not-requested'),
    },
    provenance: {
      workflow: `release-platform-${platform}.yml`,
      run_id: '1002',
      run_attempt: 1,
      artifact_id: `release-fragment-${platform}`,
    },
    assets: [
      {
        name: assetName,
        platform,
        architecture: 'arm64',
        role: options.role,
        signing_status: options.assetSigningStatus ?? options.signingStatus ?? 'unsigned',
      },
    ],
    gates,
    limitations: [],
  }
  const specPath = join(root, `${platform}.spec.json`)
  writeJson(specPath, spec)
  run(['fragment', '--spec', specPath, '--assets-dir', platformDir, '--output', join(root, `${platform}.fragment.json`)])
}

function completeCandidate(root, policy) {
  const candidatePath = candidate(root, 'stable')
  const specs = {
    server: { role: 'server-bundle', signingStatus: 'unsigned', assetSigningStatus: 'not-applicable', gates: ['build', 'health'] },
    macos: { role: 'application', signingStatus: 'signed', assetSigningStatus: 'signed', gates: ['build', 'signature'] },
    ios: { role: 'application', signingStatus: 'testflight', assetSigningStatus: 'testflight', gates: ['build', 'distribution-signature'] },
    source: { role: 'source', signingStatus: 'unsigned', assetSigningStatus: 'not-applicable', gates: ['source-archive'] },
  }
  for (const [platform, options] of Object.entries(specs)) fragment(root, platform, options)
  const sbom = join(root, 'sbom.spdx.json')
  writeFileSync(sbom, '{"spdxVersion":"SPDX-2.3"}\n')
  const notes = join(root, 'release-notes.md')
  writeFileSync(notes, '# Kshift 0.1.0\n')
  const manifest = join(root, 'release-manifest.json')
  run([
    'merge',
    '--candidate', candidatePath,
    '--fragments-dir', root,
    '--sbom', sbom,
    '--notes', notes,
    '--output', manifest,
    '--mode', 'stable',
    '--policy', policy,
  ])
  return manifest
}

function flattenAssets(root, manifest) {
  const releaseAssets = join(root, 'release-assets')
  mkdirSync(releaseAssets, { recursive: true })
  for (const asset of manifest.assets) {
    const candidates = [
      ...['server', 'macos', 'ios', 'source'].map((platform) => join(root, `${platform}-assets`, asset.name)),
      join(root, asset.name),
    ]
    const source = candidates.find((path) => {
      try {
        statSync(path)
        return true
      } catch {
        return false
      }
    })
    assert.ok(source, `missing source for ${asset.name}`)
    writeFileSync(join(releaseAssets, asset.name), readFileSync(source))
  }
  return releaseAssets
}

test('builds a contract-v1 fragment with byte count and SHA-256', () => {
  const root = tempRoot()
  fragment(root, 'macos', { role: 'application', signingStatus: 'signed' })
  const output = JSON.parse(readFileSync(join(root, 'macos.fragment.json'), 'utf8'))
  assert.equal(output.schema_version, '1')
  assert.equal(output.assets[0].size_bytes, 'fixture-macos'.length)
  assert.match(output.assets[0].sha256, /^[0-9a-f]{64}$/)
  assert.equal(output.provenance.run_attempt, 1)
})

test('merges and validates a fully gated stable release with approved policy', () => {
  const root = tempRoot()
  const policy = approvedPolicy(root)
  const manifestPath = completeCandidate(root, policy)
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  assert.equal(manifest.schema_version, '1')
  assert.equal(manifest.release_status, 'draft')
  assert.equal(manifest.signing.status, 'testflight')
  run(['validate', '--manifest', manifestPath, '--mode', 'stable', '--policy', policy])
  const releaseAssets = flattenAssets(root, manifest)
  run(['verify-assets', '--manifest', manifestPath, '--assets-dir', releaseAssets])
  const tamperName = manifest.assets[0].name
  writeFileSync(join(releaseAssets, tamperName), 'tampered')
  const tampered = run(['verify-assets', '--manifest', manifestPath, '--assets-dir', releaseAssets], 2)
  assert.match(tampered.stderr, /size mismatch|sha256 mismatch/)
})

test('stable merge rejects a pending signing policy', () => {
  const root = tempRoot()
  const policy = approvedPolicy(root)
  writeJson(policy, { ...JSON.parse(readFileSync(policy, 'utf8')), decision_status: 'pending' })
  const candidatePath = candidate(root, 'stable')
  fragment(root, 'server', { role: 'server-bundle', signingStatus: 'unsigned', assetSigningStatus: 'not-applicable', gates: ['build', 'health'] })
  const sbom = join(root, 'sbom.spdx.json')
  writeFileSync(sbom, '{}')
  const result = run(['merge', '--candidate', candidatePath, '--fragments-dir', root, '--sbom', sbom, '--output', join(root, 'out.json'), '--mode', 'stable', '--policy', policy], 2)
  assert.match(result.stderr, /not approved/)
})

test('stable merge rejects mismatched source commits', () => {
  const root = tempRoot()
  const policy = approvedPolicy(root)
  const candidatePath = candidate(root, 'stable')
  fragment(root, 'server', {
    role: 'server-bundle',
    signingStatus: 'unsigned',
    assetSigningStatus: 'not-applicable',
    gates: ['build', 'health'],
    sourceCommit: 'c'.repeat(40),
  })
  const sbom = join(root, 'sbom.spdx.json')
  writeFileSync(sbom, '{}')
  const result = run(['merge', '--candidate', candidatePath, '--fragments-dir', root, '--sbom', sbom, '--output', join(root, 'out.json'), '--mode', 'stable', '--policy', policy], 2)
  assert.match(result.stderr, /source commit mismatch/)
})

test('fragment rejects path traversal in an asset name', () => {
  const root = tempRoot()
  const specPath = join(root, 'spec.json')
  writeJson(specPath, {
    schema_version: '1',
    product: 'Kshift',
    version: '0.1.0',
    channel: 'preview',
    source_commit: COMMIT,
    platform: 'macos',
    architecture: 'arm64',
    signing: { status: 'unsigned', identity: null, notarization: 'not-requested' },
    provenance: {
      workflow: 'release-platform-macos.yml',
      run_id: '1',
      run_attempt: 1,
      artifact_id: 'release-fragment-macos',
    },
    assets: [{ name: '../escape.dmg', platform: 'macos', architecture: 'arm64', role: 'application', signing_status: 'unsigned' }],
    gates: [{ name: 'build', status: 'passed', evidence: 'build log' }],
    limitations: [],
  })
  const result = run([
    'fragment',
    '--spec', specPath,
    '--assets-dir', root,
    '--output', join(root, 'fragment.json'),
  ], 2)
  assert.match(result.stderr, /safe release filename/)
})

test('draft merge records missing platforms without calling the release stable', () => {
  const root = tempRoot()
  const candidatePath = candidate(root, 'preview')
  fragment(root, 'server', {
    role: 'server-bundle',
    signingStatus: 'unsigned',
    assetSigningStatus: 'not-applicable',
    gates: ['build'],
    channel: 'preview',
  })
  const sbom = join(root, 'sbom.spdx.json')
  writeFileSync(sbom, '{}')
  const manifestPath = join(root, 'draft.json')
  run(['merge', '--candidate', candidatePath, '--fragments-dir', root, '--sbom', sbom, '--output', manifestPath, '--mode', 'draft'])
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  assert.equal(manifest.release_status, 'draft')
  assert.equal(manifest.missing_platforms.length, 2)
})

test('collects fragments and their referenced assets from downloaded artifacts', () => {
  const root = tempRoot()
  fragment(root, 'server', {
    role: 'server-bundle',
    signingStatus: 'unsigned',
    assetSigningStatus: 'not-applicable',
    gates: ['build'],
    channel: 'preview',
  })
  const output = join(root, 'collected')
  run(['collect', '--artifacts-dir', root, '--output-dir', output])
  assert.ok(readFileSync(join(output, 'server.fragment.json'), 'utf8').includes('server-bundle'))
  assert.ok(readFileSync(join(output, 'kshift-0.1.0-server.bin'), 'utf8').includes('fixture'))
})

test('generates a deterministic SPDX document from lockfiles', () => {
  const root = tempRoot()
  writeFileSync(join(root, 'Cargo.lock'), '[[package]]\nname = "kshift-server"\nversion = "0.1.0"\n')
  const output = join(root, 'sbom.spdx.json')
  const sbomResult = spawnSync(process.execPath, [
    join(REPO, 'release/tools/generate-sbom.mjs'),
    '--root', root,
    '--output', output,
    '--version', '0.1.0',
    '--source-commit', COMMIT,
  ], { encoding: 'utf8' })
  assert.equal(sbomResult.status, 0, sbomResult.stderr)
  const sbom = JSON.parse(readFileSync(output, 'utf8'))
  assert.equal(sbom.spdxVersion, 'SPDX-2.3')
  assert.equal(sbom.packages.length, 2)
  assert.equal(sbom.relationships.length, 2)
})

test('example candidate satisfies the candidate contract', () => {
  const result = run(['validate-candidate', '--candidate', 'release/examples/candidate.json'])
  assert.match(result.stdout, /"status":"passed"/)
})

test('computes a stable database migration context', () => {
  const root = tempRoot()
  const migrations = join(root, 'migrations')
  mkdirSync(migrations)
  writeFileSync(join(migrations, '0001_first.sql'), 'SELECT 1;\n')
  writeFileSync(join(migrations, '0002_second.sql'), 'SELECT 2;\n')
  const output = join(root, 'database.json')
  const result = spawnSync(process.execPath, [
    join(REPO, 'release/tools/compute-database-context.mjs'),
    '--migrations-dir', migrations,
    '--schema-version', '1',
    '--exact-version', '18.7',
    '--output', output,
  ], { encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  const context = JSON.parse(readFileSync(output, 'utf8'))
  assert.equal(context.schema_version, '1')
  assert.match(context.migration_digest, /^[0-9a-f]{64}$/)
})

test('checksums are deterministic', () => {
  const root = tempRoot()
  const assets = join(root, 'assets')
  mkdirSync(assets)
  writeFileSync(join(assets, 'a.bin'), 'a')
  writeFileSync(join(assets, 'b.bin'), 'b')
  const sums = join(root, 'SHA256SUMS')
  run(['checksums', '--dir', assets, '--output', sums])
  const lines = readFileSync(sums, 'utf8').trim().split('\n')
  assert.deepEqual(lines.map((line) => line.slice(66)), ['a.bin', 'b.bin'])
})
