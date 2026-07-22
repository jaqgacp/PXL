#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { basename, dirname, join, normalize, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const errors = []
const notes = []
const fail = (message) => errors.push(message)

function read(relativePath) {
  return readFileSync(join(root, relativePath), 'utf8')
}

function markdownFiles(directory) {
  const output = []
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (['.git', 'node_modules', 'dist'].includes(entry.name)) continue
    const path = join(directory, entry.name)
    if (entry.isDirectory()) output.push(...markdownFiles(path))
    else if (entry.isFile() && entry.name.endsWith('.md')) output.push(path)
  }
  return output
}

function activeMarkdownFiles() {
  return markdownFiles(root).filter((path) =>
    !path.includes('/docs/PXL/archive/') &&
    !path.includes('/docs/PXL/trash-review/'))
}

function section(markdown, heading) {
  const start = markdown.indexOf(`${heading}\n`)
  if (start === -1) return ''
  const bodyStart = start + heading.length + 1
  const next = markdown.slice(bodyStart).search(/^#{1,2} /m)
  return next === -1 ? markdown.slice(bodyStart) : markdown.slice(bodyStart, bodyStart + next)
}

function wordCount(markdown) {
  return (markdown.match(/\S+/g) || []).length
}

function parseFindings(markdown) {
  const index = section(markdown, '## Findings Status Index')
  const rows = []
  for (const line of index.split('\n')) {
    const match = line.match(/^\|\s*(PXL-(?:AUD|DA)-\d+)\s*\|\s*(Critical|High|Medium|Low)\s*\|\s*(Open|In Progress|Retested Passed)\s*\|/)
    if (match) rows.push({ id: match[1], severity: match[2], status: match[3] })
  }
  return rows
}

function findBasename(name) {
  const ignored = new Set(['.git', 'node_modules', 'dist'])
  const matches = []
  function walk(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (ignored.has(entry.name)) continue
      const path = join(directory, entry.name)
      if (entry.isDirectory()) walk(path)
      else if (entry.name === name) matches.push(path)
    }
  }
  walk(root)
  return matches
}

const state = read('AI/AI_STATE.md')
const prompt = read('AI/AGENT_SYSTEM_PROMPT.md')
const findings = read('docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md')
const findingRows = parseFindings(findings)

if (findingRows.length === 0) fail('authoritative Findings Status Index is missing or unparseable')

const statusCounts = findingRows.reduce((counts, row) => {
  counts[row.status] = (counts[row.status] || 0) + 1
  return counts
}, {})
const active = findingRows.filter((row) => row.status !== 'Retested Passed')
const expectedStanding = `${statusCounts['Retested Passed'] || 0} Retested Passed / ${statusCounts['In Progress'] || 0} In Progress / ${statusCounts.Open || 0} Open (${findingRows.length} total)`

if (!state.includes(expectedStanding)) {
  fail(`AI State standing does not match register: expected "${expectedStanding}"`)
}

const requiredStateMarkers = [
  '**Current Date:**',
  '**Current Branch:**',
  '**Working Tree:**',
  '**Product Phase:**',
  '**Environment:**',
  '**Product Readiness:**',
  '## Current Finding Standing',
  '## Active Work Map',
  '## Hosted and UX Status',
  '## Known Blockers and Non-Assumptions',
  '## Last Verified Commands',
  '## Recommended Next Task',
]
for (const marker of requiredStateMarkers) {
  if (!state.includes(marker)) fail(`AI State is missing required marker: ${marker}`)
}

const today = new Date().toISOString().slice(0, 10)
if (!state.includes(`**Current Date:** ${today}`)) {
  fail(`AI State current date is missing or stale; expected ${today}`)
}

let branch = ''
try {
  branch = execFileSync('git', ['branch', '--show-current'], { cwd: root, encoding: 'utf8' }).trim()
} catch {
  fail('could not determine current Git branch')
}
if (branch && !state.includes(`**Current Branch:** \`${branch}\``)) {
  fail(`AI State branch does not match working tree: expected ${branch}`)
}

const stateWords = wordCount(state)
const promptWords = wordCount(prompt)
if (stateWords < 500 || stateWords > 1500) fail(`AI State length is ${stateWords} words; expected 500-1500`)
if (promptWords < 800 || promptWords > 1500) fail(`Agent System Prompt length is ${promptWords} words; expected 800-1500`)

const recommendedHeadings = state.match(/^## Recommended Next Task\s*$/gm) || []
if (recommendedHeadings.length !== 1) {
  fail(`AI State must have exactly one Recommended Next Task heading; found ${recommendedHeadings.length}`)
}
const recommended = section(state, '## Recommended Next Task')
const recommendedIds = [...new Set(recommended.match(/PXL-(?:AUD|DA)-\d+/g) || [])]
if (active.length === 0) {
  // Fully-closed certification program: no finding remains open. The
  // Recommended Next Task must then name no finding and must explicitly state
  // that the finding program is complete (a next task may still be described in
  // prose, e.g. module/engine certification, without a finding ID).
  if (recommendedIds.length !== 0) {
    fail(`with no open findings, Recommended Next Task must name no finding; found ${recommendedIds.join(', ')}`)
  } else if (!/no (?:audit )?findings? remain open|finding program is complete|no open findings remain/i.test(recommended)) {
    fail('with no open findings, Recommended Next Task must state that the finding program is complete')
  }
} else if (recommendedIds.length !== 1) {
  fail(`Recommended Next Task must name exactly one finding; found ${recommendedIds.join(', ') || 'none'}`)
} else {
  const selected = findingRows.find((row) => row.id === recommendedIds[0])
  if (!selected) fail(`recommended finding ${recommendedIds[0]} does not exist in the register`)
  else if (selected.status === 'Retested Passed') fail(`recommended finding ${selected.id} is already Retested Passed`)
}

for (const row of active) {
  const anchor = `<a id="${row.id.toLowerCase()}"></a>`
  if (!findings.includes(anchor)) fail(`active finding anchor is missing: ${row.id}`)
  if ((row.severity === 'Critical' || row.severity === 'High') && !state.includes(row.id)) {
    fail(`active ${row.severity} finding is omitted from AI State: ${row.id}`)
  }
}

const activeListing = [
  section(state, '## Current Finding Standing'),
  section(state, '## Active Work Map'),
  ...[...state.matchAll(/^### (PXL-(?:AUD|DA)-\d+)/gm)].map((match) => match[1]),
].join('\n')
for (const row of findingRows.filter((item) => item.status === 'Retested Passed')) {
  if (activeListing.includes(row.id)) fail(`passed finding is incorrectly listed as active: ${row.id}`)
}

const positiveReadinessPatterns = [
  /PXL\s+is\s+production[- ]ready/i,
  /product\s+is\s+production[- ]ready/i,
  /Sales Invoice UX\s+(?:is\s+)?fully implemented/i,
]
for (const pattern of positiveReadinessPatterns) {
  for (const match of state.matchAll(new RegExp(pattern.source, 'gi'))) {
    const context = state.slice(Math.max(0, match.index - 40), match.index + match[0].length + 20)
    if (!/\bnot\b|\bnever\b|\bneither\b|while .* remain active/i.test(context)) {
      fail(`AI State contains an unsupported readiness claim: "${match[0]}"`)
    }
  }
}
if (!/not production-ready/i.test(state)) fail('AI State must explicitly state that PXL is not production-ready')
if (!/business qualification remains source-gated|PXL-AUD-053 still governs/i.test(state)) {
  fail('AI State must distinguish transaction-workspace UI completion from Sales Invoice business/source qualification')
}

// Validate explicit Markdown links in active documents.
for (const path of activeMarkdownFiles()) {
  const markdown = readFileSync(path, 'utf8')
  for (const match of markdown.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
    let target = match[1].trim()
    if (!target || /^(?:https?:|mailto:|#)/.test(target)) continue
    target = target.replace(/^<|>$/g, '')
    const targetPath = decodeURIComponent(target.split('#')[0])
    if (!targetPath) continue
    const resolved = normalize(resolve(dirname(path), targetPath))
    if (!existsSync(resolved)) fail(`broken internal link in ${path.slice(root.length + 1)}: ${target}`)
    if ((resolved.includes('/archive/') || resolved.includes('/trash-review/')) && !path.endsWith('PXL_DOCUMENTATION_INDEX.md')) {
      fail(`active document links to non-current material: ${path.slice(root.length + 1)} -> ${target}`)
    }
  }
}

// Validate file references in AI State. A planned output is allowed only on a
// line explicitly marked "Create then run".
for (const line of state.split('\n')) {
  for (const match of line.matchAll(/`([^`]+\.(?:md|mjs|tsx|ts|sql|json))`/g)) {
    const ref = match[1]
    if (/\s/.test(ref) && !ref.startsWith('docs/')) continue
    if (line.includes('Create then run')) continue
    if (ref.includes('/')) {
      const path = join(root, ref)
      if (!existsSync(path)) fail(`AI State references a missing file: ${ref}`)
    } else if (findBasename(ref).length === 0) {
      fail(`AI State references a missing basename: ${ref}`)
    }
  }
}

for (const line of state.split('\n')) {
  if (/Read first:|Files to inspect|Governing documents|Recommended Next Task/i.test(line) &&
      /archive\/|trash-review\//i.test(line) &&
      !/Do not/i.test(line)) {
    fail(`archived/trash material is listed as current required reading: ${line.trim()}`)
  }
}

const aiMarkdown = readdirSync(join(root, 'AI')).filter((name) => name.endsWith('.md')).sort()
const expectedAiMarkdown = ['AGENT_SYSTEM_PROMPT.md', 'AI_STATE.md']
if (JSON.stringify(aiMarkdown) !== JSON.stringify(expectedAiMarkdown)) {
  fail(`AI/ must contain only the two startup files; found ${aiMarkdown.join(', ')}`)
}

const duplicateRegisterNames = activeMarkdownFiles()
  .map((path) => basename(path))
  .filter((name) => /(?:FINDINGS|DEFECT|REMEDIATION).*(?:REGISTER|TRACKER)|MASTER_AUDIT_FINDINGS/i.test(name))
if (duplicateRegisterNames.length > 0) fail(`possible competing findings register: ${duplicateRegisterNames.join(', ')}`)

const staleStatusFiles = [
  'AI/AI_STATE.md',
  'docs/PXL/01. Architecture/PXL_ARCHITECTURE_SUMMARY.md',
  'docs/PXL/02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md',
  'docs/PXL/13. Testing and Validation/PXL_CANONICAL_DEMO_DATASET.md',
  'docs/PXL/00. Governance/PXL_PRODUCT_BACKLOG.md',
]
for (const relativePath of staleStatusFiles) {
  const markdown = read(relativePath)
  // Once the certification program is fully closed the authoritative current
  // standing legitimately reports 0 Open; exempt only that exact standing string
  // so any OTHER unqualified zero-open claim still fails.
  const withoutStanding = markdown.split(expectedStanding).join(' ')
  if (/zero open findings|all findings closed|\b0\s+Open\b/i.test(withoutStanding)) {
    fail(`stale zero-open status phrase found in ${relativePath}`)
  }
}

for (const relativePath of [
  'docs/PXL/archive/phase-reports/PXL_PHASE2_PRODUCT_AUDIT_REPORT.md',
  'docs/PXL/archive/phase-reports/PXL_PHASE3_CANONICAL_IMPLEMENTATION_REPORT.md',
]) {
  const markdown = read(relativePath)
  if (!markdown.includes('**Status:** Historical Snapshot') || !markdown.includes('**Not Current Source of Truth:**')) {
    fail(`archived phase report lacks snapshot/source-of-truth label: ${relativePath}`)
  }
}

notes.push(`findings: ${expectedStanding}; active IDs: ${active.map((row) => row.id).join(', ')}`)
notes.push(`startup length: Agent Prompt ${promptWords} words; AI State ${stateWords} words`)
notes.push(`recommended next finding: ${recommendedIds[0] || 'invalid'}`)

if (errors.length > 0) {
  for (const message of errors) console.error(`FAIL: ${message}`)
  process.exit(1)
}

for (const message of notes) console.log(`OK: ${message}`)
