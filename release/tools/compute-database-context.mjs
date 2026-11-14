#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { Buffer } from 'node:buffer'
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'

function parseArgs(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]
    if (!token.startsWith('--')) throw new Error(`unexpected argument: ${token}`)
    const equals = token.indexOf('=')
    if (equals > 2) {
      values[token.slice(2, equals)] = token.slice(equals + 1)
      continue
    }
    const key = token.slice(2)
    const value = argv[index + 1]
    if (value == null || value.startsWith('--')) throw new Error(`--${key} needs a value`)
    values[key] = value
    index += 1
  }
  return values
}

function required(values, key) {
  if (!values[key]) throw new Error(`missing --${key}`)
  return values[key]
}

function main() {
  const values = parseArgs(process.argv.slice(2))
  const directory = resolve(required(values, 'migrations-dir'))
  const exactVersion = required(values, 'exact-version')
  const output = resolve(required(values, 'output'))
  if (!existsSync(directory) || !statSync(directory).isDirectory()) {
    throw new Error(`migration directory is missing: ${directory}`)
  }
  if (!/^18\.[0-9]+(?:\.[0-9]+)?$/.test(exactVersion)) {
    throw new Error('exact version must start with PostgreSQL 18')
  }
  const files = readdirSync(directory)
    .filter((name) => name.endsWith('.sql'))
    .sort()
  if (files.length === 0) throw new Error('migration directory has no SQL files')
  const digest = createHash('sha256')
  let schemaVersion = values['schema-version']
  if (!schemaVersion) {
    const domainSource = readFileSync(resolve(values['domain-source'] ?? join(directory, '..', 'crates/kshift-domain/src/lib.rs')), 'utf8')
    schemaVersion = domainSource.match(/pub const SCHEMA_VERSION:\s*u32\s*=\s*([0-9]+)/)?.[1]
    if (!schemaVersion) throw new Error('cannot read SCHEMA_VERSION from domain source')
  }
  if (!/^[0-9]+$/.test(schemaVersion)) throw new Error('schema version must be numeric')
  for (const name of files) {
    const match = name.match(/^[0-9]{4}_[A-Za-z0-9_-]+\.sql$/)
    if (!match) throw new Error(`invalid migration filename: ${name}`)
    const content = readFileSync(join(directory, name))
    digest.update(name)
    digest.update(Buffer.from([0]))
    digest.update(content)
    digest.update(Buffer.from([0]))
  }
  const context = {
    engine: 'postgresql',
    major: 18,
    exact_version: exactVersion,
    schema_version: schemaVersion,
    migration_digest: digest.digest('hex'),
  }
  mkdirSync(dirname(output), { recursive: true })
  writeFileSync(output, `${JSON.stringify(context, null, 2)}\n`, 'utf8')
  process.stdout.write(`${JSON.stringify({ status: 'passed', output, schema_version: schemaVersion, migration_digest: context.migration_digest })}\n`)
}

try {
  main()
} catch (error) {
  process.stderr.write(`compute-database-context: ${error.message}\n`)
  process.exitCode = 2
}
