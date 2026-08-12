#!/usr/bin/env node
'use strict';

/**
 * MT MCP Server 用の stdio <-> HTTP ブリッジ。
 *
 * Claude Desktop の claude_desktop_config.json は、リモートの HTTP/SSE
 * サーバー（"type": "sse" / "url" 形式）を直接サポートしていない
 * （"not a valid MCP server configuration" として無視される）。
 * ローカル環境で MT (mt-data-api.cgi) が HTTP のみ（HTTPS未対応）で動いて
 * いる場合、Claude Desktop のリモートコネクタ機能も使えない。
 *
 * このスクリプトは Claude Desktop が「ローカルコマンド」として起動する
 * MCP サーバーとして振る舞い、標準入出力（stdio）で受け取った JSON-RPC
 * メッセージを、そのまま MT MCP Server の HTTP エンドポイントへ転送する
 * だけの薄い中継役。HTTPSは不要（localhost 上の通信のため）。
 *
 * 使い方（claude_desktop_config.json）:
 *
 *   {
 *     "mcpServers": {
 *       "movable-type": {
 *         "command": "node",
 *         "args": ["/absolute/path/to/mt-mcp-bridge.js"],
 *         "env": {
 *           "MT_MCP_URL": "http://localhost:10000/mt-data-api.cgi/v4/mcp",
 *           "MT_MCP_TOKEN": "<発行したトークン>"
 *         }
 *       }
 *     }
 *   }
 *
 * トークンは README の方法A/B/Cのいずれかで発行したものを使用する。
 */

const http = require('http');
const https = require('https');
const readline = require('readline');

const TARGET_URL = process.env.MT_MCP_URL;
const TOKEN = process.env.MT_MCP_TOKEN;

if (!TARGET_URL) {
    process.stderr.write('[mt-mcp-bridge] MT_MCP_URL environment variable is required\n');
    process.exit(1);
}
if (!TOKEN) {
    process.stderr.write('[mt-mcp-bridge] MT_MCP_TOKEN environment variable is required\n');
    process.exit(1);
}

let target;
try {
    target = new URL(TARGET_URL);
} catch (err) {
    process.stderr.write('[mt-mcp-bridge] Invalid MT_MCP_URL: ' + err.message + '\n');
    process.exit(1);
}

const client = target.protocol === 'https:' ? https : http;

// MCP の stdio トランスポートは改行区切りの JSON-RPC メッセージを使う。
const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) {
        return;
    }

    const body = Buffer.from(trimmed, 'utf8');
    const req = client.request(target, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + TOKEN,
            'Content-Length': body.length,
        },
    }, (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8').trim();
            if (res.statusCode >= 400) {
                process.stderr.write('[mt-mcp-bridge] HTTP ' + res.statusCode + ': ' + text + '\n');
                return;
            }
            // 通知（notifications/*）には応答本文が無い（204/空ボディ）。
            // その場合は stdout に何も書き出さない（JSON-RPC の通知には
            // レスポンスを返さないのが正しい）。
            if (!text) {
                return;
            }
            process.stdout.write(text + '\n');
        });
    });

    req.on('error', (err) => {
        process.stderr.write('[mt-mcp-bridge] Request error: ' + err.message + '\n');
    });

    req.write(body);
    req.end();
});

process.stdin.resume();
