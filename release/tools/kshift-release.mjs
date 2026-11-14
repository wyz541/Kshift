#!/usr/bin/env node

import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const DEFAULT_POLICY = join(ROOT, 'release/policy.json')
const VERSION_RE = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-preview\.([1-9][0-9]*))?$/
const STABLE_TAG_RE = /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/
const PREVIEW_TAG_RE = /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-preview\.([1-9][0-9]*)$/
const COMMIT_RE = /^[0-9a-f]{40}$/
const SHA256_RE = /^[0-9a-f]{64}$/
const SAFE_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
const SAFE_KEY_RE = /^[a-z][a-z0-9_-]*$/
const SECRET_KEY_RE = /(^|_)(token|password|secret|private_key|credential|authorization)($|_)/i
const SECRET_VALUE_RE = /(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]+PRIVATE KEY-----)/
const PLATFORMS = ['server', 'macos', 'ios', 'source']
const CHANNELS = ['preview', 'stable', 'hotfix']
const ASSET_ROLES = ['application', 'server-bundle', 'source', 'manifest', 'checksums', 'sbom', 'evidence', 'notes']
const ASSET_SIGNING = ['signed', 'notarized', 'testflight', 'unsigned', 'not-applicable']
const TOP_SIGNING = ['signed', 'testflight', 'ad-hoc', 'unsigned']
const NOTARIZATION = ['passed', 'failed', 'not-requested', 'not-applicable']
const GATE_STATUS = ['passed', 'failed', 'skipped']

function fail(message) {
  throw new Error(message)
}

function parseArgs(argv) {
  const [command, ...tokens] = argv
  const values = {}
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index]
    if (!token.startsWith('--')) fail(`unexpected argument: ${token}`)
    const equals = token.indexOf('=')
    if (equals > 2) {
      values[token.slice(2, equals)] = token.slice(equals + 1)
      continue
    }
    const key = token.slice(2)
    const value = tokens[index + 1]
    if (value == null || value.startsWith('--')) fail(`--${key} needs a value`)
    values[key] = value
    index += 1
  }
  return { command, values }
}

function required(values, key) {
  const value = values[key]
  if (!value) fail(`missing --${key}`)
  return value
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch (error) {
    fail(`cannot read JSON ${path}: ${error.message}`)
  }
}

function writeJson(path, value, mode = 0o644) {
  mkdirSync(dirname(resolve(path)), { recursive: true })
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode })
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value)
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function isoDate(value) {
  return nonEmptyString(value) && !Number.isNaN(Date.parse(value))
}

function validateSafeName(name, label) {
  if (!nonEmptyString(name) || !SAFE_NAME_RE.test(name) || basename(name) !== name) {
    fail(`${label} must match a safe release filename`)
  }
}

function scanMetadata(value, label = 'metadata') {
  if (typeof value === 'string') {
    if (value.startsWith('/') || value.includes('/Users/') || value.includes('/home/')) {
      fail(`${label} contains an absolute local path`)
    }
    if (SECRET_VALUE_RE.test(value)) fail(`${label} contains secret-like material`)
    return
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanMetadata(item, `${label}[${index}]`))
    return
  }
  if (!isObject(value)) return
  for (const [key, item] of Object.entries(value)) {
    if (!SAFE_KEY_RE.test(key)) fail(`${label} has an unsafe key: ${key}`)
    if (SECRET_KEY_RE.test(key)) fail(`${label} has a secret-like key: ${key}`)
    scanMetadata(item, `${label}.${key}`)
  }
}

function validateVersion(value) {
  if (!VERSION_RE.test(value ?? '')) fail('version must be SemVer core with an optional preview suffix')
}

function validateSourceCommit(value) {
  if (!COMMIT_RE.test(value ?? '')) fail('source_commit must be 40 lowercase hex characters')
}

function validateCandidate(candidate) {
  if (candidate.schema_version !== '1') fail('candidate.schema_version must be 1')
  if (candidate.product !== 'Kshift') fail('candidate.product must be Kshift')
  validateVersion(candidate.version)
  if (!CHANNELS.includes(candidate.channel)) fail('candidate.channel is invalid')
  validateSourceCommit(candidate.source_commit)
  if (!isObject(candidate.minimum_os) || candidate.minimum_os.macos !== '26.0' || candidate.minimum_os.ios !== '26.0') {
    fail('candidate.minimum_os must declare macOS and iOS 26.0')
  }
  if (!isObject(candidate.database) || candidate.database.engine !== 'postgresql' || candidate.database.major !== 18) {
    fail('candidate.database must declare PostgreSQL 18')
  }
  if (!nonEmptyString(candidate.database.exact_version)) fail('candidate.database.exact_version is required')
  if (!nonEmptyString(candidate.database.schema_version)) fail('candidate.database.schema_version is required')
  if (!SHA256_RE.test(candidate.database.migration_digest ?? '')) {
    fail('candidate.database.migration_digest must be a SHA-256')
  }
  if (!isObject(candidate.provenance)) fail('candidate.provenance is required')
  validateProvenance(candidate.provenance, 'candidate.provenance')
  if (!isObject(candidate.rollback) || !['new-patch-release', 'restore-backup', 'manual'].includes(candidate.rollback.strategy)) {
    fail('candidate.rollback is invalid')
  }
  if (!nonEmptyString(candidate.rollback.notes)) fail('candidate.rollback.notes is required')
  if (!Array.isArray(candidate.limitations)) fail('candidate.limitations must be an array')
  if (candidate.required_platforms != null) {
    if (!Array.isArray(candidate.required_platforms)) fail('candidate.required_platforms must be an array')
    if (new Set(candidate.required_platforms).size !== candidate.required_platforms.length) {
      fail('candidate.required_platforms must not contain duplicates')
    }
    for (const platform of candidate.required_platforms) {
      if (!PLATFORMS.includes(platform)) fail(`candidate.required_platforms has an unknown platform: ${platform}`)
    }
  }
  const tagPattern = candidate.channel === 'preview' ? PREVIEW_TAG_RE : STABLE_TAG_RE
  if (!tagPattern.test(candidate.tag ?? '')) fail('candidate.tag does not match channel and version')
  if (candidate.channel === 'preview' && !candidate.tag.startsWith(`v${candidate.version}-preview.`)) {
    fail('preview tag does not match candidate version')
  }
  if (candidate.channel !== 'preview' && candidate.tag !== `v${candidate.version}`) {
    fail('stable or hotfix tag must equal v<version>')
  }
}

function validateProvenance(provenance, label) {
  if (!isObject(provenance)) fail(`${label} must be an object`)
  for (const key of ['workflow', 'run_id', 'artifact_id']) {
    if (!nonEmptyString(provenance[key])) fail(`${label}.${key} is required`)
  }
  if (!Number.isInteger(Number(provenance.run_attempt)) || Number(provenance.run_attempt) < 1) {
    fail(`${label}.run_attempt must be a positive integer`)
  }
}

function validateSigning(signing, label) {
  if (!isObject(signing)) fail(`${label} must be an object`)
  if (!TOP_SIGNING.includes(signing.status)) fail(`${label}.status is invalid`)
  if (signing.identity != null && !nonEmptyString(signing.identity)) fail(`${label}.identity is invalid`)
  if (!NOTARIZATION.includes(signing.notarization)) fail(`${label}.notarization is invalid`)
}

function validateAsset(asset, label, { requireSize = true } = {}) {
  if (!isObject(asset)) fail(`${label} must be an object`)
  validateSafeName(asset.name, `${label}.name`)
  if (!PLATFORMS.includes(asset.platform)) fail(`${label}.platform is invalid`)
  if (!nonEmptyString(asset.architecture)) fail(`${label}.architecture is required`)
  if (!ASSET_ROLES.includes(asset.role)) fail(`${label}.role is invalid`)
  if (requireSize && (!Number.isInteger(asset.size_bytes) || asset.size_bytes < 1)) {
    fail(`${label}.size_bytes must be a positive integer`)
  }
  if (!SHA256_RE.test(asset.sha256 ?? '')) fail(`${label}.sha256 is invalid`)
  if (!ASSET_SIGNING.includes(asset.signing_status)) fail(`${label}.signing_status is invalid`)
}

function validateFragment(fragment, label) {
  if (!isObject(fragment)) fail(`${label} must be an object`)
  if (fragment.schema_version !== '1' || fragment.product !== 'Kshift') fail(`${label} has an invalid contract identity`)
  validateVersion(fragment.version)
  if (!CHANNELS.includes(fragment.channel)) fail(`${label}.channel is invalid`)
  validateSourceCommit(fragment.source_commit)
  if (!PLATFORMS.includes(fragment.platform)) fail(`${label}.platform is invalid`)
  if (!nonEmptyString(fragment.architecture)) fail(`${label}.architecture is required`)
  if (!isoDate(fragment.generated_at)) fail(`${label}.generated_at must be ISO 8601`)
  validateSigning(fragment.signing, `${label}.signing`)
  validateProvenance(fragment.provenance, `${label}.provenance`)
  if (!Array.isArray(fragment.assets) || fragment.assets.length < 1) fail(`${label}.assets must not be empty`)
  if (!Array.isArray(fragment.gates) || fragment.gates.length < 1) fail(`${label}.gates must not be empty`)
  if (!Array.isArray(fragment.limitations)) fail(`${label}.limitations must be an array`)
  const names = new Set()
  for (const [index, asset] of fragment.assets.entries()) {
    validateAsset(asset, `${label}.assets[${index}]`)
    if (asset.platform !== fragment.platform || asset.architecture !== fragment.architecture) {
      fail(`${label} asset platform or architecture does not match fragment`)
    }
    if (names.has(asset.name)) fail(`${label} has a duplicate asset: ${asset.name}`)
    names.add(asset.name)
  }
  for (const [index, gate] of fragment.gates.entries()) {
    if (!isObject(gate) || !nonEmptyString(gate.name) || !GATE_STATUS.includes(gate.status) || !nonEmptyString(gate.evidence)) {
      fail(`${label}.gates[${index}] is invalid`)
    }
  }
}

function loadPolicy(path) {
  const policy = readJson(path)
  if (policy.schema_version !== '1') fail('policy.schema_version must be 1')
  if (!['pending', 'approved', 'rejected'].includes(policy.decision_status)) {
    fail('policy.decision_status must be pending, approved or rejected')
  }
  if (!Array.isArray(policy.stable_required_platforms)) fail('policy.stable_required_platforms is invalid')
  if (!isObject(policy.stable_required_roles)) fail('policy.stable_required_roles is invalid')
  if (!isObject(policy.stable_required_gates)) fail('policy.stable_required_gates is invalid')
  if (!isObject(policy.stable_signing)) fail('policy.stable_signing is invalid')
  return policy
}

function normalizeGateStatus(status) {
  return status === 'not-run' ? 'skipped' : status
}

function buildFragment(values) {
  const spec = readJson(resolve(required(values, 'spec')))
  const assetsDir = resolve(required(values, 'assets-dir'))
  const outputPath = resolve(required(values, 'output'))
  if (spec.schema_version !== '1' || spec.product !== 'Kshift') fail('fragment spec must use schema version 1')
  validateVersion(spec.version)
  if (!CHANNELS.includes(spec.channel)) fail('fragment channel is invalid')
  validateSourceCommit(spec.source_commit)
  if (!PLATFORMS.includes(spec.platform)) fail('fragment platform is invalid')
  if (!nonEmptyString(spec.architecture)) fail('fragment architecture is required')
  validateSigning(spec.signing, 'fragment.signing')
  validateProvenance(spec.provenance, 'fragment.provenance')
  if (!Array.isArray(spec.assets) || spec.assets.length < 1) fail('fragment assets must not be empty')
  if (!Array.isArray(spec.gates) || spec.gates.length < 1) fail('fragment gates must not be empty')
  if (!Array.isArray(spec.limitations)) fail('fragment limitations must be an array')
  const names = new Set()
  const assets = spec.assets.map((asset, index) => {
    if (!isObject(asset)) fail(`fragment.assets[${index}] must be an object`)
    const normalized = {
      name: asset.name,
      platform: asset.platform ?? spec.platform,
      architecture: asset.architecture ?? spec.architecture,
      role: asset.role,
      signing_status: asset.signing_status ?? spec.signing.status,
      size_bytes: 0,
      sha256: '',
    }
    validateSafeName(normalized.name, `fragment.assets[${index}].name`)
    if (names.has(normalized.name)) fail(`duplicate fragment asset: ${normalized.name}`)
    names.add(normalized.name)
    if (normalized.platform !== spec.platform || normalized.architecture !== spec.architecture) {
      fail(`fragment.assets[${index}] platform or architecture does not match fragment`)
    }
    if (!ASSET_ROLES.includes(normalized.role)) fail(`fragment.assets[${index}].role is invalid`)
    if (!ASSET_SIGNING.includes(normalized.signing_status)) fail(`fragment.assets[${index}].signing_status is invalid`)
    const assetPath = join(assetsDir, normalized.name)
    if (!existsSync(assetPath) || !statSync(assetPath).isFile()) fail(`asset file is missing: ${normalized.name}`)
    normalized.size_bytes = statSync(assetPath).size
    normalized.sha256 = sha256(assetPath)
    return normalized
  })
  const gates = spec.gates.map((gate, index) => {
    const status = normalizeGateStatus(gate?.status)
    if (!isObject(gate) || !nonEmptyString(gate.name) || !GATE_STATUS.includes(status) || !nonEmptyString(gate.evidence)) {
      fail(`fragment.gates[${index}] is invalid`)
    }
    return { name: gate.name, status, evidence: gate.evidence }
  })
  const fragment = {
    schema_version: '1',
    product: 'Kshift',
    version: spec.version,
    channel: spec.channel,
    source_commit: spec.source_commit,
    platform: spec.platform,
    architecture: spec.architecture,
    generated_at: spec.generated_at ?? new Date().toISOString(),
    assets,
    signing: spec.signing,
    provenance: {
      workflow: spec.provenance.workflow,
      run_id: spec.provenance.run_id,
      run_attempt: Number(spec.provenance.run_attempt),
      artifact_id: spec.provenance.artifact_id,
    },
    gates,
    limitations: spec.limitations,
  }
  validateFragment(fragment, 'fragment')
  scanMetadata(fragment, 'fragment')
  writeJson(outputPath, fragment)
  process.stdout.write(`${JSON.stringify({ status: 'passed', output: outputPath, platform: fragment.platform, assets: assets.length })}\n`)
}

function walkFiles(root, files = []) {
  for (const name of readdirSync(root).sort()) {
    const path = join(root, name)
    const stat = statSync(path)
    if (stat.isDirectory()) walkFiles(path, files)
    else if (stat.isFile()) files.push(path)
  }
  return files
}

function collectArtifacts(values) {
  const artifactsDir = resolve(required(values, 'artifacts-dir'))
  const outputDir = resolve(required(values, 'output-dir'))
  mkdirSync(outputDir, { recursive: true })
  const files = walkFiles(artifactsDir)
  const fragments = files.filter((path) => path.endsWith('.fragment.json'))
  if (fragments.length === 0) fail('no fragment files found in downloaded artifacts')
  const byName = new Map()
  for (const path of files) {
    const name = basename(path)
    const existing = byName.get(name) ?? []
    existing.push(path)
    byName.set(name, existing)
  }
  const copied = new Set()
  for (const fragmentPath of fragments) {
    const fragmentName = basename(fragmentPath)
    if (copied.has(fragmentName)) fail(`duplicate fragment filename: ${fragmentName}`)
    const fragment = readJson(fragmentPath)
    validateFragment(fragment, fragmentName)
    for (const asset of fragment.assets) {
      if (copied.has(asset.name)) fail(`duplicate release asset in artifacts: ${asset.name}`)
      const matches = byName.get(asset.name) ?? []
      if (matches.length !== 1) fail(`asset must appear exactly once in downloaded artifacts: ${asset.name}`)
      writeFileSync(join(outputDir, asset.name), readFileSync(matches[0]))
      copied.add(asset.name)
    }
    writeFileSync(join(outputDir, fragmentName), readFileSync(fragmentPath))
    copied.add(fragmentName)
  }
  process.stdout.write(`${JSON.stringify({ status: 'passed', fragments: fragments.length, files: copied.size, output: outputDir })}\n`)
}

function loadFragments(directory) {
  const fragments = []
  for (const name of readdirSync(directory).sort()) {
    if (!name.endsWith('.fragment.json')) continue
    const path = join(directory, name)
    const fragment = readJson(path)
    validateFragment(fragment, name)
    fragments.push({ path, fragment })
  }
  return fragments
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => nonEmptyString(value)))]
}

function overallSigning(fragments) {
  const applicationFragments = fragments.filter(({ fragment }) =>
    fragment.platform === 'macos' || fragment.platform === 'ios'
  )
  const statuses = applicationFragments.map(({ fragment }) => fragment.signing.status)
  let status = 'signed'
  if (statuses.length === 0 || statuses.includes('unsigned')) status = 'unsigned'
  else if (statuses.includes('ad-hoc')) status = 'ad-hoc'
  else if (statuses.includes('testflight')) status = 'testflight'
  const identities = uniqueStrings(applicationFragments.map(({ fragment }) => fragment.signing.identity))
  const notarizations = applicationFragments.map(({ fragment }) => fragment.signing.notarization)
  let notarization = 'not-applicable'
  if (notarizations.includes('failed')) notarization = 'failed'
  else if (notarizations.includes('not-requested')) notarization = 'not-requested'
  else if (notarizations.includes('passed')) notarization = 'passed'
  return { status, identity: identities.length ? identities.join(',') : null, notarization }
}

function metadataAsset(path, role) {
  if (!existsSync(path) || !statSync(path).isFile()) fail(`metadata asset is missing: ${path}`)
  return {
    name: basename(path),
    platform: 'source',
    architecture: 'all',
    role,
    size_bytes: statSync(path).size,
    sha256: sha256(path),
    signing_status: 'not-applicable',
  }
}

function mergeFragments(values) {
  const candidate = readJson(resolve(required(values, 'candidate')))
  const fragmentsDir = resolve(required(values, 'fragments-dir'))
  const outputPath = resolve(required(values, 'output'))
  const sbomPath = resolve(required(values, 'sbom'))
  const notesPath = values.notes ? resolve(values.notes) : null
  const policy = loadPolicy(values.policy ? resolve(values.policy) : DEFAULT_POLICY)
  const mode = values.mode ?? ((candidate.channel === 'stable' || candidate.channel === 'hotfix') ? 'stable' : 'draft')
  if (!['draft', 'stable'].includes(mode)) fail('--mode must be draft or stable')
  validateCandidate(candidate)
  const loaded = loadFragments(fragmentsDir)
  if (loaded.length === 0) fail('no fragment files found')

  const fragmentKeys = new Set()
  const names = new Set()
  const assets = []
  const gates = []
  const limitations = [...candidate.limitations]

  for (const { fragment } of loaded) {
    const key = `${fragment.platform}:${fragment.architecture}`
    if (fragmentKeys.has(key)) fail(`duplicate fragment platform and architecture: ${key}`)
    fragmentKeys.add(key)
    if (fragment.product !== candidate.product) fail(`fragment product mismatch: ${key}`)
    if (fragment.version !== candidate.version) fail(`fragment version mismatch: ${key}`)
    if (fragment.channel !== candidate.channel) fail(`fragment channel mismatch: ${key}`)
    if (fragment.source_commit !== candidate.source_commit) fail(`fragment source commit mismatch: ${key}`)
    for (const asset of fragment.assets) {
      if (names.has(asset.name)) fail(`duplicate release asset name: ${asset.name}`)
      names.add(asset.name)
      assets.push(asset)
    }
    for (const gate of fragment.gates) {
      gates.push({
        name: `${fragment.platform}:${gate.name}`,
        status: gate.status,
        evidence: gate.evidence,
      })
    }
    limitations.push(...fragment.limitations)
  }

  for (const asset of [metadataAsset(sbomPath, 'sbom'), ...(notesPath ? [metadataAsset(notesPath, 'notes')] : [])]) {
    if (names.has(asset.name)) fail(`duplicate metadata asset name: ${asset.name}`)
    names.add(asset.name)
    assets.push(asset)
  }

  const presentPlatforms = new Set(loaded.map(({ fragment }) => fragment.platform))
  const requiredPlatforms = mode === 'stable'
    ? policy.stable_required_platforms
    : (candidate.required_platforms ?? [...presentPlatforms])
  if (!Array.isArray(requiredPlatforms)) fail('required platform policy is invalid')
  const missingAll = requiredPlatforms
    .filter((platform) => !presentPlatforms.has(platform))
    .map((platform) => ({ platform, reason: 'required fragment is missing' }))
  const missingPlatforms = missingAll.filter((item) => item.platform !== 'source')

  const signing = overallSigning(loaded)
  const manifest = {
    schema_version: '1',
    product: 'Kshift',
    version: candidate.version,
    channel: candidate.channel,
    tag: candidate.tag,
    source_commit: candidate.source_commit,
    generated_at: new Date().toISOString(),
    minimum_os: candidate.minimum_os,
    database: candidate.database,
    assets,
    signing,
    sbom: {
      format: values['sbom-format'] ?? 'spdx-json',
      file: basename(sbomPath),
      sha256: sha256(sbomPath),
    },
    provenance: {
      workflow: candidate.provenance.workflow,
      run_id: candidate.provenance.run_id,
      run_attempt: Number(candidate.provenance.run_attempt),
      artifact_id: candidate.provenance.artifact_id,
    },
    gates,
    limitations: uniqueStrings(limitations),
    rollback: candidate.rollback,
    release_status: 'draft',
    missing_platforms: missingPlatforms,
    promotion: null,
  }

  if (mode === 'stable') {
    validateStableManifest(manifest, policy)
  } else {
    const failedGates = gates.filter((gate) => gate.status === 'failed')
    if (failedGates.length > 0) fail(`draft fragment gates failed: ${failedGates.map((gate) => gate.name).join(', ')}`)
  }
  scanMetadata(manifest, 'manifest')
  writeJson(outputPath, manifest)
  process.stdout.write(`${JSON.stringify({ status: 'passed', output: outputPath, mode, assets: assets.length, missing: missingAll.length })}\n`)
}

function gateSet(gates) {
  return new Set(gates.filter((gate) => gate.status === 'passed').map((gate) => gate.name))
}

function validateStableManifest(manifest, policy) {
  if (policy.decision_status !== 'approved') fail('stable signing and distribution policy is not approved')
  if (manifest.missing_platforms.length > 0) {
    fail(`stable release is missing platforms: ${manifest.missing_platforms.map((item) => item.platform).join(', ')}`)
  }
  const passed = gateSet(manifest.gates)
  for (const [platform, requiredGates] of Object.entries(policy.stable_required_gates)) {
    for (const gateName of requiredGates) {
      if (!passed.has(`${platform}:${gateName}`)) fail(`required stable gate is missing or failed: ${platform}:${gateName}`)
    }
  }
  for (const [platform, requiredRoles] of Object.entries(policy.stable_required_roles)) {
    const platformAssets = manifest.assets.filter((asset) => asset.platform === platform)
    if (!platformAssets.some((asset) => requiredRoles.includes(asset.role))) {
      fail(`stable release requires a role for ${platform}: ${requiredRoles.join(', ')}`)
    }
    const allowed = policy.stable_signing[platform]
    if (!Array.isArray(allowed)) fail(`stable signing policy is missing for ${platform}`)
    for (const asset of platformAssets) {
      if (!allowed.includes(asset.signing_status)) {
        fail(`stable signing status is not allowed for ${platform}: ${asset.signing_status}`)
      }
    }
  }
  if (!policy.stable_signing_global.includes(manifest.signing.status)) {
    fail(`stable global signing status is not allowed: ${manifest.signing.status}`)
  }
}

function validateManifestContract(manifest) {
  if (!isObject(manifest) || manifest.schema_version !== '1' || manifest.product !== 'Kshift') {
    fail('invalid manifest contract')
  }
  validateVersion(manifest.version)
  if (!CHANNELS.includes(manifest.channel)) fail('manifest.channel is invalid')
  if (!nonEmptyString(manifest.tag)) fail('manifest.tag is required')
  validateSourceCommit(manifest.source_commit)
  if (!isoDate(manifest.generated_at)) fail('manifest.generated_at must be ISO 8601')
  if (!isObject(manifest.minimum_os) || manifest.minimum_os.macos !== '26.0' || manifest.minimum_os.ios !== '26.0') {
    fail('manifest.minimum_os is invalid')
  }
  if (!isObject(manifest.database) || manifest.database.engine !== 'postgresql' || manifest.database.major !== 18) {
    fail('manifest.database is invalid')
  }
  if (!nonEmptyString(manifest.database.exact_version) || !nonEmptyString(manifest.database.schema_version)) {
    fail('manifest.database exact_version and schema_version are required')
  }
  if (!SHA256_RE.test(manifest.database.migration_digest ?? '')) fail('manifest.database.migration_digest is invalid')
  if (!Array.isArray(manifest.assets) || manifest.assets.length < 1) fail('manifest.assets must not be empty')
  const names = new Set()
  for (const [index, asset] of manifest.assets.entries()) {
    validateAsset(asset, `manifest.assets[${index}]`)
    if (names.has(asset.name)) fail(`duplicate manifest asset: ${asset.name}`)
    names.add(asset.name)
  }
  validateSigning(manifest.signing, 'manifest.signing')
  if (!isObject(manifest.sbom) || !['spdx-json', 'cyclonedx-json'].includes(manifest.sbom.format)) {
    fail('manifest.sbom is invalid')
  }
  validateSafeName(manifest.sbom.file, 'manifest.sbom.file')
  if (!SHA256_RE.test(manifest.sbom.sha256 ?? '')) fail('manifest.sbom digest is invalid')
  validateProvenance(manifest.provenance, 'manifest.provenance')
  if (!Array.isArray(manifest.gates) || manifest.gates.length < 1) fail('manifest.gates must not be empty')
  for (const [index, gate] of manifest.gates.entries()) {
    if (!isObject(gate) || !nonEmptyString(gate.name) || !GATE_STATUS.includes(gate.status) || !nonEmptyString(gate.evidence)) {
      fail(`manifest.gates[${index}] is invalid`)
    }
  }
  if (!Array.isArray(manifest.limitations)) fail('manifest.limitations must be an array')
  if (!isObject(manifest.rollback) || !['new-patch-release', 'restore-backup', 'manual'].includes(manifest.rollback.strategy)) {
    fail('manifest.rollback is invalid')
  }
  if (!nonEmptyString(manifest.rollback.notes)) fail('manifest.rollback.notes is required')
  if (!['draft', 'promoted', 'failed'].includes(manifest.release_status)) fail('manifest.release_status is invalid')
  if (manifest.missing_platforms != null) {
    if (!Array.isArray(manifest.missing_platforms)) fail('manifest.missing_platforms must be an array')
    for (const missing of manifest.missing_platforms) {
      if (!['server', 'macos', 'ios'].includes(missing.platform) || !nonEmptyString(missing.reason)) {
        fail('manifest.missing_platforms has an invalid entry')
      }
    }
  }
  if (manifest.promotion != null) {
    if (!isObject(manifest.promotion) || !nonEmptyString(manifest.promotion.approved_by) || !isoDate(manifest.promotion.approved_at) || !nonEmptyString(manifest.promotion.run_id)) {
      fail('manifest.promotion is invalid')
    }
  }
  scanMetadata(manifest, 'manifest')
}

function validateCandidateFile(values) {
  const candidate = readJson(resolve(required(values, 'candidate')))
  validateCandidate(candidate)
  process.stdout.write(`${JSON.stringify({ status: 'passed', channel: candidate.channel, version: candidate.version })}\n`)
}

function validateManifest(values) {
  const manifest = readJson(resolve(required(values, 'manifest')))
  const mode = values.mode ?? 'draft'
  const policy = loadPolicy(values.policy ? resolve(values.policy) : DEFAULT_POLICY)
  validateManifestContract(manifest)
  if (mode === 'stable') {
    validateStableManifest(manifest, policy)
  }
  process.stdout.write(`${JSON.stringify({ status: 'passed', mode, assets: manifest.assets.length, platforms: [...new Set(manifest.assets.map((asset) => asset.platform))].sort() })}\n`)
}

function checksums(values) {
  const directory = resolve(required(values, 'dir'))
  const output = resolve(required(values, 'output'))
  const outputName = basename(output)
  const names = readdirSync(directory)
    .filter((name) => name !== outputName)
    .filter((name) => statSync(join(directory, name)).isFile())
    .sort()
  if (names.length === 0) fail('checksum directory has no files')
  const lines = names.map((name) => `${sha256(join(directory, name))}  ${name}`)
  mkdirSync(dirname(output), { recursive: true })
  writeFileSync(output, `${lines.join('\n')}\n`, { encoding: 'utf8', mode: 0o644 })
  process.stdout.write(`${JSON.stringify({ status: 'passed', output, files: names.length })}\n`)
}

function verifyAssets(values) {
  const manifest = readJson(resolve(required(values, 'manifest')))
  validateManifestContract(manifest)
  const directory = resolve(required(values, 'assets-dir'))
  const failures = []
  for (const asset of manifest.assets) {
    const path = join(directory, asset.name)
    if (!existsSync(path) || !statSync(path).isFile()) {
      failures.push(`missing asset: ${asset.name}`)
      continue
    }
    if (statSync(path).size !== asset.size_bytes) failures.push(`size mismatch: ${asset.name}`)
    if (sha256(path) !== asset.sha256) failures.push(`sha256 mismatch: ${asset.name}`)
  }
  if (failures.length > 0) fail(failures.join('; '))
  process.stdout.write(`${JSON.stringify({ status: 'passed', assets: manifest.assets.length })}\n`)
}

function buildEvidence(values) {
  const manifestPath = resolve(required(values, 'manifest'))
  const manifest = readJson(manifestPath)
  validateManifestContract(manifest)
  const output = resolve(required(values, 'output'))
  const evidence = {
    schema_version: '1',
    kind: 'release-evidence',
    generated_at: new Date().toISOString(),
    product: manifest.product,
    version: manifest.version,
    channel: manifest.channel,
    tag: manifest.tag,
    source_commit: manifest.source_commit,
    manifest_sha256: sha256(manifestPath),
    release_url: values['release-url'] ?? null,
    workflow_run: values['run-id']
      ? { run_id: values['run-id'], run_attempt: Number(values['run-attempt'] ?? 1) }
      : null,
    assets: manifest.assets.map((asset) => ({
      name: asset.name,
      platform: asset.platform,
      architecture: asset.architecture,
      role: asset.role,
      size_bytes: asset.size_bytes,
      sha256: asset.sha256,
      signing_status: asset.signing_status,
    })),
    signing: manifest.signing,
    promotion: manifest.promotion,
    gates: manifest.gates,
    limitations: manifest.limitations,
  }
  scanMetadata(evidence, 'evidence')
  writeJson(output, evidence, 0o644)
  process.stdout.write(`${JSON.stringify({ status: 'passed', output })}\n`)
}

function main() {
  const { command, values } = parseArgs(process.argv.slice(2))
  switch (command) {
    case 'fragment':
      return buildFragment(values)
    case 'merge':
      return mergeFragments(values)
    case 'validate':
      return validateManifest(values)
    case 'validate-candidate':
      return validateCandidateFile(values)
    case 'checksums':
      return checksums(values)
    case 'verify-assets':
      return verifyAssets(values)
    case 'collect':
      return collectArtifacts(values)
    case 'evidence':
      return buildEvidence(values)
    default:
      fail(`unknown command: ${command ?? '<missing>'}`)
  }
}

try {
  main()
} catch (error) {
  process.stderr.write(`kshift-release: ${error.message}\n`)
  process.exitCode = 2
}
