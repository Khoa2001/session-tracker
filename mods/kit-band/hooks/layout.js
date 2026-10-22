// Pure layout for the band: no Claude Code API in here, so tests can import it directly.
// Colors follow the approved preview; model colors mirror statusline/statusline-command.sh.

const THEMES = {
  opus: { name: 'opus', dir: '#fba4c8', branch: '#c86edc' },
  sonnet: { name: 'sonnet', dir: '#facc6e', branch: '#e68246' },
  haiku: { name: 'haiku', dir: '#6ee7d7', branch: '#38a0dc' },
  fable: { name: 'fable', dir: '#c4b5fd', branch: '#818cf8' },
  claude: { name: 'claude', dir: '#4cd0de', branch: '#c067de' },
}

const PREFIXES = ['feat', 'fix', 'chore', 'refactor', 'docs', 'test', 'perf', 'build', 'ci', 'style', 'revert', 'hotfix']

export function modelTheme(model) {
  const id = String(model || '').toLowerCase()
  for (const key of ['opus', 'sonnet', 'haiku', 'fable']) {
    if (id.includes(key)) return THEMES[key]
  }
  return THEMES.claude
}

// Branch without its conventional type prefix (feat/, fix/, ...).
export function shortBranch(branch) {
  const i = branch.indexOf('/')
  return i > 0 && PREFIXES.includes(branch.slice(0, i)) ? branch.slice(i + 1) : branch
}

// Cap a name at 14 characters, ending in an ellipsis.
export function cap(text) {
  const chars = Array.from(text)
  return chars.length <= 14 ? text : chars.slice(0, 13).join('') + '…'
}

export function ctxLevel(pct) {
  if (pct < 60) return 'ok'
  if (pct < 85) return 'warn'
  return 'bad'
}

// Fit to the pane: drop the diff, then shorten the branch, then drop it, then cap the
// repo, and stop at the first layout that fits. Unknown width shows everything. state: { model, repo, name, branch, changed, ahead, pct }.
export function layout(state, cols) {
  const theme = modelTheme(state.model)
  const out = {
    theme,
    name: state.name || '',
    branch: state.branch ? shortBranch(state.branch) : '',
    showBranch: Boolean(state.branch),
    changed: state.changed > 0 ? state.changed : 0,
    ahead: state.ahead > 0 ? state.ahead : 0,
    showDiff: state.changed > 0 || state.ahead > 0,
    pct: typeof state.pct === 'number' ? Math.round(state.pct) : null,
  }
  out.diffText = [state.changed > 0 ? '±' + state.changed : '', state.ahead > 0 ? '↑' + state.ahead : '']
    .filter(Boolean)
    .join(' ')
  if (out.pct !== null) out.level = ctxLevel(out.pct)

  const width = () => {
    let w = theme.name.length
    if (out.name) w += 2 + out.name.length
    if (out.showBranch && out.branch) w += 1 + out.branch.length
    if (out.showDiff && out.diffText) w += 3 + out.diffText.length
    if (out.pct !== null) w += 3 + String(out.pct).length + 1
    return w
  }
  if (typeof cols === 'number' && cols > 0) {
    const avail = cols - 2
    const fits = () => width() <= avail
    if (!fits()) out.showDiff = false
    if (!fits()) out.branch = cap(shortBranch(state.branch || ''))
    if (!fits()) out.showBranch = false
    if (!fits()) out.name = cap(state.name || '')
  }
  return out
}
