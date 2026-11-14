#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..')

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

function readOptional(path) {
  return existsSync(path) ? readFileSync(path, 'utf8') : ''
}

function cleanId(value) {
  return value.replace(/[^A-Za-z0-9.+-]/g, '-')
}

function cargoPackages(root) {
  const text = readOptional(join(root, 'Cargo.lock'))
  const packages = []
  for (const block of text.split('[[package]]').slice(1)) {
    const name = block.match(/^name\s*=\s*"([^"]+)"/m)?.[1]
    const version = block.match(/^version\s*=\s*"([^"]+)"/m)?.[1]
    const checksum = block.match(/^checksum\s*=\s*"([0-9a-f]{64})"/m)?.[1]
    if (name && version) packages.push({ ecosystem: 'cargo', name, version, checksum })
  }
  return packages
}

function swiftPackages(root) {
  const path = join(root, 'Package.resolved')
  const text = readOptional(path)
  if (!text) return []
  let data
  try {
    data = JSON.parse(text)
  } catch (error) {
    throw new Error(`invalid Package.resolved: ${error.message}`)
  }
  const pins = data.pins ?? data.object?.pins ?? []
  return pins.map((pin) => {
    const identity = pin.identity ?? pin.package
    const state = pin.state ?? {}
    const version = state.version ?? state.revision ?? 'unknown'
    const checksum = /^[0-9a-f]{40}$/.test(state.revision ?? '') ? state.revision : undefined
    return { ecosystem: 'swift', name: identity, version, checksum }
  }).filter((item) => item.name)
}

function nodePackages(root) {
  const path = join(root, 'package-lock.json')
  const text = readOptional(path)
  if (!text) return []
  const data = JSON.parse(text)
  return Object.entries(data.packages ?? {})
    .filter(([name]) => name.startsWith('node_modules/'))
    .map(([name, pkg]) => ({
      ecosystem: 'npm',
      name: name.replace(/^node_modules\//, ''),
      version: pkg.version ?? 'unknown',
      checksum: pkg.integrity ? undefined : undefined,
    }))
}

function main() {
  const values = parseArgs(process.argv.slice(2))
  const root = values.root ? resolve(values.root) : ROOT
  const output = resolve(required(values, 'output'))
  const product = values.product ?? 'Kshift'
  const version = required(values, 'version')
  const sourceCommit = required(values, 'source-commit')
  if (!/^[0-9a-f]{40}$/.test(sourceCommit)) throw new Error('source commit must be 40 lowercase hex characters')

  const packages = [...cargoPackages(root), ...swiftPackages(root), ...nodePackages(root)]
    .filter((item, index, all) => all.findIndex((other) =>
      other.ecosystem === item.ecosystem && other.name === item.name && other.version === item.version
    ) === index)
    .sort((left, right) =>
      `${left.ecosystem}:${left.name}:${left.version}`.localeCompare(`${right.ecosystem}:${right.name}:${right.version}`)
    )

  const spdxPackages = packages.map((pkg) => {
    const id = `SPDXRef-Package-${cleanId(pkg.ecosystem)}-${cleanId(pkg.name)}-${cleanId(pkg.version)}`
    return {
      SPDXID: id,
      name: pkg.name,
      versionInfo: pkg.version,
      downloadLocation: 'NOASSERTION',
      filesAnalyzed: false,
      licenseConcluded: pkg.ecosystem === 'cargo' ? 'NOASSERTION' : 'NOASSERTION',
      licenseDeclared: 'NOASSERTION',
      copyrightText: 'NOASSERTION',
      externalRefs: [
        {
          referenceCategory: 'PACKAGE-MANAGER',
          referenceType: pkg.ecosystem === 'cargo' ? 'purl' : 'purl',
          referenceLocator: `pkg:${pkg.ecosystem}/${encodeURIComponent(pkg.name)}@${encodeURIComponent(pkg.version)}`,
        },
      ],
    }
  })

  const rootId = 'SPDXRef-Package-Kshift'
  const doc = {
    spdxVersion: 'SPDX-2.3',
    dataLicense: 'CC0-1.0',
    SPDXID: 'SPDXRef-DOCUMENT',
    name: `${product}-${version}`,
    documentNamespace: `https://github.com/wyz541/Kshift/spdx/${sourceCommit}/${createHash('sha256').update(`${product}:${version}`).digest('hex').slice(0, 16)}`,
    creationInfo: {
      created: new Date().toISOString(),
      creators: ['Tool: Kshift release-sbom'],
    },
    packages: [
      {
        SPDXID: rootId,
        name: product,
        versionInfo: version,
        downloadLocation: 'NOASSERTION',
        filesAnalyzed: false,
        licenseConcluded: 'NOASSERTION',
        licenseDeclared: 'NOASSERTION',
        copyrightText: 'NOASSERTION',
        comment: `source commit ${sourceCommit}`,
      },
      ...spdxPackages,
    ],
    relationships: [
      {
        spdxElementId: 'SPDXRef-DOCUMENT',
        relationshipType: 'DESCRIBES',
        relatedSpdxElement: rootId,
      },
      ...spdxPackages.map((pkg) => ({
        spdxElementId: rootId,
        relationshipType: 'DEPENDS_ON',
        relatedSpdxElement: pkg.SPDXID,
      })),
    ],
  }
  mkdirSync(dirname(output), { recursive: true })
  writeFileSync(output, `${JSON.stringify(doc, null, 2)}\n`, 'utf8')
  process.stdout.write(`${JSON.stringify({ status: 'passed', output, packages: spdxPackages.length })}\n`)
}

try {
  main()
} catch (error) {
  process.stderr.write(`generate-sbom: ${error.message}\n`)
  process.exitCode = 2
}
