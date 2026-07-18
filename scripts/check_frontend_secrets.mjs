#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const scanRoots = [
  '.env',
  '.env.local',
  '.env.development',
  '.env.production',
  '.env.test',
  'index.html',
  'vite.config.js',
  'vite.config.ts',
  'src',
  'public',
  'dist',
]

const forbiddenNames = [
  /\bVITE_[A-Z0-9_]*(SERVICE[_-]?ROLE|SECRET|PRIVATE)[A-Z0-9_]*\b/i,
  /\bSUPABASE_SERVICE_ROLE_KEY\b/i,
  /\bSERVICE_ROLE_KEY\b/i,
  /\bsb_secret_[A-Za-z0-9_-]+\b/i,
]

const jwtLike = /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g
const textExtensions = new Set([
  '.cjs', '.css', '.env', '.html', '.js', '.json', '.jsx', '.mjs',
  '.ts', '.tsx', '.txt', '.vite', '.yml', '.yaml',
])

function base64UrlDecode(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=')
  return Buffer.from(padded, 'base64').toString('utf8')
}

function tokenRole(token) {
  try {
    const payload = JSON.parse(base64UrlDecode(token.split('.')[1] || ''))
    return typeof payload.role === 'string' ? payload.role : null
  } catch {
    return null
  }
}

function extensionFor(path) {
  const name = path.split('/').pop() || path
  if (name.startsWith('.env')) return '.env'
  const dot = name.lastIndexOf('.')
  return dot === -1 ? '' : name.slice(dot)
}

function walk(path, files = []) {
  const stat = statSync(path)
  if (stat.isDirectory()) {
    for (const entry of readdirSync(path)) {
      if (['.git', 'node_modules', '.supabase'].includes(entry)) continue
      walk(join(path, entry), files)
    }
  } else if (stat.isFile() && textExtensions.has(extensionFor(path))) {
    files.push(path)
  }
  return files
}

const files = scanRoots.filter(existsSync).flatMap(path => walk(path))
const findings = []

for (const file of files) {
  const content = readFileSync(file, 'utf8')
  const rel = relative(process.cwd(), file)

  for (const pattern of forbiddenNames) {
    if (pattern.test(content)) {
      findings.push(`${rel}: prohibited frontend secret name or service credential marker`)
      break
    }
  }

  for (const match of content.matchAll(jwtLike)) {
    if (tokenRole(match[0]) === 'service_role') {
      findings.push(`${rel}: JWT payload role is service_role`)
      break
    }
  }
}

if (findings.length) {
  console.error('Frontend secret guard failed. Remove service-role/private credentials from frontend-facing files.')
  for (const finding of findings) console.error(`- ${finding}`)
  process.exit(1)
}

console.log(`Frontend secret guard passed (${files.length} files scanned).`)
