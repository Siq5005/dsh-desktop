/**
 * Headless web-profile smoke: boots the REAL web profile (the one the GUI
 * uses, real ~/.dsh home) with the current core, then asserts the web server
 * serves index.html through the launch-token handshake.
 *
 * Why this exists: the desktop-profile smoke only covered the shell's own
 * composition. Plugin client bundles (e.g. @linxin666/dsh-client-ui-skin-center)
 * link against host APIs at boot; a removed export (like
 * installSettingsSection in @deepseek-ai/dsh-settings >= 0.1.2-rc.1) crashes
 * the whole boot. That only shows up when the REAL web profile is booted.
 *
 * Run (any core; must be launched from a dsh-desktop checkout):
 *   DSH_DESKTOP_PROFILE=web node --expose-internals scripts/smoke-web-profile.mjs
 *
 * Uses the real ~/.dsh home so it validates the exact plugin set the GUI runs.
 * Binds 127.0.0.1:0 (ephemeral port) and disposes the boot afterwards; it does
 * not open a browser and does not start agent turns.
 */

import { bootHost } from '../src/host.js'

const PROFILE_NAME = process.env.DSH_DESKTOP_PROFILE ?? 'web'

const scheduled = { spec: undefined }
const stubRuntime = {
  schedule(spec) {
    scheduled.spec = spec
    return () => {}
  },
}
const stubProfiles = {
  list: async () => [{ name: 'desktop', dir: '' }, { name: 'web', dir: '' }],
  select: async () => {},
}

console.log('smoke-web-profile: booting real profile:', PROFILE_NAME)

const { ctx, profile, releaseResolver } = await bootHost({
  profileName: PROFILE_NAME,
  desktopRuntime: stubRuntime,
  desktopProfiles: stubProfiles,
  exit: () => {},
  onPrepare: () => {},
})

try {
  const webServer = ctx.get('webServer')
  const spec = scheduled.spec
  console.log('profile:', profile.name, '->', profile.dir)
  console.log('webServer.host:', webServer.host, 'port:', webServer.port)
  if (spec === undefined) throw new Error('desktop-shell did not schedule a window')
  if (!spec.url.includes('127.0.0.1')) throw new Error('scheduled url is not loopback: ' + spec.url)

  // 0.1.2-rc.1 mints a browser cookie from the launch token (303 -> clean /).
  const handshake = await fetch(spec.url, { redirect: 'manual' })
  const setCookie = handshake.headers.get('set-cookie')
  console.log('token handshake:', handshake.status, 'set-cookie:', setCookie === null ? 'no' : 'yes')
  if (handshake.status !== 303 || setCookie === null) {
    throw new Error('launch-token handshake failed: ' + handshake.status)
  }
  const res = await fetch(`http://127.0.0.1:${webServer.port}/`, {
    headers: { cookie: setCookie.split(';')[0] },
  })
  const text = await res.text()
  console.log('fetch:', res.status, 'bytes:', text.length)
  console.log('html marker:', /<!doctype html|<html/i.test(text) ? 'yes' : 'no')
  if (res.status !== 200) throw new Error('web UI returned ' + res.status)
  console.log('OK: web profile booted with a live loopback web UI (plugin client bundles linked cleanly)')
} finally {
  await ctx.fiber.dispose()
  releaseResolver()
}