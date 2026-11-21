import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.0/firebase-app.js';
import { 
  getAuth, 
  signInWithEmailAndPassword, 
  signOut, 
  onAuthStateChanged 
} from 'https://www.gstatic.com/firebasejs/10.14.0/firebase-auth.js';
import { 
  getFirestore, 
  collection, 
  doc, 
  onSnapshot, 
  setDoc, 
  serverTimestamp 
} from 'https://www.gstatic.com/firebasejs/10.14.0/firebase-firestore.js';

// --- 1. Firebase Cloud Setup ---
const firebaseConfig = {
  projectId: "nothing-link-cloud",
  appId: "1:899067968175:web:7157c878fc5ee8edfc725a",
  storageBucket: "nothing-link-cloud.firebasestorage.app",
  apiKey: "AIzaSyDoBxPq7OEohKqr7PTGqycmvo8fLebFzdA",
  authDomain: "nothing-link-cloud.firebaseapp.com",
  messagingSenderId: "899067968175",
  projectNumber: "899067968175"
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

// DOM Elements
const userPill = document.getElementById('userPill');
const userEmailText = document.getElementById('userEmailText');
const logoutBtn = document.getElementById('logoutBtn');
const authCard = document.getElementById('authCard');
const loginForm = document.getElementById('loginForm');
const authEmail = document.getElementById('authEmail');
const authPassword = document.getElementById('authPassword');
const authErrorMsg = document.getElementById('authErrorMsg');

const connPill = document.getElementById('connPill');
const connDot = document.getElementById('connDot');
const connText = document.getElementById('connText');

const deviceIndicator = document.getElementById('deviceIndicator');
const deviceTitle = document.getElementById('deviceTitle');
const deviceSub = document.getElementById('deviceSub');
const statusBadge = document.getElementById('statusBadge');
const specConnection = document.getElementById('specConnection');
const specMode = document.getElementById('specMode');
const specChannel = document.getElementById('specChannel');

const btnHotspot = document.getElementById('btnHotspot');
const btnMirrorOff = document.getElementById('btnMirrorOff');
const btnMirrorOn = document.getElementById('btnMirrorOn');
const btnUnlock = document.getElementById('btnUnlock');
const stopContainer = document.getElementById('stopContainer');
const btnStopStream = document.getElementById('btnStopStream');

const toastBanner = document.getElementById('toastBanner');
const toastText = document.getElementById('toastText');

let currentUser = null;
let activePhoneRecord = null;
let activePhoneId = 'NL-A8A7:D17F:6A99'; // fallback to known device ID
let isTunnelActive = false;
let peerConnection = null;
let adbDataChannel = null;
let tunnelWs = null;

// Toast helper
function showToast(msg, isError = false) {
  toastText.textContent = msg;
  toastBanner.className = 'toast-banner' + (isError ? ' error' : '');
  toastBanner.style.display = 'block';
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => {
    toastBanner.style.display = 'none';
  }, 4500);
}

// --- 2. Auth State Handler ---
onAuthStateChanged(auth, (user) => {
  if (user) {
    currentUser = user;
    userEmailText.textContent = user.email;
    userPill.style.display = 'flex';
    authCard.style.display = 'none';
    specChannel.textContent = 'Cloud Mesh Ready';
    listenToCloudPresence(user.uid);
  } else {
    currentUser = null;
    userPill.style.display = 'none';
    authCard.style.display = 'block';
    specChannel.textContent = 'Sign In Required';
  }
});

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  authErrorMsg.style.display = 'none';
  try {
    await signInWithEmailAndPassword(auth, authEmail.value.trim(), authPassword.value);
    showToast('Signed into Firebase Cloud successfully!');
  } catch (err) {
    authErrorMsg.textContent = err.message;
    authErrorMsg.style.display = 'block';
  }
});

logoutBtn.addEventListener('click', async () => {
  await signOut(auth);
});

// --- 3. Listen to Phone Presence in Firestore ---
function listenToCloudPresence(uid) {
  const presenceCol = collection(db, 'users', uid, 'presence');
  onSnapshot(presenceCol, (snapshot) => {
    let bestPhone = null;
    snapshot.forEach((docSnap) => {
      const data = docSnap.data();
      const devId = data.deviceId || docSnap.id;
      // Skip the desktop PC record
      if (devId !== 'NL-D1F9:8B2A:920E') {
        bestPhone = { id: devId, ...data };
      }
    });

    if (bestPhone) {
      activePhoneRecord = bestPhone;
      activePhoneId = bestPhone.id;
      const is5G = bestPhone.transport === 'CELLULAR' || (bestPhone.localIp && bestPhone.localIp.startsWith('192.0.0'));
      
      if (is5G) {
        deviceSub.textContent = `Remote 5G Cellular (${bestPhone.localIp || 'Carrier CGNAT'}) • Cloud Mesh`;
        specConnection.textContent = `5G Cellular (${bestPhone.localIp || 'Remote'})`;
      } else {
        deviceSub.textContent = `Direct Wi-Fi Hotspot (${bestPhone.localIp || '2ms'}) • Ultra-Low Latency`;
        specConnection.textContent = `Hotspot (${bestPhone.localIp || '10.38.115.80'})`;
      }
      specChannel.textContent = 'P2P Tunnel Ready';
    }
  });
}

// --- 4. WebRTC P2P Tunnel Handshake (5G Different Network Mode) ---
async function ensureTunnelConnected() {
  if (isTunnelActive && adbDataChannel && adbDataChannel.readyState === 'open') {
    return true;
  }

  if (!currentUser) {
    throw new Error('Please sign in to Firebase first.');
  }

  showToast('Negotiating WebRTC P2P Tunnel over Google STUN...');
  specChannel.textContent = 'Connecting P2P...';

  return new Promise((resolve, reject) => {
    try {
      // 1. Connect local WebSocket to Node bridge (/ws-tunnel)
      const wsProto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      tunnelWs = new WebSocket(`${wsProto}//${window.location.host}/ws-tunnel`);
      tunnelWs.binaryType = 'arraybuffer';

      // 2. Setup RTCPeerConnection with STUN servers
      peerConnection = new RTCPeerConnection({
        iceServers: [
          { urls: 'stun:stun.l.google.com:19302' },
          { urls: 'stun:stun1.l.google.com:19302' },
          { urls: 'stun:stun.cloudflare.com:3478' }
        ]
      });

      // 3. Create 'adb-bridge' DataChannel
      adbDataChannel = peerConnection.createDataChannel('adb-bridge', { ordered: true });
      adbDataChannel.binaryType = 'arraybuffer';

      const timeoutTimer = setTimeout(() => {
        if (!isTunnelActive) {
          reject(new Error('Cloud tunnel handshake timed out. Ensure Nothing Link is open on phone.'));
        }
      }, 15000);

      adbDataChannel.onopen = async () => {
        clearTimeout(timeoutTimer);
        isTunnelActive = true;
        specChannel.textContent = 'P2P Mesh Active';
        showToast('5G Cloud P2P Tunnel connected! Registering ADB bridge...');

        // Tell server to adb connect 127.0.0.1:5556
        try {
          await fetch('/api/connect-tunnel', { method: 'POST' });
        } catch (e) {}

        resolve(true);
      };

      adbDataChannel.onclose = () => {
        isTunnelActive = false;
        specChannel.textContent = 'Tunnel Idle';
      };

      adbDataChannel.onerror = (e) => {
        console.warn('DataChannel error:', e);
      };

      // Pipe DataChannel <-> WebSocket
      adbDataChannel.onmessage = (e) => {
        if (tunnelWs && tunnelWs.readyState === WebSocket.OPEN) {
          tunnelWs.send(e.data);
        }
      };

      tunnelWs.onmessage = (e) => {
        if (adbDataChannel && adbDataChannel.readyState === 'open') {
          adbDataChannel.send(e.data);
        }
      };

      // 4. Create Offer & Upload to Firestore
      (async () => {
        const offer = await peerConnection.createOffer();
        await peerConnection.setLocalDescription(offer);

        const sessionId = `ses_${Date.now()}`;
        const sessionDocRef = doc(db, 'users', currentUser.uid, 'sessions', sessionId);

        const targetDevice = activePhoneId || 'NL-F33E:7C0C:8465';

        await setDoc(sessionDocRef, {
          sessionId,
          fromDeviceId: 'NL-D1F9:8B2A:920E', // Windows Desktop PC
          toDeviceId: targetDevice,          // Nothing Phone
          state: 'INITIATED',
          offerSdp: JSON.stringify(offer),
          createdAt: serverTimestamp(),
          expiresAt: new Date(Date.now() + 5 * 60 * 1000)
        });

        // 5. Listen for Answer SDP from phone
        onSnapshot(sessionDocRef, async (snap) => {
          const data = snap.data();
          if (!data) return;
          if (data.answerSdp && !peerConnection.currentRemoteDescription) {
            const answer = JSON.parse(data.answerSdp);
            await peerConnection.setRemoteDescription(new RTCSessionDescription(answer));
          }
        });
      })().catch(err => {
        clearTimeout(timeoutTimer);
        reject(err);
      });

    } catch (err) {
      reject(err);
    }
  });
}

// --- 5. Status Poller (Check Scrcpy & Active Routes) ---
async function pollServerStatus() {
  try {
    const res = await fetch('/api/status');
    const data = await res.json();

    if (data.isScrcpyRunning) {
      stopContainer.style.display = 'block';
      statusBadge.textContent = 'STREAMING';
      statusBadge.className = 'status-badge online';
      deviceIndicator.className = 'indicator-bar green';
    } else {
      stopContainer.style.display = 'none';
      if (data.activeTarget) {
        statusBadge.textContent = 'READY';
        statusBadge.className = 'status-badge online';
        deviceIndicator.className = 'indicator-bar red';
      } else if (activePhoneRecord) {
        statusBadge.textContent = '5G CLOUD';
        statusBadge.className = 'status-badge online';
        deviceIndicator.className = 'indicator-bar red';
      } else {
        statusBadge.textContent = 'SEARCHING';
        statusBadge.className = 'status-badge offline';
        deviceIndicator.className = 'indicator-bar orange';
      }
    }

    if (data.activeTarget) {
      if (data.activeTarget.isLocal) {
        connDot.className = 'status-dot green';
        connText.textContent = data.activeTarget.type || 'Connected (Local)';
        specConnection.textContent = data.activeTarget.type || 'Direct Local Link';
      } else {
        connDot.className = 'status-dot green';
        connText.textContent = 'Connected (5G Cloud P2P)';
        specConnection.textContent = '5G Cellular P2P Mesh';
      }
    } else if (activePhoneRecord) {
      connDot.className = 'status-dot orange';
      connText.textContent = `Phone Online (${activePhoneRecord.transport || '5G'})`;
    } else {
      connDot.className = 'status-dot orange';
      connText.textContent = 'Searching for Phone...';
    }
  } catch (err) {
    connDot.className = 'status-dot red';
    connText.textContent = 'Local Server Reconnecting...';
  }
}

// --- 6. Button Event Listeners ---

// 1. Turn On Phone Hotspot
btnHotspot.addEventListener('click', async () => {
  showToast('Initiating Hotspot request...');
  try {
    const statusRes = await fetch('/api/status');
    const status = await statusRes.json();

    if (status.activeTarget && status.activeTarget.isLocal) {
      showToast('Enabling Wi-Fi Hotspot on connected device...');
      const res = await fetch('/api/hotspot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target: status.activeTarget.target })
      });
      const result = await res.json();
      if (result.success) {
        showToast('Wi-Fi Hotspot activated! Connect PC Wi-Fi to phone hotspot for 2ms mode.', false);
      } else {
        showToast(`Hotspot error: ${result.error || 'Failed to toggle switch'}`, true);
      }
    } else {
      // Remote 5G mode: Trigger over Firebase Cloud command & WebRTC
      showToast('Phone on Different Network (5G). Sending Cloud Command via Firebase...');
      if (currentUser) {
        const targetPhoneId = activePhoneId || 'NL-F33E:7C0C:8465';
        const cmdDocRef = doc(db, 'users', currentUser.uid, 'commands', targetPhoneId);
        await setDoc(cmdDocRef, {
          action: 'ENABLE_HOTSPOT',
          timestamp: serverTimestamp(),
          handled: false,
          from: 'Windows PC Host'
        });
        showToast('Hotspot activation command sent over 5G! Companion app enabling Hotspot...', false);
      } else {
        showToast('Please sign in to Firebase Cloud first.', true);
      }
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, true);
  }
});

// 2. Mirror Screen (Physical Screen OFF)
btnMirrorOff.addEventListener('click', async () => {
  showToast('Preparing Mirror (Physical Screen OFF)...');
  try {
    const statusRes = await fetch('/api/status');
    const status = await statusRes.json();

    let target = null;
    if (status.activeTarget && status.activeTarget.isLocal) {
      target = status.activeTarget.target;
    } else {
      showToast('Phone on Different Network (5G). Connecting Cloud Tunnel...');
      await ensureTunnelConnected();
      target = '127.0.0.1:5556';
    }

    const res = await fetch('/api/mirror', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode: 'screen-off', target })
    });
    const result = await res.json();
    if (result.success) {
      showToast(`Mirrored! Screen is OFF. Target: ${result.target || target}`);
      specMode.textContent = 'Physical Screen OFF';
      pollServerStatus();
    } else {
      showToast(`Error: ${result.error || 'Mirror failed'}`, true);
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, true);
  }
});

// 3. Mirror Screen (Physical Screen ON)
btnMirrorOn.addEventListener('click', async () => {
  showToast('Preparing Mirror (Physical Screen ON)...');
  try {
    const statusRes = await fetch('/api/status');
    const status = await statusRes.json();

    let target = null;
    if (status.activeTarget && status.activeTarget.isLocal) {
      target = status.activeTarget.target;
    } else {
      showToast('Phone on Different Network (5G). Connecting Cloud Tunnel...');
      await ensureTunnelConnected();
      target = '127.0.0.1:5556';
    }

    const res = await fetch('/api/mirror', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode: 'screen-on', target })
    });
    const result = await res.json();
    if (result.success) {
      showToast(`Mirrored with Screen ON! Target: ${result.target || target}`);
      specMode.textContent = 'Physical Screen ON';
      pollServerStatus();
    } else {
      showToast(`Error: ${result.error || 'Mirror failed'}`, true);
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, true);
  }
});

// 4. Auto-Unlock Phone
btnUnlock.addEventListener('click', async () => {
  showToast('Waking screen & injecting pattern 159873...');
  try {
    const statusRes = await fetch('/api/status');
    const status = await statusRes.json();

    let target = null;
    if (status.activeTarget && status.activeTarget.isLocal) {
      target = status.activeTarget.target;
    } else {
      await ensureTunnelConnected();
      target = '127.0.0.1:5556';
    }

    const res = await fetch('/api/unlock', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target })
    });
    const result = await res.json();
    if (result.success) {
      showToast('Phone unlocked successfully with pattern 159873!');
    } else {
      showToast(`Unlock attempted. ${result.error || ''}`, true);
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, true);
  }
});

// 5. Disconnect / Stop Stream
btnStopStream.addEventListener('click', async () => {
  try {
    await fetch('/api/kill-stream', { method: 'POST' });
    showToast('Mirror stream stopped. Screen locked.');
    pollServerStatus();
  } catch (err) {
    showToast(`Error: ${err.message}`, true);
  }
});

// Initial poll and recurring check
pollServerStatus();
setInterval(pollServerStatus, 1500);
