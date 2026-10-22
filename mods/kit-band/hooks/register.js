import { layout, bar, modelTheme } from './layout.js'

// Prints repo, branch, changed lines, commits ahead as four lines. Sourced from the
// kit's own git helpers so the band and the status line agree. Never fetches.
const GIT_SCRIPT = [
  '. "$1" 2>/dev/null || exit 0',
  'd=$2',
  'repo=$(git_repo_name "$d"); br=$(git_branch "$d"); n=0; ah=0',
  'if [ -n "$repo" ]; then',
  '  set -- $(git_diff_stat "$d"); n=$(( $1 + $2 ))',
  '  base=$(git_base_ref "$d"); [ -n "$base" ] && ah=$(git_ahead "$d" "$base")',
  'fi',
  'printf "%s\\n%s\\n%s\\n%s\\n" "$repo" "$br" "$n" "${ah:-0}"',
].join('\n')

const REFRESH_MS = 5000

// Tool calls in the current turn, shown beside the spinner
let calls = 0
// Latest values for the band; null until the first refresh lands
let snap = null

function basename(path) {
  const parts = String(path).split('/').filter(Boolean)
  return parts.length ? parts[parts.length - 1] : ''
}

// One refresh: a few cheap reads, then a redraw only when something changed.
async function refresh($) {
  try {
    const cwd = await $.session.cwd()
    const model = await $.session.model()
    const usage = await $.session.usage()
    const root = $.plugin.root
    let lines = []
    try {
      const ran = await $.process.run(['sh', '-c', GIT_SCRIPT, 'sh', root + '/../../lib/git-info.sh', cwd])
      lines = String(ran.stdout || '').split('\n')
    } catch (error) {
      // No git, no sh, or a timeout: the band shows no git segment
    }
    const repo = lines[0] || ''
    const next = {
      model,
      repo,
      name: repo || basename(cwd),
      branch: repo ? lines[1] || '' : '',
      changed: Number(lines[2]) || 0,
      ahead: Number(lines[3]) || 0,
      pct: usage && usage.context && typeof usage.context.percent === 'number' ? usage.context.percent : null,
    }
    if (JSON.stringify(next) !== JSON.stringify(snap)) {
      snap = next
      $.ui.invalidate('ui.render')
    }
  } catch (error) {
    // Failure means "shows nothing"
  }
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    $.clock.every(REFRESH_MS, () => refresh($))
    // Not awaited: the session starts without waiting for git
    refresh($)
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    calls = 0
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    calls += 1
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    // Not awaited: a finished turn should not wait for git
    refresh($)
    return next(e)
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    if (calls === 0) return next(e)
    return next({ ...e, props: { ...e.props, suffix: ' · ' + calls + (calls === 1 ? ' tool' : ' tools') + '…' } })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!snap) return next(e)
    try {
      const { Box, Text } = $.ui.resolve(e)
      const v = layout(snap, e.props && e.props.bodyColumns)
      const levelColor = { ok: '#7ad99a', warn: '#f0c36a', bad: '#f08aa0' }
      const sep = (key) => Text({ key, color: '#6b7388', children: ['│'] })
      const parts = [
        Box({
          key: 'model',
          marginRight: 1,
          children: [Text({ color: v.theme.dir, weight: 'semibold', children: [v.theme.name] })],
        }),
      ]
      if (v.name) {
        const repo = [Text({ key: 'repo', color: v.theme.dir, children: [v.name] })]
        if (v.showBranch && v.branch) repo.push(Text({ key: 'branch', color: v.theme.branch, children: [v.branch] }))
        parts.push(Box({ key: 'where', flexDirection: 'row', columnGap: 1, children: repo }))
      }
      if (v.showDiff && v.diffText) {
        const diff = []
        if (v.changed > 0) diff.push(Text({ key: 'changed', color: '#f0c36a', children: ['±' + v.changed] }))
        if (v.ahead > 0) diff.push(Text({ key: 'ahead', color: '#7ad99a', children: ['↑' + v.ahead] }))
        parts.push(sep('s1'), Box({ key: 'diff', flexDirection: 'row', columnGap: 1, children: diff }))
      }
      if (v.pct !== null) {
        const text = (v.showBar ? bar(v.pct) + ' ' : '') + v.pct + '%'
        parts.push(sep('s2'), Text({ key: 'ctx', color: levelColor[v.level], children: [text] }))
      }
      const mine = Box({ key: 'band', flexDirection: 'row', columnGap: 1, children: parts })
      // Keep what mods after this one draw in the band
      const theirs = await next(e)
      return theirs ? Box({ flexDirection: 'column', children: [mine, theirs] }) : mine
    } catch (error) {
      return next(e)
    }
  })
}
