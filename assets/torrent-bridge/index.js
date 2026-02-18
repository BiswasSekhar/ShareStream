#!/usr/bin/env node
/**
 * Torrent Bridge — Node.js sidecar for Flutter desktop.
 *
 * Communicates via stdin/stdout JSON messages.
 * Uses webtorrent-hybrid for full BitTorrent protocol support.
 *
 * Commands (JSON on stdin):
 *   { "cmd": "seed",   "filePath": "...", "trackerUrl": "ws://..." }
 *   { "cmd": "add",    "magnetURI": "...", "trackerUrl": "ws://..." }
 *   { "cmd": "info" }
 *   { "cmd": "stop" }
 *   { "cmd": "quit" }
 *
 * Responses (JSON on stdout):
 *   { "event": "ready" }
 *   { "event": "seeding",  "magnetURI": "...", "serverUrl": "http://localhost:PORT/0/FILENAME" }
 *   { "event": "added",    "name": "...",  "serverUrl": "http://localhost:PORT/0/FILENAME" }
 *   { "event": "progress", "downloaded": 0.5, "speed": 123456, "peers": 3 }
 *   { "event": "done" }
 *   { "event": "error",    "message": "..." }
 *   { "event": "info",     "torrents": [...] }
 *   { "event": "stopped" }
 */

const WebTorrent = require('webtorrent-hybrid');
const readline = require('readline');

let client = null;
let activeTorrent = null;
let httpServer = null;
let progressTimer = null;

function send(obj) {
    process.stdout.write(JSON.stringify(obj) + '\n');
}

function startProgressReporting(torrent) {
    stopProgressReporting();
    progressTimer = setInterval(() => {
        send({
            event: 'progress',
            downloaded: Math.round(torrent.progress * 100) / 100,
            speed: torrent.downloadSpeed || torrent.uploadSpeed || 0,
            peers: torrent.numPeers,
        });
    }, 1000);
}

function stopProgressReporting() {
    if (progressTimer) {
        clearInterval(progressTimer);
        progressTimer = null;
    }
}

function getServerUrl(torrent) {
    if (!httpServer) return null;
    const addr = httpServer.address();
    if (!addr) return null;
    const videoFile = torrent.files.find(f => {
        const name = f.name.toLowerCase();
        return name.endsWith('.mp4') || name.endsWith('.mkv') || name.endsWith('.webm') || name.endsWith('.mov') || name.endsWith('.avi');
    }) || torrent.files[0];
    if (!videoFile) return null;
    const fileIndex = torrent.files.indexOf(videoFile);
    return `http://localhost:${addr.port}/${fileIndex}/${encodeURIComponent(videoFile.name)}`;
}

async function handleCommand(msg) {
    try {
        switch (msg.cmd) {
            case 'seed': {
                // Stop previous torrent
                if (activeTorrent) {
                    stopProgressReporting();
                    client.remove(activeTorrent);
                    activeTorrent = null;
                }

                const opts = {};
                if (msg.trackerUrl) {
                    opts.announce = [msg.trackerUrl];
                }

                client.seed(msg.filePath, opts, (torrent) => {
                    activeTorrent = torrent;

                    // Create HTTP server for this torrent
                    httpServer = torrent.createServer();
                    httpServer.listen(0, () => {
                        const serverUrl = getServerUrl(torrent);
                        send({
                            event: 'seeding',
                            magnetURI: torrent.magnetURI,
                            serverUrl,
                            name: torrent.name,
                        });
                    });

                    startProgressReporting(torrent);

                    torrent.on('wire', () => {
                        send({
                            event: 'progress',
                            downloaded: 1,
                            speed: torrent.uploadSpeed || 0,
                            peers: torrent.numPeers,
                        });
                    });
                });
                break;
            }

            case 'add': {
                // Stop previous torrent
                if (activeTorrent) {
                    stopProgressReporting();
                    if (httpServer) {
                        httpServer.close();
                        httpServer = null;
                    }
                    client.remove(activeTorrent);
                    activeTorrent = null;
                }

                const opts = {};
                if (msg.trackerUrl) {
                    opts.announce = [msg.trackerUrl];
                }

                client.add(msg.magnetURI, opts, (torrent) => {
                    activeTorrent = torrent;

                    // Piece prioritization — first 2% critical for fast startup
                    const totalPieces = torrent.pieces.length;
                    if (totalPieces > 0) {
                        const criticalEnd = Math.min(Math.ceil(totalPieces * 0.02), 20);
                        torrent.critical(0, criticalEnd);
                    }

                    // Create HTTP server
                    httpServer = torrent.createServer();
                    httpServer.listen(0, () => {
                        const serverUrl = getServerUrl(torrent);
                        send({
                            event: 'added',
                            name: torrent.name,
                            serverUrl,
                            files: torrent.files.map(f => ({ name: f.name, length: f.length })),
                        });
                    });

                    startProgressReporting(torrent);

                    torrent.on('done', () => {
                        send({ event: 'done' });
                        stopProgressReporting();
                    });
                });
                break;
            }

            case 'info': {
                send({
                    event: 'info',
                    torrents: client.torrents.map(t => ({
                        name: t.name,
                        magnetURI: t.magnetURI,
                        progress: t.progress,
                        downloadSpeed: t.downloadSpeed,
                        uploadSpeed: t.uploadSpeed,
                        numPeers: t.numPeers,
                    })),
                });
                break;
            }

            case 'stop': {
                stopProgressReporting();
                if (httpServer) {
                    httpServer.close();
                    httpServer = null;
                }
                if (activeTorrent) {
                    client.remove(activeTorrent);
                    activeTorrent = null;
                }
                send({ event: 'stopped' });
                break;
            }

            case 'quit': {
                stopProgressReporting();
                if (httpServer) httpServer.close();
                client.destroy(() => {
                    process.exit(0);
                });
                break;
            }

            default:
                send({ event: 'error', message: `Unknown command: ${msg.cmd}` });
        }
    } catch (err) {
        send({ event: 'error', message: err.message });
    }
}

// ─── Initialize ───

client = new WebTorrent();

client.on('error', (err) => {
    send({ event: 'error', message: err.message });
});

// Read JSON commands from stdin
const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
    try {
        const msg = JSON.parse(line.trim());
        handleCommand(msg);
    } catch (err) {
        send({ event: 'error', message: `Invalid JSON: ${err.message}` });
    }
});

rl.on('close', () => {
    stopProgressReporting();
    if (httpServer) httpServer.close();
    client.destroy(() => process.exit(0));
});

send({ event: 'ready' });
