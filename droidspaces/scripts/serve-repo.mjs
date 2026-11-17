#!/usr/bin/env node
/**
 * Read-only HTTP publisher for the repository the container hosts.
 *
 * It serves the repository tree, a JSON index of the directories it holds, and
 * a status document that names the harness build the container runs. The
 * server never writes, never follows a symbolic link out of the tree, and
 * refuses any path that resolves outside the published root.
 *
 * Usage: serve-repo.mjs --root <directory> [--port <port>]
 */

import { createReadStream } from 'node:fs'
import { lstat, readdir, readFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { join, relative, resolve, sep } from 'node:path'

function parseArguments(argv) {
  const options = { root: process.cwd(), port: 8080 }
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    if (argument === '--root') {
      options.root = argv[index + 1]
      index += 1
    } else if (argument === '--port') {
      options.port = Number(argv[index + 1])
      index += 1
    } else {
      throw new Error(`unknown argument: ${argument}`)
    }
  }
  options.root = resolve(options.root)
  if (!Number.isInteger(options.port) || options.port < 0 || options.port > 65535) {
    throw new Error(`invalid port: ${options.port}`)
  }
  return options
}

const contentTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.md', 'text/markdown; charset=utf-8'],
  ['.txt', 'text/plain; charset=utf-8'],
  ['.yml', 'text/yaml; charset=utf-8'],
  ['.yaml', 'text/yaml; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.ts', 'text/plain; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.png', 'image/png'],
])

function contentTypeFor(filePath) {
  const dot = filePath.lastIndexOf('.')
  return dot === -1 ? 'application/octet-stream' : contentTypes.get(filePath.slice(dot)) ?? 'application/octet-stream'
}

function escapeHtml(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;')
}

/** Resolve a request path inside the published root, or report that it escapes. */
function resolveInside(root, requestPath) {
  const decoded = decodeURIComponent(requestPath.split('?')[0])
  const candidate = resolve(root, `.${decoded.startsWith('/') ? decoded : `/${decoded}`}`)
  if (candidate !== root && !candidate.startsWith(root + sep)) {
    return null
  }
  return candidate
}

async function readStatus(root) {
  let commit = null
  try {
    commit = (await readFile(join(root, '.dsh-commit'), 'utf8')).trim()
  } catch {
    commit = null
  }
  return {
    repository: root,
    commit,
    node: process.version,
    platform: process.platform,
    architecture: process.arch,
    uptime_seconds: Math.round(process.uptime()),
  }
}

async function directoryListing(root, directory, requestPath) {
  const entries = await readdir(directory, { withFileTypes: true })
  const prefix = requestPath.endsWith('/') ? requestPath : `${requestPath}/`
  const rows = entries
    .filter(entry => entry.isDirectory() || entry.isFile())
    .sort((left, right) => {
      if (left.isDirectory() !== right.isDirectory()) {
        return left.isDirectory() ? -1 : 1
      }
      return left.name.localeCompare(right.name)
    })
    .map(entry => {
      const name = `${entry.name}${entry.isDirectory() ? '/' : ''}`
      const size = entry.isFile() ? ` — ${entry.size} bytes` : ''
      return `<li><a href="${escapeHtml(prefix + name)}">${escapeHtml(name)}</a>${size}</li>`
    })
    .join('\n')
  const title = escapeHtml(`${prefix} — ${root}`)
  return `<!doctype html>\n<html lang="en">\n<head><meta charset="utf-8"><title>${title}</title></head>\n<body>\n<h1>${title}</h1>\n<ul>\n${rows}\n</ul>\n</body>\n</html>\n`
}

const options = parseArguments(process.argv.slice(2))

const server = createServer((request, response) => {
  const requestPath = request.url ?? '/'
  if (requestPath === '/status.json') {
    readStatus(options.root).then(
      status => {
        response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' })
        response.end(`${JSON.stringify(status, null, 2)}\n`)
      },
      error => {
        response.writeHead(500, { 'content-type': 'application/json; charset=utf-8' })
        response.end(`${JSON.stringify({ error: String(error) })}\n`)
      },
    )
    return
  }

  const target = resolveInside(options.root, requestPath)
  if (target === null) {
    response.writeHead(403, { 'content-type': 'text/plain; charset=utf-8' })
    response.end('the requested path is outside the published tree\n')
    return
  }

  lstat(target).then(
    stats => {
      if (stats.isSymbolicLink()) {
        response.writeHead(403, { 'content-type': 'text/plain; charset=utf-8' })
        response.end('symbolic links are not published\n')
        return
      }
      if (stats.isDirectory()) {
        directoryListing(options.root, target, requestPath).then(
          listing => {
            response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' })
            response.end(listing)
          },
          error => {
            response.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' })
            response.end(`${String(error)}\n`)
          },
        )
        return
      }
      response.writeHead(200, {
        'content-type': contentTypeFor(target),
        'content-length': stats.size,
        'last-modified': stats.mtime.toUTCString(),
      })
      createReadStream(target).pipe(response)
    },
    error => {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
      response.end(`${relative(options.root, target)}: ${String(error)}\n`)
    },
  )
})

server.listen(options.port, '0.0.0.0', () => {
  process.stdout.write(`[droidspaces] repository http server on port ${options.port} serving ${options.root}\n`)
})
