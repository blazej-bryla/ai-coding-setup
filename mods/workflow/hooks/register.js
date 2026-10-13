// workflow mod: /work status band above the prompt, and /tickets /who /story.
// Read-only by design: reads files through $.fs and env through $.env; never
// writes, never touches tool calls or prompts, never calls the model.
// Plain JS (no JSX): trees are built with the global `h`.

import {
  feServers,
  headline,
  locate,
  paths,
  portLine,
  prLine,
  readTask,
  storyText,
  ticketsText,
  whoText,
} from './reader.js'

const REFRESH_MS = 20_000

// What reader.js reads through. `$` stays in this file (the engine follows it
// into same-file functions only); env names must be literals.
async function io($) {
  return {
    read: path => $.fs.read(path),
    list: path => $.fs.list(path),
    exists: path => $.fs.exists(path),
    cwd: () => $.session.cwd(),
    env: {
      HOME: await $.env.get('HOME'),
      AGENTS_CONFIG: await $.env.get('AGENTS_CONFIG'),
      WT_ROOT: await $.env.get('WT_ROOT'),
      FE_REPO: await $.env.get('FE_REPO'),
      BE_REPO: await $.env.get('BE_REPO'),
      WT_REMOTE_FE_PORT: await $.env.get('WT_REMOTE_FE_PORT'),
    },
  }
}

// The command's lines go to the transcript as a notice: shown to the person,
// never sent to the model, and no turn starts.
const say = ($, text) => {
  $.ui.log(text)
  return {}
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'tickets',
      description: 'Ticket frontier for this side: ready / blocked / done (no Claude turn)',
    })
    await $.command.register({
      name: 'who',
      description: 'Who holds the shared FE port and which task worktrees run a FE (no Claude turn)',
    })
    await $.command.register({
      name: 'story',
      description: 'Story mode: Linear id, branch, base, PR per ticket (no Claude turn)',
    })
    $.clock.every(REFRESH_MS, () => $.ui.invalidate('ui.render'))
    return next(e)
  })

  on('turn.complete', ($, e, next) => {
    if (e.agentId === undefined) $.ui.invalidate('ui.render')
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    let lines
    try {
      const fs = await io($)
      const loc = await locate(fs)
      if (!loc) return next(e)
      const task = await readTask(fs, loc)
      const servers = await feServers(fs, loc.paths)
      lines = [headline(task), [prLine(task), portLine(servers, loc.paths.remotePort)].filter(Boolean).join('        ')]
    } catch {
      return next(e)
    }
    const { Box, Text } = $.ui.resolve(e)
    return h(
      Box,
      { flexDirection: 'column' },
      h(Text, { wrap: 'truncate' }, lines[0]),
      h(Text, { dimColor: true, wrap: 'truncate' }, lines[1]),
    )
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'tickets' }, async $ => {
    try {
      const fs = await io($)
      const loc = await locate(fs)
      return say($, loc ? ticketsText(await readTask(fs, loc)) : 'tickets: no task here (not a task worktree or scratch dir)')
    } catch (err) {
      return say($, `tickets: ${err?.message ?? err}`)
    }
  })

  on('command.run', { command: 'who' }, async $ => {
    try {
      const fs = await io($)
      const p = await paths(fs)
      return say($, whoText(await feServers(fs, p), p.remotePort))
    } catch (err) {
      return say($, `who: ${err?.message ?? err}`)
    }
  })

  on('command.run', { command: 'story' }, async $ => {
    try {
      const fs = await io($)
      const loc = await locate(fs)
      return say($, loc ? storyText(await readTask(fs, loc)) : 'story: no task here (not a task worktree or scratch dir)')
    } catch (err) {
      return say($, `story: ${err?.message ?? err}`)
    }
  })
}
