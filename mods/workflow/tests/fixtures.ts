// A fake disk for the tests: HOME=/home/u, WT_ROOT=/wt.
// Scratch: todo-1 (local mode), todo-2 (story mode with PRs and a cross-repo edge).
// FE servers: todo-2-fe on :3000, todo-1-fe on :5210 (from .shots/.fe-url).

export const HOME = '/home/u'
export const WT = '/wt'
const S = `${HOME}/.agents/scratch`

const ticket = (n: string, title: string, fields: Record<string, string>) =>
  [`# ${n} — ${title}`, '', ...Object.entries(fields).map(([k, v]) => `**${k}:** ${v}`), ''].join('\n')

export const FILES: Record<string, string> = {
  // local mode: 01 done, 02 ready, 03 blocked by 02
  [`${S}/todo-1/context.md`]: '---\nstage: grilled\nbranch: dev/todo-1-thing\n---\n\n## Task\n',
  [`${S}/todo-1/tickets/fe/01-a.md`]: ticket('01', '[frontend] First', { 'Blocked by': 'None — can start immediately.', Status: 'done (abc123)' }),
  [`${S}/todo-1/tickets/fe/02-b.md`]: ticket('02', '[frontend] Second', { 'Blocked by': '01 (linearised; no functional dependency)', Status: 'ready-for-agent' }),
  [`${S}/todo-1/tickets/fe/03-c.md`]: ticket('03', '[frontend] Third', { 'Blocked by': '02', Status: 'ready-for-agent' }),

  // story mode: fe/01 done+merged, fe/02 done+ready PR, fe/03 waits on be/02, fe/04 ready
  [`${S}/todo-2/context.md`]: '---\nstage: grilled\nbranch: dev/todo-2-story\nmode: story\nbase: main\n---\n',
  [`${S}/todo-2/tickets/fe/01-a.md`]: ticket('01', '[frontend] One', {
    'Blocked by': 'None', Linear: 'TODO-11', Branch: 'dev/todo-11-one', Base: 'story',
    PR: 'https://github.com/o/r/pull/1640', 'PR status': 'merged', Status: 'done',
  }),
  [`${S}/todo-2/tickets/fe/02-b.md`]: ticket('02', '[frontend] Two', {
    'Blocked by': '01', Linear: 'TODO-12', Branch: 'dev/todo-12-two', Base: '01',
    PR: 'https://github.com/o/r/pull/1641', 'PR status': 'draft', Status: 'done',
  }),
  [`${S}/todo-2/tickets/fe/03-c.md`]: ticket('03', '[frontend] Three', {
    'Blocked by': '02; cross-repo be/02', Linear: 'TODO-13', Branch: 'dev/todo-13-three', Base: '02',
    PR: '—', 'PR status': '—', Status: 'ready-for-agent',
  }),
  [`${S}/todo-2/tickets/fe/04-d.md`]: ticket('04', '[frontend] Four', {
    'Blocked by': '01', Linear: 'TODO-14', Branch: 'dev/todo-14-four', Base: '01',
    PR: '—', 'PR status': '—', Status: 'ready-for-agent',
  }),
  [`${S}/todo-2/tickets/be/01-x.md`]: ticket('01', '[backend] X', { 'Blocked by': 'None', Status: 'done' }),
  [`${S}/todo-2/tickets/be/02-y.md`]: ticket('02', '[backend] Y', { 'Blocked by': '01', Status: 'ready-for-agent' }),

  // main checkouts (FE_REPO / BE_REPO defaults under HOME)
  [`${HOME}/Workspace/my-frontend/.git/HEAD`]: 'ref: refs/heads/dev/TODO-1-thing\n',
  [`${HOME}/Workspace/my-backend/.git/HEAD`]: 'ref: refs/heads/main\n',

  // FE dev servers
  [`${WT}/todo-2-fe/.shots/.fe-url`]: 'http://localhost:3000\n',
  [`${WT}/todo-1-fe/.shots/.fe-url`]: 'http://localhost:5210\n',
}

// Directories implied by the files, plus the worktrees themselves.
const DIRS = new Set<string>([`${WT}/todo-1-fe`, `${WT}/todo-2-fe`, `${WT}/todo-3-be`])
for (const f of Object.keys(FILES)) {
  const parts = f.split('/')
  for (let i = 2; i < parts.length; i++) DIRS.add(parts.slice(0, i).join('/'))
}

export function list(path: string) {
  const prefix = path.replace(/\/$/, '') + '/'
  const names = new Map<string, 'file' | 'dir'>()
  for (const f of Object.keys(FILES)) if (f.startsWith(prefix)) {
    const rest = f.slice(prefix.length)
    names.set(rest.split('/')[0], rest.includes('/') ? 'dir' : 'file')
  }
  for (const d of DIRS) if (d.startsWith(prefix) && !d.slice(prefix.length).includes('/')) names.set(d.slice(prefix.length), 'dir')
  return [...names].map(([name, kind]) => ({ name, kind, size: 0, mtimeMs: 0, isLink: false }))
}

export const exists = (path: string) => path in FILES || DIRS.has(path.replace(/\/$/, ''))
