/**
 * dsh-unity-modkit — Unity asset unpacking + BepInEx plugin build tools for DeepSeek Harness.
 *
 * Registers host tools on ctx.tools:
 *   unity_unpack        tools/unpack.py (info | list | mats | export | zip)
 *   unity_build_plugin  tools/build-plugin.sh (optionally installs into the game)
 *   unity_scaffold      tools/new-plugin.sh (auto-detects IL2CPP vs Mono)
 *
 * @module dsh-unity-modkit
 */

import { spawn, spawnSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineTool } from '@deepseek-ai/dsh-tools'
import Schema from '@deepseek-ai/schemastery'

/** Package root: the directory that contains tools/ and lib/. */
const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/** Cordis plugin name. */
export const name = 'unity-modkit'

/** Service required by the tool consumer. */
export const inject = ['tools']

/** Deployment configuration; defaults mirror cordis.patch.yml. */
export const Config = Schema.object({
  /** Checkout containing tools/. Empty = this package's own directory. */
  toolkitDir: Schema.string().default(''),
  /** Default process timeout in milliseconds. */
  timeoutMs: Schema.number().default(600000),
  /** Characters of merged output kept in the result (head + tail). */
  outputChars: Schema.number().default(12000),
  /** Absolute path to bash. Empty = auto-detect. */
  bashPath: Schema.string().default(''),
  /** Absolute path to python. Empty = auto-detect. */
  pythonPath: Schema.string().default(''),
})

const OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    exitCode: { required: true, oneOf: [{ type: 'integer' }, { type: 'null' }] },
    signal: { required: true, oneOf: [{ type: 'string' }, { type: 'null' }] },
    timedOut: { type: 'boolean', required: true },
    aborted: { type: 'boolean', required: true },
    timeoutMs: { type: 'number', required: true },
    output: {
      type: 'object',
      additionalProperties: false,
      required: true,
      properties: {
        text: { type: 'string', required: true },
        truncated: { type: 'boolean', required: true },
      },
    },
  },
}

function renderResult(_args, value) {
  const prefix = value.timedOut ? '[timed out] ' : ''
  const status = value.exitCode === null ? 'signal ' + value.signal : 'exit ' + value.exitCode
  return [{ type: 'text', text: prefix + status + '\n\n' + value.output.text }]
}

function truncate(text, limit) {
  if (text.length <= limit) return { text, truncated: false }
  const head = Math.min(4000, Math.floor(limit / 3))
  return {
    text: text.slice(0, head) + '\n... [truncated] ...\n' + text.slice(-(limit - head)),
    truncated: true,
  }
}

/** Ask the OS where an executable is; returns null when missing. */
function which(exe) {
  try {
    const probe = process.platform === 'win32' ? ['where', [exe]] : ['which', [exe]]
    const out = spawnSync(probe[0], probe[1], { encoding: 'utf8', windowsHide: true })
    if (out.status !== 0) return null
    for (const line of String(out.stdout || '').split(/\r?\n/)) {
      const candidate = line.trim()
      if (candidate && existsSync(candidate)) return candidate
    }
  } catch { /* fall through */ }
  return null
}

/** Bounded search for the bash shipped by dsh-ops shell caches. */
function findDshOpsBash() {
  const roots = [
    join(homedir(), '.dsh'),
    'C:/Users/Public',
    'D:/DeePSeek',
  ]
  for (const root of roots) {
    for (const shellRoot of [join(root, 'dsh-ops', 'shells'), join(root, 'shells')]) {
      let entries
      try { entries = readdirSync(shellRoot) } catch { continue }
      for (const entry of entries) {
        const level1 = join(shellRoot, entry)
        const dirs = [level1]
        try {
          for (const sub of readdirSync(level1)) dirs.push(join(level1, sub))
        } catch { /* not a directory */ }
        for (const dir of dirs) {
          for (const rel of ['winuxcmd/bin/bash.exe', 'winuxcmd/usr/bin/bash.exe', 'bin/bash.exe', 'bash.exe']) {
            const candidate = join(dir, rel)
            if (existsSync(candidate)) return candidate
          }
        }
      }
    }
  }
  return null
}

function detectBash(config) {
  if (config.bashPath && existsSync(config.bashPath)) return config.bashPath
  if (process.env.BASH && existsSync(process.env.BASH)) return process.env.BASH
  const fromPath = which('bash')
  if (fromPath) return fromPath
  const candidates = [
    'C:/Program Files/Git/bin/bash.exe',
    'C:/Program Files/Git/usr/bin/bash.exe',
    'C:/Program Files (x86)/Git/bin/bash.exe',
  ]
  for (const candidate of candidates) if (existsSync(candidate)) return candidate
  return findDshOpsBash()
}

function detectPython(config) {
  if (config.pythonPath && existsSync(config.pythonPath)) return config.pythonPath
  if (process.env.PYTHON && existsSync(process.env.PYTHON)) return process.env.PYTHON
  const fromPath = which('python')
  if (fromPath) return fromPath
  const base = join(process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local'), 'Programs', 'Python')
  try {
    for (const entry of readdirSync(base)) {
      const candidate = join(base, entry, 'python.exe')
      if (existsSync(candidate)) return candidate
    }
  } catch { /* ignore */ }
  return null
}

function requireExecutable(path, label, hint) {
  if (path) return path
  throw new Error(
    label + ' not found. Set ' + label.toLowerCase() + 'Path in cordis.patch.yml, ' +
    'or install it: ' + hint,
  )
}

function requireScript(path, label) {
  if (!existsSync(path)) {
    throw new Error(
      label + ' is missing: ' + path + '\n' +
      'Point config.toolkitDir at a dsh-unity-modkit checkout that contains tools/.',
    )
  }
  return path
}

function killTree(child) {
  if (!child || child.killed) return
  if (process.platform === 'win32') {
    spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true })
  } else {
    try { child.kill('SIGKILL') } catch { /* ignore */ }
  }
}

function runProcess(command, args, options) {
  const timeoutMs = options.timeoutMs || 600000
  const outputChars = options.outputChars || 12000
  const base = {
    exitCode: null, signal: null, timedOut: false, aborted: false, timeoutMs,
  }
  return new Promise((resolvePromise) => {
    let child
    try {
      child = spawn(command, args, {
        cwd: options.cwd,
        env: { ...process.env, ...(options.env || {}) },
        windowsHide: true,
      })
    } catch (error) {
      resolvePromise({
        ...base,
        output: { text: '[spawn failed] ' + error.message + '\ncommand: ' + command, truncated: false },
      })
      return
    }

    let text = ''
    let timedOut = false
    let aborted = false
    let settled = false

    const finish = (code, signal) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      if (options.signal) options.signal.removeEventListener('abort', onAbort)
      resolvePromise({
        exitCode: code === undefined ? null : code,
        signal: signal === undefined ? null : signal,
        timedOut,
        aborted,
        timeoutMs,
        output: truncate(text, outputChars),
      })
    }

    const timer = setTimeout(() => { timedOut = true; killTree(child) }, timeoutMs)
    const onAbort = () => { aborted = true; killTree(child) }
    if (options.signal) {
      if (options.signal.aborted) { aborted = true; killTree(child) }
      else options.signal.addEventListener('abort', onAbort, { once: true })
    }

    child.stdout?.on('data', (chunk) => { text += chunk })
    child.stderr?.on('data', (chunk) => { text += chunk })
    child.on('error', (error) => { text += '\n[spawn error] ' + error.message + '\n' })
    child.on('close', (code, signal) => finish(code, signal))
  })
}

function toolkitRoot(config) {
  return config.toolkitDir && config.toolkitDir.trim()
    ? resolve(config.toolkitDir)
    : PACKAGE_ROOT
}

/** Register the unity-modkit tools. */
export function apply(ctx, config = {}) {
  const root = toolkitRoot(config)
  const scripts = {
    unpack: join(root, 'tools', 'unpack.py'),
    build: join(root, 'tools', 'build-plugin.sh'),
    scaffold: join(root, 'tools', 'new-plugin.sh'),
  }
  const bash = detectBash(config)
  const python = detectPython(config)
  const defaults = { timeoutMs: config.timeoutMs, outputChars: config.outputChars }

  ctx.tools.register(defineTool({
    name: 'unity_unpack',
    description: 'Unpack or inspect Unity assets with dsh-unity-modkit. '
      + 'action=info: detect bundle type/encryption + object census. '
      + 'action=list: resource names. action=mats: materials and their shaders. '
      + 'action=export: write assets (default Texture2D) to a directory. '
      + 'action=zip: package an exported directory into a .zip. '
      + 'Encrypted bundles are reported, never brute-forced; pass "key" only if you own it.',
    parameters: {
      action: { type: 'string', required: true, enum: ['info', 'list', 'mats', 'export', 'zip'], description: 'info | list | mats | export | zip.' },
      src: { type: 'string', description: 'Bundle file, .assets file, or *_Data directory. Required for info/list/mats/export.' },
      out: { type: 'string', description: 'Output directory (action=export).' },
      keyword: { type: 'string', description: 'Filter asset names (case-insensitive).' },
      type: { type: 'string', description: 'Comma-separated object types, e.g. Texture2D,AudioClip. Default Texture2D.' },
      key: { type: 'string', description: 'Decryption key (hex or string) for encrypted bundles.' },
      limit: { type: 'number', description: 'list: max rows (default 300, 0 = unlimited).' },
      outZip: { type: 'string', description: 'zip: archive path to create.' },
      dir: { type: 'string', description: 'zip: directory to package.' },
      toDesktop: { type: 'boolean', description: 'zip: put the archive on the Desktop when outZip is relative.' },
    },
    output: { schema: OUTPUT_SCHEMA, render: renderResult },
    execute(args, exec) {
      const action = args.action
      if (action !== 'zip' && !args.src) throw new Error('src is required for action=' + action)
      if (action === 'export' && !args.out) throw new Error('out is required for action=export')
      if (action === 'zip' && (!args.outZip || !args.dir)) throw new Error('outZip and dir are required for action=zip')

      const py = requireScript(scripts.unpack, 'unpack.py')
      const exe = requireExecutable(python, 'python', 'https://www.python.org/downloads/')
      const argv = [py, action]

      if (action === 'info' || action === 'mats') {
        argv.push('-s', args.src)
      } else if (action === 'list') {
        argv.push('-s', args.src)
        if (args.type) argv.push('-t', args.type)
        if (args.keyword) argv.push('-k', args.keyword)
        if (args.limit !== undefined) argv.push('--limit', String(args.limit))
      } else if (action === 'export') {
        argv.push(args.out, '-s', args.src)
        if (args.type) argv.push('-t', args.type)
        if (args.keyword) argv.push('-k', args.keyword)
      } else if (action === 'zip') {
        argv.push(args.outZip, '-d', args.dir)
        if (args.toDesktop) argv.push('--to-desktop')
      }
      if (args.key) argv.push('--key', args.key)

      return runProcess(exe, argv, { ...defaults, cwd: root, signal: exec.signal })
    },
  }))

  ctx.tools.register(defineTool({
    name: 'unity_build_plugin',
    description: 'Build a BepInEx plugin project with dsh-unity-modkit. '
      + 'Runs tools/build-plugin.sh with the redirected dotnet environment '
      + '(NuGet caches kept out of %APPDATA%, so restore never hits an ACL denial). '
      + 'install=true copies the built DLL into <gameDir>/BepInEx/plugins/ after a successful build.',
    parameters: {
      projectDir: { type: 'string', required: true, description: 'Plugin project directory containing a .csproj.' },
      gameDir: { type: 'string', required: true, description: 'Game root containing BepInEx/ (reference paths + optional install).' },
      install: { type: 'boolean', description: 'Copy the built DLL into <gameDir>/BepInEx/plugins/ on success.' },
      extraArgs: { type: 'array', items: { type: 'string' }, description: 'Extra arguments appended to the build script.' },
    },
    output: { schema: OUTPUT_SCHEMA, render: renderResult },
    execute(args, exec) {
      const script = requireScript(scripts.build, 'build-plugin.sh')
      const exe = requireExecutable(bash, 'bash', 'https://git-scm.com/download/win')
      const argv = [script, args.projectDir]
      if (args.install) argv.push('--install', args.gameDir)
      if (Array.isArray(args.extraArgs)) argv.push(...args.extraArgs)
      return runProcess(exe, argv, {
        ...defaults,
        cwd: root,
        env: { GAME_DIR: args.gameDir },
        signal: exec.signal,
      })
    },
  }))

  ctx.tools.register(defineTool({
    name: 'unity_scaffold',
    description: 'Scaffold a BepInEx plugin project from dsh-unity-modkit templates. '
      + 'Auto-detects IL2CPP (GameAssembly.dll / BepInEx/interop) versus Mono and writes '
      + 'a ready-to-build csproj plus Plugin.cs.',
    parameters: {
      targetDir: { type: 'string', required: true, description: 'Directory to create the project in.' },
      name: { type: 'string', required: true, description: 'Plugin/assembly name, e.g. MyMod.' },
      gameDir: { type: 'string', required: true, description: 'Game root containing BepInEx/.' },
      guid: { type: 'string', description: 'Plugin GUID; defaults to com.example.<lowercased name>.' },
    },
    output: { schema: OUTPUT_SCHEMA, render: renderResult },
    execute(args, exec) {
      const script = requireScript(scripts.scaffold, 'new-plugin.sh')
      const exe = requireExecutable(bash, 'bash', 'https://git-scm.com/download/win')
      const argv = [script, args.targetDir, args.name, args.gameDir]
      if (args.guid) argv.push(args.guid)
      return runProcess(exe, argv, { ...defaults, cwd: root, signal: exec.signal })
    },
  }))
}

/** Exported for tests and diagnostics. */
export function describeEnvironment(config = {}) {
  const root = toolkitRoot(config)
  return {
    root,
    bash: detectBash(config),
    python: detectPython(config),
    scripts: {
      unpack: join(root, 'tools', 'unpack.py'),
      build: join(root, 'tools', 'build-plugin.sh'),
      scaffold: join(root, 'tools', 'new-plugin.sh'),
    },
  }
}
