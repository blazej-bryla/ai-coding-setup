import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { exists, FILES, HOME, list, WT } from './fixtures'

const SURFACES = ['terminal', 'desktop'] as const

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 10 },
  view: {},
}

// The world beneath the plugin: cwd, env and the fake disk. `missing` drops
// files whose path contains any of the given strings; reading a path that
// contains one of `unreadable` throws although the file is listed. `extra` adds files (e.g. a
// config file) on top of the fixtures.
function world(on: On, cwd: string, missing: string[] = [], unreadable: string[] = [], extra: Record<string, string> = {}) {
  const has = (p: string) => !missing.some(m => p.includes(m))
  mock.env(on, { HOME, WT_ROOT: WT })
  on('session.cwd', () => ({ value: cwd }))
  on('fs.exists', ($, e) => ({ value: e.path in extra || (has(e.path) && exists(e.path)) }))
  on('fs.list', ($, e) => ({ value: list(e.path).filter(x => has(`${e.path}/${x.name}`)) }))
  on('fs.read', ($, e) => {
    if (e.path in extra) return { value: extra[e.path] }
    if (!has(e.path) || !(e.path in FILES)) throw new Error(`ENOENT: ${e.path}`)
    if (unreadable.some(m => e.path.includes(m))) throw new Error(`EACCES: ${e.path}`)
    return { value: FILES[e.path] }
  })
  // What the engine draws when the plugin passes: an empty marked Box.
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return h(Box, { key: 'engine' })
  })
  const logs: string[] = []
  on('ui.log', ($, e) => {
    logs.push(e.text)
    return { value: undefined }
  })
  return logs
}

async function bandText($: any, surface: (typeof SURFACES)[number]) {
  const ui = await $.ui.mount({ plugin: 'workflow', surface, component: 'AbovePrompt', props: BAND })
  const texts = (await ui.findAll({ type: 'Text' })).map((t: any) => t.text)
  if (texts.length === 0) expect(await ui.find({ key: 'engine' })).toBeDefined()
  await ui.unmount()
  return texts
}

describe('panel', () => {
  for (const surface of SURFACES) {
    test(`non-task cwd draws nothing (${surface})`, async ($, on) => {
      world(on, `${HOME}/.agents`)
      expect(await bandText($, surface)).toEqual([])
    })

    test(`local mode (${surface})`, async ($, on) => {
      world(on, `${WT}/todo-1-fe/src`)
      const [head, second] = await bandText($, surface)
      expect(head).toBe('todo-1 · fe · local   tickets 1/3 done   wave: 02')
      expect(second).toBe(':3000 → todo-2-fe')
    })

    test(`story mode with PRs (${surface})`, async ($, on) => {
      world(on, `${WT}/todo-2-fe`)
      const [head, second] = await bandText($, surface)
      expect(head).toBe('todo-2 · fe · story   tickets 2/4 done   wave: 04   waiting: be/02')
      expect(second).toMatch(/^PRs: #1640 merged · #1641 draft\s+:3000 → todo-2-fe$/)
    })

    test(`main checkout on a task branch (${surface})`, async ($, on) => {
      world(on, `${HOME}/Workspace/my-frontend/src`)
      expect((await bandText($, surface))[0]).toBe('todo-1 · fe · local   tickets 1/3 done   wave: 02')
    })

    test(`main checkout without a scratch dir draws nothing (${surface})`, async ($, on) => {
      world(on, `${HOME}/Workspace/my-backend`)
      expect(await bandText($, surface)).toEqual([])
    })

    test(`missing files draw nothing, no throw (${surface})`, async ($, on) => {
      world(on, `${WT}/todo-2-fe`, ['context.md'])
      expect(await bandText($, surface)).toEqual([])
    })

    test(`unreadable ticket draws nothing (${surface})`, async ($, on) => {
      world(on, `${WT}/todo-2-fe`, [], ['02-b.md'])
      expect(await bandText($, surface)).toEqual([])
    })
  }
})

describe('commands', () => {
  test('/tickets lists the frontier without a turn', async ($, on) => {
    const logs = world(on, `${WT}/todo-2-fe`)
    const ran = await $.command.run({ command: 'tickets', args: '' })
    expect(ran.text).toBeUndefined()
    expect(logs[0].split('\n')).toEqual([
      'todo-2 · fe · story — 2/4 done',
      'ready    04  Four',
      'blocked  03  Three  — by be/02',
      'done     01  One',
      'done     02  Two',
    ])
  })

  test('/who lists FE servers from .fe-url files', async ($, on) => {
    const logs = world(on, `${HOME}/.agents`)
    await $.command.run({ command: 'who', args: '' })
    expect(logs[0]).toBe(':3000 → todo-2-fe\n:5210 → todo-1-fe')
  })

  test('/story lists PRs per ticket', async ($, on) => {
    const logs = world(on, `${WT}/todo-2-fe`)
    await $.command.run({ command: 'story', args: '' })
    expect(logs[0].split('\n')).toEqual([
      'todo-2 · fe · story',
      '01  TODO-11  dev/todo-11-one  base story  #1640 merged',
      '02  TODO-12  dev/todo-12-two  base 01  #1641 draft',
      '03  TODO-13  dev/todo-13-three  base 02  no PR',
      '04  TODO-14  dev/todo-14-four  base 01  no PR',
    ])
  })

  test('/who takes the shared port from the config file', async ($, on) => {
    const config = `# local values\nexport WT_REMOTE_FE_PORT='5210'   # remote API origin\nexport FE_REPO="$HOME/Workspace/my-frontend"\n`
    const logs = world(on, `${HOME}/.agents`, [], [], { [`${HOME}/.agents/config.local.zsh`]: config })
    await $.command.run({ command: 'who', args: '' })
    expect(logs[0]).toBe(':5210 → todo-1-fe\n:3000 → todo-2-fe')
  })

  test('/story in local mode says so', async ($, on) => {
    const logs = world(on, `${WT}/todo-1-fe`)
    await $.command.run({ command: 'story', args: '' })
    expect(logs[0]).toMatch(/mode local/)
  })

  test('/tickets outside a task says so', async ($, on) => {
    const logs = world(on, '/tmp/elsewhere')
    await $.command.run({ command: 'tickets', args: '' })
    expect(logs[0]).toMatch(/no task here/)
  })
})
