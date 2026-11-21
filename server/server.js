const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const { spawn, execFile, exec } = require('child_process');
const { WebSocketServer } = require('ws');

const PORT = 3000;
const ADB_TUNNEL_PORT = 5556;
const ROOT_DIR = path.resolve(__dirname, '..');
const BIN_DIR = path.join(ROOT_DIR, 'bin', 'scrcpy');
const ADB_PATH = path.join(BIN_DIR, 'adb.exe');
const SCRCPY_PATH = path.join(BIN_DIR, 'scrcpy.exe');
const SETTINGS_PATH = path.join(ROOT_DIR, 'settings.ini');
const PATTERN_PATH = path.join(ROOT_DIR, 'pattern.txt');
const PUBLIC_DIR = path.join(__dirname, 'public');

let activeScrcpyProcess = null;
let activeTunnelWs = null;
let activeTcpSocket = null;

// Read settings.ini
function getSetting(section, key, defaultValue = '') {
  try {
    if (!fs.existsSync(SETTINGS_PATH)) return defaultValue;
    const content = fs.readFileSync(SETTINGS_PATH, 'utf8');
    let currentSec = '';
    for (const rawLine of content.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSec = line.slice(1, -1).trim();
      } else if (currentSec === section && line.startsWith(`${key}=`)) {
        return line.slice(key.length + 1).trim();
      }
    }
  } catch (e) {
    console.error('Error reading settings.ini:', e.message);
  }
  return defaultValue;
}

// Fast TCP connect test
function testTcpPort(host, port, timeoutMs = 400) {
  return new Promise((resolve) => {
    const s = new net.Socket();
    let resolved = false;
    s.setTimeout(timeoutMs);
    s.once('connect', () => {
      resolved = true;
      s.destroy();
      resolve(true);
    });
    s.once('timeout', () => {
      s.destroy();
      if (!resolved) resolve(false);
    });
    s.once('error', () => {
      s.destroy();
      if (!resolved) resolve(false);
    });
    s.connect(port, host);
  });
}

// Execute ADB command safely
function runAdb(args) {
  return new Promise((resolve, reject) => {
    execFile(ADB_PATH, args, { windowsHide: true, timeout: 10000 }, (err, stdout, stderr) => {
      if (err) resolve({ success: false, stdout: stdout || '', stderr: stderr || err.message });
      else resolve({ success: true, stdout: stdout || '', stderr: stderr || '' });
    });
  });
}

let cachedGateway = null;
let lastGwCheckTime = 0;

async function getCachedGateway() {
  const now = Date.now();
  if (cachedGateway !== null && (now - lastGwCheckTime < 10000)) {
    return cachedGateway;
  }
  lastGwCheckTime = now;
  try {
    const gw = await new Promise((resolve) => {
      exec(`route print 0.0.0.0`, { windowsHide: true }, (err, stdout) => {
        if (!stdout) return resolve('');
        const lines = stdout.split(/\r?\n/);
        for (const line of lines) {
          const parts = line.trim().split(/\s+/);
          if (parts[0] === '0.0.0.0' && parts[1] === '0.0.0.0' && parts[2]) {
            return resolve(parts[2]);
          }
        }
        resolve('');
      });
    });
    cachedGateway = gw;
    return gw;
  } catch (e) {
    return '';
  }
}

// Find best reachable phone target (USB -> Direct Hotspot -> Wi-Fi -> Cloud Tunnel)
async function findPhoneTarget() {
  // 1. Check USB devices attached
  const devRes = await runAdb(['devices', '-l']);
  const lines = devRes.stdout.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('List of'));
  
  for (const line of lines) {
    const parts = line.split(/\s+/);
    const serial = parts[0];
    const state = parts[1];
    if (state === 'device' && !serial.includes(':')) {
      return { target: serial, type: 'USB Cable (Direct)', isLocal: true };
    }
  }

  // 2. Check Hotspot Default Gateway (e.g. 10.38.115.80:5555 or 192.168.43.1:5555)
  try {
    const gw = await getCachedGateway();
    if (gw && gw !== '192.168.1.1' && gw !== '0.0.0.0') {
      const open = await testTcpPort(gw, 5555, 300);
      if (open) {
        await runAdb(['connect', `${gw}:5555`]);
        return { target: `${gw}:5555`, type: 'Mobile Hotspot Gateway (2ms)', isLocal: true };
      }
    }
  } catch (e) {}

  // 3. Check 192.168.43.1 standard Android hotspot
  if (await testTcpPort('192.168.43.1', 5555, 300)) {
    await runAdb(['connect', '192.168.43.1:5555']);
    return { target: '192.168.43.1:5555', type: 'Android Hotspot Gateway (192.168.43.1)', isLocal: true };
  }

  // 4. Check active wireless targets already in adb table
  for (const line of lines) {
    const parts = line.split(/\s+/);
    const serial = parts[0];
    const state = parts[1];
    if (state === 'device' && serial.includes(':')) {
      const [ip, portStr] = serial.split(':');
      if (await testTcpPort(ip, parseInt(portStr, 10), 350)) {
        return { target: serial, type: `Wireless ADB (${serial})`, isLocal: true };
      }
    }
  }

  // 5. Check Cloud WebRTC ADB Tunnel (localhost:5556) only if active
  if (activeTunnelWs && activeTunnelWs.readyState === 1) {
    return { target: `127.0.0.1:${ADB_TUNNEL_PORT}`, type: 'Firebase Cloud P2P Tunnel (Remote 5G)', isLocal: false };
  }

  return null;
}

// Perform automated phone unlock
async function performUnlock(target) {
  const serialArgs = target ? ['-s', target] : [];
  console.log(`[Unlock] Initiating unlock for target: ${target || 'default'}`);

  // 1. Wake screen
  await runAdb([...serialArgs, 'shell', 'input', 'keyevent', '224']);
  await new Promise(r => setTimeout(r, 200));

  // 2. Dismiss fingerprint / bring up bouncer
  await runAdb([...serialArgs, 'shell', 'input', 'keyevent', '82']);
  await new Promise(r => setTimeout(r, 350));
  await runAdb([...serialArgs, 'shell', 'input', 'swipe', '540', '1800', '540', '500', '150']);
  await new Promise(r => setTimeout(r, 450));

  // 3. Inject pattern vector 159873 via unlock.sh
  const unlockSh = path.join(ROOT_DIR, 'core', 'unlock.sh');
  if (fs.existsSync(unlockSh)) {
    await runAdb([...serialArgs, 'push', unlockSh, '/data/local/tmp/unlock.sh']);
    await runAdb([...serialArgs, 'shell', 'chmod', '+x', '/data/local/tmp/unlock.sh']);
    await runAdb([...serialArgs, 'shell', 'sh', '/data/local/tmp/unlock.sh']);
  } else {
    // Direct shell motionevent stroke
    const strokeCmd = `
sendevent /dev/input/event2 3 57 1
sendevent /dev/input/event2 3 53 247; sendevent /dev/input/event2 3 54 1163; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 540; sendevent /dev/input/event2 3 54 1456; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 833; sendevent /dev/input/event2 3 54 1750; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 540; sendevent /dev/input/event2 3 54 1750; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 247; sendevent /dev/input/event2 3 54 1750; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 540; sendevent /dev/input/event2 3 54 1456; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 53 833; sendevent /dev/input/event2 3 54 1163; sendevent /dev/input/event2 0 0 0
sleep 0.05
sendevent /dev/input/event2 3 57 -1; sendevent /dev/input/event2 0 0 0
`;
    await runAdb([...serialArgs, 'shell', strokeCmd]);
  }

  // 4. Verify status
  const check = await runAdb([...serialArgs, 'shell', 'dumpsys', 'window', 'policy']);
  const unlocked = check.stdout.includes('mKeyguardUnlocked=true') || check.stdout.includes('showing=false');
  console.log(`[Unlock] Result: ${unlocked ? 'SUCCESS' : 'ATTEMPTED'}`);
  return { success: unlocked };
}

// Remotely turn on hotspot
async function turnOnHotspot(target) {
  const serialArgs = target ? ['-s', target] : [];
  console.log(`[Hotspot] Enabling hotspot on target: ${target || 'default'}`);

  // Wake and unlock
  try {
    await performUnlock(target);
  } catch (e) {}
  await new Promise(r => setTimeout(r, 400));

  // Method 1: Android shell command
  try {
    await runAdb([...serialArgs, 'shell', 'cmd', 'connectivity', 'set-wifi-tethering', 'enabled']);
  } catch (e) {}

  // Method 2: Launch Tether Settings & tap switch at (948, 1066)
  try {
    await runAdb([...serialArgs, 'shell', 'am', 'start', '-a', 'android.settings.TETHER_SETTINGS']);
    await new Promise(r => setTimeout(r, 800));
    await runAdb([...serialArgs, 'shell', 'input', 'tap', '948', '1066']);
    await new Promise(r => setTimeout(r, 800));
    await runAdb([...serialArgs, 'shell', 'input', 'keyevent', '3']);
  } catch (e) {}

  return { success: true };
}

// Start Scrcpy Mirroring Session
async function startMirroring({ screenOff = true, target = null }) {
  if (activeScrcpyProcess && !activeScrcpyProcess.killed) {
    return { success: true, message: 'Scrcpy is already running.', pid: activeScrcpyProcess.pid };
  }

  let phone = null;
  if (target) {
    phone = { target, type: 'Selected Target', isLocal: true };
  } else {
    phone = await findPhoneTarget();
  }

  if (!phone) {
    throw new Error('No phone detected. Please connect USB cable or connect PC Wi-Fi to phone hotspot.');
  }

  const serial = phone.target;
  const serialArgs = ['-s', serial];

  // 1. Auto-unlock phone
  try {
    await performUnlock(serial);
  } catch (e) {
    console.warn('[Mirror] Auto-unlock warning:', e.message);
  }

  // 2. Enable 3-button navigation overlay for convenient PC mouse controls
  try {
    await runAdb([...serialArgs, 'shell', 'cmd', 'overlay', 'disable', 'com.android.internal.systemui.navbar.gestural']);
    await runAdb([...serialArgs, 'shell', 'cmd', 'overlay', 'enable', 'com.android.internal.systemui.navbar.threebutton']);
    await runAdb([...serialArgs, 'shell', 'settings', 'put', 'secure', 'navigation_mode', '0']);
  } catch (e) {}

  // 3. Assemble Scrcpy arguments
  const scrcpyArgs = [
    '-s', serial,
    '--window-title=Nothing-Connect',
    '--stay-awake',
    '--power-off-on-close'
  ];

  if (screenOff) {
    scrcpyArgs.push('--turn-screen-off');
  }

  if (phone.isLocal) {
    scrcpyArgs.push('--max-fps=120', '--video-codec=h265', '--video-bit-rate=16M');
  } else {
    scrcpyArgs.push('--max-fps=60', '--video-codec=h264', '--video-bit-rate=4M');
  }

  console.log(`[Scrcpy] Launching: ${SCRCPY_PATH} ${scrcpyArgs.join(' ')}`);

  const child = spawn(SCRCPY_PATH, scrcpyArgs, {
    cwd: BIN_DIR,
    detached: false,
    stdio: 'ignore',
    windowsHide: false
  });

  activeScrcpyProcess = child;

  child.on('exit', async (code) => {
    console.log(`[Scrcpy] Mirror window closed with code ${code}. Restoring phone state...`);
    activeScrcpyProcess = null;

    // Put screen to sleep safely without power toggle
    try {
      await runAdb([...serialArgs, 'shell', 'input', 'keyevent', '223']);
    } catch (e) {}

    // Restore gesture navigation
    try {
      await runAdb([...serialArgs, 'shell', 'cmd', 'overlay', 'disable', 'com.android.internal.systemui.navbar.threebutton']);
      await runAdb([...serialArgs, 'shell', 'cmd', 'overlay', 'enable', 'com.android.internal.systemui.navbar.gestural']);
      await runAdb([...serialArgs, 'shell', 'settings', 'put', 'secure', 'navigation_mode', '2']);
    } catch (e) {}
  });

  return { success: true, target: serial, type: phone.type, pid: child.pid };
}

// Setup local TCP server for ADB bridge over WebRTC (port 5556)
const adbTcpServer = net.createServer((socket) => {
  console.log('[Tunnel] Scrcpy/ADB client connected to 127.0.0.1:5556');
  activeTcpSocket = socket;

  socket.on('data', (chunk) => {
    if (activeTunnelWs && activeTunnelWs.readyState === 1) { // OPEN
      activeTunnelWs.send(chunk);
    }
  });

  socket.on('close', () => {
    console.log('[Tunnel] Local ADB TCP socket closed.');
    if (activeTcpSocket === socket) activeTcpSocket = null;
  });

  socket.on('error', (err) => {
    console.warn('[Tunnel] Local ADB TCP error:', err.message);
  });
});

adbTcpServer.listen(ADB_TUNNEL_PORT, '127.0.0.1', () => {
  console.log(`[Tunnel] Local ADB bridge server listening on 127.0.0.1:${ADB_TUNNEL_PORT}`);
});

// Setup HTTP Server & WebSocket
const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // --- API Routes ---
  if (pathname === '/api/status') {
    (async () => {
      try {
        const adbRes = await runAdb(['devices', '-l']);
        const lines = adbRes.stdout.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('List of'));
        const devices = lines.map(line => {
          const parts = line.split(/\s+/);
          return { serial: parts[0], state: parts[1], details: parts.slice(2).join(' ') };
        });

        const phone = await findPhoneTarget();

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          status: 'ok',
          isScrcpyRunning: !!(activeScrcpyProcess && !activeScrcpyProcess.killed),
          scrcpyPid: activeScrcpyProcess ? activeScrcpyProcess.pid : null,
          devices,
          activeTarget: phone,
          tunnelConnected: !!(activeTunnelWs && activeTunnelWs.readyState === 1)
        }));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    })();
    return;
  }

  if (pathname === '/api/mirror' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = body ? JSON.parse(body) : {};
        const result = await startMirroring({
          screenOff: data.mode !== 'screen-on',
          target: data.target || null
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  if (pathname === '/api/unlock' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = body ? JSON.parse(body) : {};
        const phone = data.target ? { target: data.target } : await findPhoneTarget();
        if (!phone) throw new Error('No phone detected. Plug in your USB cable or connect to the phone Wi-Fi hotspot.');
        const result = await performUnlock(phone.target);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  if (pathname === '/api/hotspot' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', async () => {
      try {
        const data = body ? JSON.parse(body) : {};
        const phone = data.target ? { target: data.target } : await findPhoneTarget();
        if (!phone) throw new Error('No phone detected. Plug in your USB cable once, or tap Hotspot on your phone to connect.');
        const result = await turnOnHotspot(phone.target);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  if (pathname === '/api/connect-tunnel' && req.method === 'POST') {
    try {
      const adbRes = await runAdb(['connect', `127.0.0.1:${ADB_TUNNEL_PORT}`]);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, target: `127.0.0.1:${ADB_TUNNEL_PORT}`, output: adbRes.stdout.trim() }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  if (pathname === '/api/kill-stream' && req.method === 'POST') {
    if (activeScrcpyProcess) {
      try {
        process.kill(activeScrcpyProcess.pid);
      } catch (e) {}
      activeScrcpyProcess = null;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'Stream stopped.' }));
    return;
  }

  // --- Static Files ---
  let filePath = path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname);
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(PUBLIC_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
  };

  const contentType = mimeTypes[ext] || 'application/octet-stream';
  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    }
  });
});

// Setup WebSocket server on /ws-tunnel
const wss = new WebSocketServer({ server, path: '/ws-tunnel' });

wss.on('connection', (ws) => {
  console.log('[WebSocket] Browser WebRTC adb-bridge tunnel connected!');
  activeTunnelWs = ws;

  ws.on('message', (data) => {
    if (activeTcpSocket && !activeTcpSocket.destroyed) {
      activeTcpSocket.write(data);
    }
  });

  ws.on('close', () => {
    console.log('[WebSocket] Browser WebRTC tunnel disconnected.');
    if (activeTunnelWs === ws) activeTunnelWs = null;
  });

  ws.on('error', (e) => {
    console.warn('[WebSocket] Tunnel error:', e.message);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=================================================`);
  console.log(`   NOTHING LINK MASTER CLOUD DASHBOARD`);
  console.log(`   URL: http://localhost:${PORT}`);
  console.log(`   ADB Bridge Port: ${ADB_TUNNEL_PORT}`);
  console.log(`=================================================`);
});
