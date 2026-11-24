// Padel online relay.
//
// Pairs two phones (random quick match, or a private 4-letter room code) and
// then forwards their game packets to each other. The host phone runs the
// match; this server never looks inside a game packet, so it stays tiny,
// cheap and generic.
//
// Protocol (WebSocket):
//   text frames  = JSON control messages
//     client -> server  {t:"hello", v}              protocol version check
//                       {t:"quick", length, rating}  join the random queue (paired by rating)
//                       {t:"create", length, golden} make a private room
//                       {t:"join", code}             join a private room
//                       {t:"cancel"}                 leave queue/room
//     server -> client  {t:"queued"} {t:"room", code} {t:"matched", host, length, golden}
//                       {t:"left"} {t:"error", code, msg}
//   binary frames = game packets, forwarded verbatim to the other player

"use strict";
const http = require("http");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT || 8080);
const PROTOCOL = 2;                       // bump when the game's netcode changes
const RATING_WINDOW = 150;                // pair within this rating gap at first...
const RATING_WIDEN = 40;                  // ...widening by this much per second of waiting
const LENGTHS = ["quick", "set", "match"];
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const ROOM_TTL_MS = 30 * 60 * 1000;
const MAX_PER_IP = 16;
const MAX_MSGS_PER_SEC = 200;             // game traffic is ~35/s per player

const queues = Object.fromEntries(LENGTHS.map((l) => [l, []]));
const rooms = new Map();                  // code -> { host, length, golden, created }
const perIp = new Map();
let matchesStarted = 0;

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({
      ok: true,
      clients: wss.clients.size,
      waiting: LENGTHS.reduce((n, l) => n + queues[l].length, 0),
      rooms: rooms.size,
      matchesStarted,
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 });

function send(ws, obj) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
}

function newCode() {
  for (;;) {
    let c = "";
    for (let i = 0; i < 4; i++) c += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
}

// Take a socket out of any queue or room it is waiting in.
function leaveWaiting(ws) {
  if (ws.queue) {
    const q = queues[ws.queue];
    const i = q.indexOf(ws);
    if (i >= 0) q.splice(i, 1);
    ws.queue = null;
  }
  if (ws.room) {
    const r = rooms.get(ws.room);
    if (r && r.host === ws) rooms.delete(ws.room);
    ws.room = null;
  }
}

// How far apart two ratings may be: generous after a wait, so nobody is stuck.
function ratingWindow(ws, now) {
  return RATING_WINDOW + RATING_WIDEN * Math.max(0, now - (ws.queuedAt || now)) / 1000;
}

// The waiting player nearest in rating to `ws`, if within both players' windows.
function closestMatch(q, ws) {
  const now = Date.now();
  let best = null;
  let bestGap = Infinity;
  for (const o of q) {
    if (o === ws || o.readyState !== 1) continue;
    const gap = Math.abs((o.rating || 1000) - (ws.rating || 1000));
    if (gap <= Math.max(ratingWindow(o, now), ratingWindow(ws, now)) && gap < bestGap) {
      best = o;
      bestGap = gap;
    }
  }
  return best;
}

// Waiting players' windows grow each second: pair any that now fit.
setInterval(() => {
  for (const l of LENGTHS) {
    const q = queues[l];
    for (let i = 0; i < q.length; i++) {
      const a = q[i];
      const b = closestMatch(q.slice(i + 1), a);
      if (b) {
        q.splice(q.indexOf(b), 1);
        q.splice(i, 1);
        a.queue = null;
        b.queue = null;
        pair(a, b, l, true);
        i--;
      }
    }
  }
}, 1000);

function pair(host, guest, length, golden) {
  host.peer = guest;
  guest.peer = host;
  matchesStarted++;
  send(host, { t: "matched", host: true, length, golden });
  send(guest, { t: "matched", host: false, length, golden });
}

function onControl(ws, m) {
  if (m.t === "hello") {
    ws.version = m.v;
    if (m.v !== PROTOCOL) {
      send(ws, { t: "error", code: "version", msg: "Please update the game to play online." });
      ws.close(4000, "version");
    }
    return;
  }
  if (ws.version !== PROTOCOL || ws.peer) return; // must say hello first; no lobby actions mid-match
  switch (m.t) {
    case "quick": {
      leaveWaiting(ws);
      const length = LENGTHS.includes(m.length) ? m.length : "quick";
      ws.rating = Number.isFinite(m.rating) ? Math.max(0, Math.min(4000, m.rating)) : 1000;
      ws.queuedAt = Date.now();
      const q = queues[length];
      for (let i = q.length - 1; i >= 0; i--) if (q[i].readyState !== 1) q.splice(i, 1);
      const other = closestMatch(q, ws);
      if (other) {
        q.splice(q.indexOf(other), 1);
        other.queue = null;
        pair(other, ws, length, true);
      } else {
        q.push(ws);
        ws.queue = length;
        send(ws, { t: "queued" });
      }
      break;
    }
    case "create": {
      leaveWaiting(ws);
      const code = newCode();
      const length = LENGTHS.includes(m.length) ? m.length : "quick";
      rooms.set(code, { host: ws, length, golden: m.golden !== false, created: Date.now() });
      ws.room = code;
      send(ws, { t: "room", code });
      break;
    }
    case "join": {
      const code = String(m.code || "").toUpperCase().trim();
      const r = rooms.get(code);
      if (!r || r.host.readyState !== 1 || r.host === ws) {
        send(ws, { t: "error", code: "no_room", msg: "No game with that code. Check it with your friend." });
        break;
      }
      leaveWaiting(ws);
      rooms.delete(code);
      r.host.room = null;
      pair(r.host, ws, r.length, r.golden);
      break;
    }
    case "cancel":
      leaveWaiting(ws);
      break;
  }
}

wss.on("connection", (ws, req) => {
  const ip = (req.headers["fly-client-ip"] || req.headers["x-forwarded-for"] || req.socket.remoteAddress || "")
    .toString().split(",")[0].trim();
  const n = (perIp.get(ip) || 0) + 1;
  if (n > MAX_PER_IP) {
    ws.close(4001, "too many connections");
    return;
  }
  perIp.set(ip, n);
  ws.ip = ip;
  ws.isAlive = true;
  ws.msgCount = 0;
  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", (data, isBinary) => {
    if (++ws.msgCount > MAX_MSGS_PER_SEC) {
      ws.close(4002, "flood");
      return;
    }
    if (isBinary) {
      if (ws.peer && ws.peer.readyState === 1) ws.peer.send(data, { binary: true });
      return;
    }
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }
    if (m && typeof m.t === "string") onControl(ws, m);
  });

  ws.on("close", () => {
    leaveWaiting(ws);
    const left = (perIp.get(ip) || 1) - 1;
    if (left <= 0) perIp.delete(ip); else perIp.set(ip, left);
    if (ws.peer) {
      send(ws.peer, { t: "left" });
      ws.peer.peer = null;
      ws.peer = null;
    }
  });
});

// Heartbeat (drops phones that vanished without closing), message-rate window,
// and expiry of private rooms nobody joined.
setInterval(() => {
  for (const ws of wss.clients) {
    ws.msgCount = 0;
  }
}, 1000);
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
  const now = Date.now();
  for (const [code, r] of rooms) {
    if (now - r.created > ROOM_TTL_MS) {
      send(r.host, { t: "error", code: "expired", msg: "Your private game expired." });
      r.host.room = null;
      rooms.delete(code);
    }
  }
}, 15000);

server.listen(PORT, () => console.log(`padel relay listening on :${PORT} (protocol ${PROTOCOL})`));
