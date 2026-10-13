// Shared reader for the panel and the commands. Read-only. It never sees `$`
// (a mod passes `$` only to functions in its own file): register.js hands it
// `io`, plain functions over $.fs reads, the session's cwd and the env values
// it needs. Every function returns data or throws; callers decide what a
// failure looks like (the panel draws nothing).

const SIDES = ['fe', 'be']

// Same rule as _slug in ~/.agents/shell/worktrees.zsh:
// TODO-12-add-due-dates | dev/todo-7-1-x | todo-12  ->  todo-12 | todo-7-1
export function slugOf(branch) {
  const m = /[a-z]+-[0-9]+(-[0-9]+)?/i.exec(branch)
  return m ? m[0].toLowerCase() : branch.replace(/^[^/]*\//, '')
}

// `export NAME=value` lines of the config file -> { NAME: value }. Quotes are stripped, $HOME /
// ${HOME} / a leading ~ expanded; anything fancier is ignored.
export function parseConfig(text, home) {
  const out = {}
  for (const line of text.split('\n')) {
    const m = /^\s*export\s+([A-Z_][A-Z0-9_]*)=(?:'([^']*)'|"([^"]*)"|([^\s#]*))/.exec(line)
    if (!m) continue
    let v = m[2] ?? m[3] ?? m[4] ?? ''
    if (m[2] === undefined) v = v.replace(/\$\{HOME\}|\$HOME(?![A-Za-z0-9_])/g, home)
    if (v.startsWith('~/')) v = home + v.slice(1)
    out[m[1]] = v
  }
  return out
}

// Same precedence as hooks/lib/config.sh: the config file (~/.agents/config.local.zsh, or
// $AGENTS_CONFIG), then the environment, then the neutral defaults. A missing config file is fine.
// io.env: { HOME, AGENTS_CONFIG, WT_ROOT, FE_REPO, BE_REPO, WT_REMOTE_FE_PORT }, unset ones undefined.
export async function paths(io) {
  const home = io.env.HOME ?? ''
  const expand = p => (p && p.startsWith('~/') ? home + p.slice(1) : p)
  const file = expand(io.env.AGENTS_CONFIG) || `${home}/.agents/config.local.zsh`
  let cfg = {}
  try {
    if (await io.exists(file)) cfg = parseConfig(await io.read(file), home)
  } catch {
    cfg = {}
  }
  const get = name => cfg[name] || expand(io.env[name])
  return {
    scratch: `${home}/.agents/scratch`,
    wtRoot: get('WT_ROOT') || `${home}/Workspace/my-worktrees`,
    feRepo: get('FE_REPO') || `${home}/Workspace/my-frontend`,
    beRepo: get('BE_REPO') || `${home}/Workspace/my-backend`,
    remotePort: get('WT_REMOTE_FE_PORT') || '3000',
  }
}

const under = (cwd, root) => cwd === root || cwd.startsWith(root + '/')

// The task this session runs in, or null. A task worktree is
// <WT_ROOT>/<slug>-<side>; a main checkout counts when the scratch dir of its
// current branch's slug exists.
export async function locate(io) {
  const p = await paths(io)
  const cwd = await io.cwd()
  let slug, side
  if (under(cwd, p.wtRoot)) {
    const m = /^(.+)-(fe|be)$/.exec(cwd.slice(p.wtRoot.length + 1).split('/')[0])
    if (!m) return null
    ;[, slug, side] = m
  } else {
    const root = under(cwd, p.feRepo) ? p.feRepo : under(cwd, p.beRepo) ? p.beRepo : null
    if (!root) return null
    side = root === p.feRepo ? 'fe' : 'be'
    const head = (await io.read(`${root}/.git/HEAD`)).trim()
    const ref = /^ref: refs\/heads\/(.+)$/.exec(head)
    if (!ref) return null
    slug = slugOf(ref[1])
  }
  const dir = `${p.scratch}/${slug}`
  if (!(await io.exists(`${dir}/context.md`))) return null
  return { slug, side, dir, paths: p }
}

function frontmatter(text) {
  const m = /^---\n([\s\S]*?)\n---/.exec(text)
  const out = {}
  if (m) for (const line of m[1].split('\n')) {
    const kv = /^([\w-]+):\s*(.*)$/.exec(line)
    if (kv) out[kv[1]] = kv[2].trim()
  }
  return out
}

function field(text, name) {
  const m = new RegExp(`^\\*\\*${name}:\\*\\*\\s*(.*)$`, 'm').exec(text)
  const v = m ? m[1].trim() : ''
  return v === '—' || v === '-' ? '' : v
}

// "03; cross-repo be/02" -> { same: ['03'], cross: ['be/02'] }. Parenthesised
// asides are notes, and "None …" means no blockers.
export function parseBlockers(value) {
  if (!value || /^none\b/i.test(value)) return { same: [], cross: [] }
  const v = value.replace(/\([^)]*\)/g, '')
  const cross = [...v.matchAll(/\b(fe|be)\/(\d{2})\b/g)].map(m => `${m[1]}/${m[2]}`)
  const same = [...v.replace(/\b(fe|be)\/\d{2}\b/g, '').matchAll(/\b(\d{2})\b/g)].map(m => m[1])
  return { same, cross }
}

export function parseTicket(name, text) {
  const num = (/^(\d{2})/.exec(name) ?? [])[1] ?? name.replace(/\.md$/, '')
  const heading = (/^#\s+(.*)$/m.exec(text) ?? [])[1] ?? name
  const title = heading.replace(/^\d{2}\s*[—–-]\s*/, '').replace(/^\[[^\]]+\]\s*/, '')
  const status = field(text, 'Status')
  const pr = field(text, 'PR')
  return {
    num,
    title,
    isDone: /^done\b/i.test(status),
    status: status.split(/[\s(.]/)[0] || 'todo',
    blockers: parseBlockers(field(text, 'Blocked by')),
    linear: field(text, 'Linear'),
    branch: field(text, 'Branch'),
    base: field(text, 'Base'),
    pr: (/\/pull\/(\d+)/.exec(pr) ?? [])[1] ?? '',
    prStatus: field(text, 'PR status'),
  }
}

async function readTickets(io, dir, side) {
  const tdir = `${dir}/tickets/${side}`
  if (!(await io.exists(tdir))) return []
  const names = (await io.list(tdir))
    .filter(e => e.kind === 'file' && e.name.endsWith('.md'))
    .map(e => e.name)
    .sort()
  const out = []
  for (const name of names) out.push(parseTicket(name, await io.read(`${tdir}/${name}`)))
  return out
}

// Everything the panel and the commands show for the task at `loc`.
export async function readTask(io, loc) {
  const context = frontmatter(await io.read(`${loc.dir}/context.md`))
  const mode = context.mode === 'story' ? 'story' : 'local'
  const tickets = await readTickets(io, loc.dir, loc.side)
  const done = new Set(tickets.filter(t => t.isDone).map(t => t.num))
  const crossDone = new Set()
  for (const other of SIDES.filter(s => s !== loc.side))
    for (const t of await readTickets(io, loc.dir, other)) if (t.isDone) crossDone.add(`${other}/${t.num}`)
  for (const t of tickets) {
    t.waitingOn = [
      ...t.blockers.same.filter(n => !done.has(n)),
      ...t.blockers.cross.filter(c => !crossDone.has(c)),
    ]
  }
  const open = tickets.filter(t => !t.isDone)
  return {
    ...loc,
    mode,
    tickets,
    doneCount: done.size,
    ready: open.filter(t => t.waitingOn.length === 0),
    blocked: open.filter(t => t.waitingOn.length > 0),
    waitingCross: [...new Set(open.flatMap(t => t.waitingOn.filter(w => w.includes('/'))))].sort(),
  }
}

// Running FE dev servers, from the .shots/.fe-url files `wts` writes (and its
// trap removes): [{ port, name }]. No lsof.
export async function feServers(io, p) {
  const dirs = []
  if (await io.exists(p.wtRoot))
    for (const e of await io.list(p.wtRoot))
      if (e.kind === 'dir' && !e.name.startsWith('.')) dirs.push({ name: e.name, path: `${p.wtRoot}/${e.name}` })
  dirs.push({ name: p.feRepo.split('/').pop(), path: p.feRepo })
  const out = []
  for (const d of dirs) {
    const f = `${d.path}/.shots/.fe-url`
    if (!(await io.exists(f))) continue
    const port = (/:(\d+)/.exec(await io.read(f)) ?? [])[1]
    if (port) out.push({ port, name: d.name })
  }
  return out.sort((a, b) => Number(a.port) - Number(b.port) || a.name.localeCompare(b.name))
}

export const holderOf = (servers, port) => servers.find(s => s.port === port)?.name

// ---- text, shared by the band and the commands ---------------------------

export function headline(task) {
  const parts = [
    `${task.slug} · ${task.side} · ${task.mode}`,
    `tickets ${task.doneCount}/${task.tickets.length} done`,
  ]
  if (task.ready.length) parts.push(`wave: ${task.ready.map(t => t.num).join(', ')}`)
  if (task.waitingCross.length) parts.push(`waiting: ${task.waitingCross.join(', ')}`)
  return parts.join('   ')
}

export function prLine(task) {
  const prs = task.tickets.filter(t => t.pr)
  return prs.length ? `PRs: ${prs.map(t => `#${t.pr} ${t.prStatus || '?'}`).join(' · ')}` : ''
}

// `port` = the configured remote-API FE port (paths().remotePort), shared by one task at a time.
export const portLine = (servers, port) => `:${port} → ${holderOf(servers, port) ?? 'free'}`

export function ticketsText(task) {
  const rows = [
    ...task.ready.map(t => `ready    ${t.num}  ${t.title}`),
    ...task.blocked.map(t => `blocked  ${t.num}  ${t.title}  — by ${t.waitingOn.join(', ')}`),
    ...task.tickets.filter(t => t.isDone).map(t => `done     ${t.num}  ${t.title}`),
  ]
  return [`${task.slug} · ${task.side} · ${task.mode} — ${task.doneCount}/${task.tickets.length} done`, ...rows].join('\n')
}

export function whoText(servers, port) {
  const others = servers.filter(s => s.port !== port)
  return [portLine(servers, port), ...others.map(s => `:${s.port} → ${s.name}`)].join('\n')
}

export function storyText(task) {
  if (task.mode !== 'story') return `${task.slug}: mode ${task.mode} — /story is for story mode only`
  return [
    `${task.slug} · ${task.side} · story`,
    ...task.tickets.map(t =>
      [
        t.num,
        t.linear || '—',
        t.branch || '—',
        `base ${t.base || '—'}`,
        t.pr ? `#${t.pr} ${t.prStatus || '?'}` : 'no PR',
      ].join('  '),
    ),
  ].join('\n')
}
