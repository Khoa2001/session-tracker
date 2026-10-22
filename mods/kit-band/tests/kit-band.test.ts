import { expect, mock, test } from 'claude-code/testing'
import { cap, ctxLevel, layout, shortBranch } from '../hooks/layout.js'

const HINT = {
  plugin: 'kit-band',
  component: 'PromptHint',
  requestId: 'hint',
  surface: 'terminal',
  viewport: { columns: 100, rows: 30 },
  props: { isDraft: false, isWorking: false, hint: 'bypass permissions on (shift+tab to cycle)' },
} as const

const SPINNER = {
  plugin: 'kit-band',
  component: 'Spinner',
  requestId: 'main',
  surface: 'terminal',
  viewport: { columns: 100, rows: 30 },
  props: { word: 'Thinking', message: '', suffix: '', mode: 'thinking' },
} as const

test('pure helpers', () => {
  expect(shortBranch('feat/mod-kit-band')).toBe('mod-kit-band')
  expect(shortBranch('main')).toBe('main')
  expect(shortBranch('wip/x')).toBe('wip/x')
  expect(cap('short')).toBe('short')
  expect(cap('wezterm-claude-kit')).toBe('wezterm-claud…')
  expect(ctxLevel(59)).toBe('ok')
  expect(ctxLevel(60)).toBe('warn')
  expect(ctxLevel(85)).toBe('bad')
})

test('layout drops parts in order when narrow', () => {
  const state = { model: 'claude-opus-4', name: 'wezterm-claude-kit', branch: 'feat/mod-kit-band', changed: 42, ahead: 3, pct: 31 }
  const wide = layout(state, 100)
  expect(wide.showDiff && wide.showBranch).toBe(true)
  expect(wide.branch).toBe('mod-kit-band')
  expect(layout(state, 36).showDiff).toBe(false)
  expect(layout(state, 20).showBranch).toBe(false)
  expect(layout({ ...state, branch: '' }, undefined).showBranch).toBe(false)
})

function stubSession(on: any, git: string, drawn: any = { type: 'Text', props: {}, children: ['engine'] }) {
  on('session.cwd', () => ({ value: '/work/wezterm-claude-kit' }))
  on('session.model', () => ({ value: 'claude-opus-4' }))
  on('session.usage', () => ({ value: { context: { tokens: 1, window: 2, percent: 31 }, rateLimits: [], cost: 0 } }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: git, stderr: '' } }))
  on('session.start', () => ({ cwd: '/work' }))
  on('ui.render', () => drawn)
}

test('band shows repo, branch, diff and context after a refresh', async ($, on) => {
  const clock = mock.clock(on)
  stubSession(on, 'wezterm-claude-kit\nfeat/mod-kit-band\n42\n3\n')
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await clock.advance(5000)
  const ui = await $.ui.mount(HINT)
  expect(await ui.find({ type: 'Text', text: 'opus' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'wezterm-claude-kit' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'mod-kit-band' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '±42' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '↑3' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '31%' })).toBeDefined()
  await ui.unmount()
})

test('outside a repo the git segments drop out', async ($, on) => {
  const clock = mock.clock(on)
  stubSession(on, '\n\n0\n0\n')
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await clock.advance(5000)
  const ui = await $.ui.mount(HINT)
  expect(await ui.find({ type: 'Text', text: 'wezterm-claude-kit' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^±/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^↑/ })).toBeUndefined()
  await ui.unmount()
})

test('spinner suffix counts tool calls', async ($, on) => {
  on('tool.call', () => ({ result: 'ok' }))
  on('ui.render', ($, e) => ({ type: 'Text', props: {}, children: [e.props.suffix] }))
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await $.tool.call({ tool: 'Read', file_path: 'README.md' })
  const ui = await $.ui.mount(SPINNER)
  expect(await ui.find({ type: 'Text', text: ' · 2 tools…' })).toBeDefined()
  await ui.unmount()
})

test('the band sits beside the engine hint line', async ($, on) => {
  const clock = mock.clock(on)
  // What Claude Code hands next() at this site: a reference to its own drawing
  stubSession(on, 'wezterm-claude-kit\nmain\n0\n0\n', { type: 'engine', ref: 0 })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await clock.advance(5000)
  const ui = await $.ui.mount(HINT)
  expect(await ui.find({ type: 'Text', text: 'opus' })).toBeDefined()
  await ui.unmount()
})
