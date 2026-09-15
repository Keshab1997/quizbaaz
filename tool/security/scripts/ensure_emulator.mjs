// Starts the local Firestore emulator (headless) if it is not already
// listening on FIRESTORE_EMULATOR_PORT, and waits until it is ready.
import { spawn } from 'node:child_process';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..', '..', '..');
const port = Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080);

// The latest Firestore emulator needs JDK 21. Prefer an explicit JDK 21
// install (JAVA_HOME_21 or the sandbox default) over an older system JDK.
const jdk21 = process.env.JAVA_HOME_21 ?? (os.platform() === 'linux' ? '/var/tmp/jdk21' : null);
const env = { ...process.env };
if (jdk21 && fs.existsSync(path.join(jdk21, 'bin', 'java'))) {
  env.JAVA_HOME = jdk21;
  env.PATH = `${path.join(jdk21, 'bin')}:${env.PATH ?? ''}`;
}

function portOpen(p) {
  return new Promise((resolve) => {
    const sock = new net.Socket();
    sock.once('connect', () => {
      sock.destroy();
      resolve(true);
    });
    sock.once('error', () => resolve(false));
    sock.connect(p, '127.0.0.1');
  });
}

async function main() {
  if (await portOpen(port)) {
    console.log(`[ensure_emulator] already listening on ${port}`);
    return;
  }
  console.log(`[ensure_emulator] starting Firestore emulator on ${port}…`);
  const proc = spawn(
    'npx',
    [
      '--yes',
      'firebase-tools@latest',
      'emulators:start',
      '--only',
      'firestore',
      '--project',
      'quizbaaz-740bd',
    ],
    {
      cwd: projectRoot,
      stdio: ['ignore', 'inherit', 'inherit'],
      env: { ...env, FIRESTORE_EMULATOR_HOST: `127.0.0.1:${port}` },
    },
  );
  proc.on('exit', (code) => {
    if (code !== null && code !== 0) process.exit(code);
  });

  // Wait up to 120 s for the emulator port.
  for (let i = 0; i < 120; i++) {
    if (await portOpen(port)) {
      console.log('[ensure_emulator] ready.');
      return;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  console.error('[ensure_emulator] timed out waiting for the emulator.');
  proc.kill('SIGTERM');
  process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
