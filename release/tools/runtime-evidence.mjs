#!/usr/bin/env node

import { createHash } from 'node:crypto'
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { basename, dirname, join, relative, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'

const INPUT_ALGORITHM = 'kshift-runtime-inputs-v1'
const INPUT_PATHS = [
  '.gitattributes',
  'Apps/KshiftMacOS',
  'Assets',
  'Cargo.lock',
  'Cargo.toml',
  'Package.resolved',
  'Package.swift',
  'Sources',
  'crates',
  'include',
  'migrations',
  'ops',
  'project.yml',
  'proto',
  'release/platform/build-macos.sh',
  'release/platform/build-server.sh',
  'rust-toolchain.toml',
  'rustfmt.toml',
  'schemas',
  'scripts/build-ffi.sh',
]
const COMMIT_RE = /^[0-9a-f]{40}$/
const SHA256_RE = /^[0-9a-f]{64}$/
const SECRET_VALUE_RE = /(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]+PRIVATE KEY-----)/
const GATE_STATUS = ['passed', 'failed', 'skipped']
const PLATFORMS = ['server', 'macos']

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

function writeJson(path, value) {
  mkdirSync(dirname(resolve(path)), { recursive: true })
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o644 })
}

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value)
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function sha256Bytes(bytes) {
  return createHash('sha256').update(bytes).digest('hex')
}

function sha256File(path) {
  return sha256Bytes(readFileSync(path))
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: options.encoding ?? 'utf8',
  })
  if (result.error) fail(`cannot run ${command}: ${result.error.message}`)
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr) ? result.stderr.toString('utf8') : result.stderr
    fail(`${command} failed: ${String(stderr ?? '').trim()}`)
  }
  return result
}

function gitTrackedFiles(root) {
  const result = run('git', ['ls-files', '-z', '--', ...INPUT_PATHS], { cwd: root, encoding: null })
  return result.stdout
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .sort()
}

export function sourceInputsDigest(root) {
  const files = gitTrackedFiles(root)
  if (files.length === 0) fail('runtime input inventory is empty')
  const digest = createHash('sha256')
  digest.update(`${INPUT_ALGORITHM}\0`)
  for (const file of files) {
    const absolute = join(root, file)
    digest.update(file)
    digest.update('\0')
    const stat = lstatSync(absolute, { throwIfNoEntry: false })
    if (!stat) fail(`runtime input is missing: ${file}`)
    if (stat.isSymbolicLink()) digest.update(`symlink:${readlinkSync(absolute)}`)
    else digest.update(readFileSync(absolute))
    digest.update('\0')
  }
  return { algorithm: INPUT_ALGORITHM, sha256: digest.digest('hex'), files: files.length }
}

function walkEntries(root, current = root, entries = []) {
  for (const name of readdirSync(current).sort()) {
    const absolute = join(current, name)
    const entry = relative(root, absolute).split('\\').join('/')
    const stat = lstatSync(absolute)
    if (stat.isDirectory()) walkEntries(root, absolute, entries)
    else if (stat.isSymbolicLink()) entries.push({ path: entry, type: 'symlink', target: readlinkSync(absolute) })
    else if (stat.isFile()) entries.push({ path: entry, type: 'file', absolute })
  }
  return entries
}

export function treeDigest(root, exclude = []) {
  if (!existsSync(root) || !statSync(root).isDirectory()) fail(`tree is missing: ${root}`)
  const excluded = new Set(exclude)
  const digest = createHash('sha256')
  for (const entry of walkEntries(root)) {
    if (excluded.has(entry.path) || [...excluded].some((prefix) => entry.path.startsWith(`${prefix}/`))) continue
    digest.update(entry.path)
    digest.update('\0')
    if (entry.type === 'symlink') digest.update(`symlink:${entry.target}`)
    else digest.update(readFileSync(entry.absolute))
    digest.update('\0')
  }
  return digest.digest('hex')
}

function plistValue(application, key) {
  const result = spawnSync('plutil', ['-extract', key, 'raw', '-o', '-', join(application, 'Contents/Info.plist')], {
    encoding: 'utf8',
  })
  if (result.status !== 0) fail(`Info.plist key is missing: ${key}`)
  return result.stdout.trim()
}

function codeSignature(application) {
  const result = spawnSync('codesign', ['-dv', '--verbose=4', application], { encoding: 'utf8' })
  if (result.status !== 0) fail(`codesign inspection failed for ${application}`)
  const text = `${result.stdout}\n${result.stderr}`
  const signature = text.match(/^Signature=(.+)$/m)?.[1]?.trim()
  if (signature === 'adhoc') return 'ad-hoc'
  if (signature) return 'signed'
  fail('application does not report a code signature')
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
    scanMetadata(item, `${label}.${key}`)
  }
}

function gateMap(gates) {
  if (!Array.isArray(gates) || gates.length < 1) fail('evidence.gates must not be empty')
  const result = new Map()
  for (const [index, gate] of gates.entries()) {
    if (!isObject(gate) || !nonEmptyString(gate.name) || !GATE_STATUS.includes(gate.status) || !isObject(gate.detail)) {
      fail(`evidence.gates[${index}] is invalid`)
    }
    if (result.has(gate.name)) fail(`evidence.gates contains a duplicate gate: ${gate.name}`)
    result.set(gate.name, gate)
  }
  return result
}

function requirePassedGate(gates, name) {
  const gate = gates.get(name)
  if (!gate) fail(`runtime evidence is missing required gate: ${name}`)
  if (gate.status !== 'passed') fail(`runtime evidence gate is not passed: ${name}`)
  return gate.detail
}

function validateServerDetail(name, detail) {
  if (name === 'health') {
    if (detail.before !== 'SERVING' || detail.after !== 'SERVING') fail('server health evidence must show SERVING before and after restart')
  } else if (name === 'migration') {
    if (detail.status !== 'passed' || !nonEmptyString(detail.schema_version) || !SHA256_RE.test(detail.migration_digest ?? '') || Number(detail.postgres_major) !== 18) {
      fail('server migration evidence is incomplete')
    }
  } else if (name === 'backup-restore') {
    for (const key of ['restore_verified', 'rollback_verified', 'project_count_match', 'migration_digest_match']) {
      if (detail[key] !== true) fail(`server backup-restore evidence requires ${key}=true`)
    }
  } else if (name === 'startup-recovery') {
    if (detail.supervisor !== 'LaunchAgent' || detail.restart_signal !== 'SIGKILL' || Number(detail.runs) < 2 || detail.replayed_pre_restart_event !== true) {
      fail('server startup-recovery evidence is incomplete')
    }
  } else if (name === 'logs') {
    if (detail.stdout_present !== true || detail.stderr_present !== true || detail.sensitive_data_found !== false || detail.panic_found !== false || detail.newsyslog_config !== 'passed') {
      fail('server logs evidence is incomplete')
    }
  } else {
    fail(`unknown server runtime gate: ${name}`)
  }
}

function validateMacosDetail(name, detail) {
  if (name === 'install') {
    if (detail.installed !== true || detail.launched !== true) fail('macOS install evidence is incomplete')
  } else if (name === 'upgrade') {
    if (detail.replaced !== true || detail.launched !== true || !nonEmptyString(detail.candidate_version)) fail('macOS upgrade evidence is incomplete')
  } else if (name === 'uninstall') {
    if (detail.app_absent !== true || detail.process_stopped !== true) fail('macOS uninstall evidence is incomplete')
  } else if (name === 'rollback') {
    if (detail.restored_previous !== true || detail.launched !== true) fail('macOS rollback evidence is incomplete')
  } else if (name === 'liquid-glass') {
    if (detail.glass_container !== true || detail.glass_regular !== true || !SHA256_RE.test(detail.screenshot_sha256 ?? '')) {
      fail('macOS Liquid Glass evidence is incomplete')
    }
  } else if (name === 'accessibility') {
    if (detail.audit_passed !== true || Number(detail.issue_count) !== 0) fail('macOS accessibility evidence is incomplete')
  } else if (name === 'performance') {
    if (detail.metric !== 'launch-to-evidence-ready' || Number(detail.iterations) < 3 || !Number.isFinite(Number(detail.average_ms)) || Number(detail.average_ms) > 5000 || !Number.isFinite(Number(detail.maximum_ms)) || Number(detail.maximum_ms) > 8000) {
      fail('macOS performance evidence is incomplete or above threshold')
    }
  } else {
    fail(`unknown macOS runtime gate: ${name}`)
  }
}

function verifyArtifact(platform, applicationOrBundle, evidence) {
  if (!isObject(evidence.artifact)) fail('evidence.artifact must be an object')
  if (platform === 'server') {
    const bundle = applicationOrBundle
    const server = join(bundle, 'bin/kshift-server')
    const ops = join(bundle, 'bin/kshift-ops')
    if (!existsSync(server) || !existsSync(ops)) fail('server bundle binaries are missing')
    const observed = {
      server_sha256: sha256File(server),
      ops_sha256: sha256File(ops),
      bundle_payload_sha256: treeDigest(bundle, ['BUILD_INFO.json']),
    }
    for (const [key, value] of Object.entries(observed)) {
      if (evidence.artifact[key] !== value) fail(`server artifact digest mismatch: ${key}`)
    }
  } else {
    const application = applicationOrBundle
    const executable = plistValue(application, 'CFBundleExecutable')
    const observed = {
      bundle_id: plistValue(application, 'CFBundleIdentifier'),
      short_version: plistValue(application, 'CFBundleShortVersionString'),
      build_version: plistValue(application, 'CFBundleVersion'),
      signature: codeSignature(application),
      executable_sha256: sha256File(join(application, 'Contents/MacOS', executable)),
      application_payload_sha256: treeDigest(application, ['Contents/Info.plist', 'Contents/_CodeSignature']),
    }
    for (const [key, value] of Object.entries(observed)) {
      if (evidence.artifact[key] !== value) fail(`macOS artifact digest mismatch: ${key}`)
    }
  }
}

function verifyEvidence(values) {
  const root = resolve(required(values, 'root'))
  const evidencePath = resolve(required(values, 'evidence'))
  const platform = required(values, 'platform')
  const version = required(values, 'version')
  const channel = required(values, 'channel')
  const candidateCommit = required(values, 'candidate-commit')
  const expectedGates = required(values, 'expected-gates')
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean)
  const output = resolve(required(values, 'output'))
  const artifactPath = values.bundle ? resolve(values.bundle) : values.application ? resolve(values.application) : null
  if (!PLATFORMS.includes(platform)) fail('--platform must be server or macos')
  if (!['stable', 'hotfix'].includes(channel)) fail('runtime evidence is only valid for stable or hotfix')
  if (!COMMIT_RE.test(candidateCommit)) fail('--candidate-commit must be 40 lowercase hex characters')
  if (expectedGates.length === 0) fail('--expected-gates must not be empty')
  if (!artifactPath) fail('--bundle or --application is required')
  const evidence = readJson(evidencePath)
  if (evidence.schema_version !== '1' || evidence.kind !== 'runtime-release-evidence' || evidence.product !== 'Kshift') {
    fail('runtime evidence identity is invalid')
  }
  if (evidence.platform !== platform || evidence.version !== version || evidence.channel !== channel) {
    fail('runtime evidence version, channel or platform mismatch')
  }
  if (!isObject(evidence.source) || !COMMIT_RE.test(evidence.source.commit ?? '') || evidence.source.tree_state !== 'clean') {
    fail('runtime evidence source is invalid or dirty')
  }
  if (evidence.source.input_algorithm !== INPUT_ALGORITHM) fail('runtime evidence input algorithm mismatch')
  const currentInputs = sourceInputsDigest(root)
  if (evidence.source.input_sha256 !== currentInputs.sha256) fail('runtime evidence source inputs do not match candidate checkout')
  const ancestor = spawnSync('git', ['merge-base', '--is-ancestor', evidence.source.commit, candidateCommit], { cwd: root })
  if (ancestor.status !== 0) fail('runtime evidence source commit is not an ancestor of the candidate source commit')
  if (!isObject(evidence.host) || evidence.host.os !== 'macOS' || evidence.host.architecture !== 'arm64') {
    fail('runtime evidence host is invalid')
  }
  if (!Array.isArray(evidence.limitations)) fail('runtime evidence limitations must be an array')
  scanMetadata(evidence, 'evidence')
  const gates = gateMap(evidence.gates)
  verifyArtifact(platform, artifactPath, evidence)
  const outputGates = []
  for (const name of expectedGates) {
    const detail = requirePassedGate(gates, name)
    if (platform === 'server') validateServerDetail(name, detail)
    else validateMacosDetail(name, detail)
    outputGates.push({
      name,
      status: 'passed',
      evidence: `release evidence ${basename(evidencePath)} (inputs ${currentInputs.sha256.slice(0, 12)}, gate ${name})`,
    })
  }
  const result = {
    status: 'passed',
    platform,
    version,
    channel,
    source_commit: candidateCommit,
    evidence_source_commit: evidence.source.commit,
    input_algorithm: INPUT_ALGORITHM,
    input_sha256: currentInputs.sha256,
    gates: outputGates,
  }
  scanMetadata(result, 'runtime evidence result')
  writeJson(output, result)
  process.stdout.write(`${JSON.stringify({ status: 'passed', platform, gates: outputGates.length, output })}\n`)
}

function digestCommand(values, tree = false) {
  const root = resolve(required(values, 'root'))
  const result = tree
    ? { status: 'passed', algorithm: 'kshift-tree-v1', sha256: treeDigest(root, values.exclude ? values.exclude.split(',') : []) }
    : { status: 'passed', ...sourceInputsDigest(root) }
  process.stdout.write(`${JSON.stringify(result)}\n`)
}

function main() {
  const { command, values } = parseArgs(process.argv.slice(2))
  switch (command) {
    case 'source-digest':
      return digestCommand(values)
    case 'tree-digest':
      return digestCommand(values, true)
    case 'verify':
      return verifyEvidence(values)
    default:
      fail(`unknown command: ${command ?? '<missing>'}`)
  }
}

try {
  main()
} catch (error) {
  process.stderr.write(`runtime-evidence: ${error.message}\n`)
  process.exitCode = 2
}
