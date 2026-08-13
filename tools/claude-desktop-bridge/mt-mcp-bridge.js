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

if (target.protocol !== 'http:' && target.protocol !== 'https:') {
    process.stderr.write('[mt-mcp-bridge] Invalid MT_MCP_URL: protocol must be http: or https: (got ' + target.protocol + ')\n');
    process.exit(1);
}

const client = target.protocol === 'https:' ? https : http;
const REQUEST_TIMEOUT_MS = 15000;

// MCP の stdio トランスポートは改行区切りの JSON-RPC メッセージを使う。
const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) {
        return;
    }

    let message;
    try {
        message = JSON.parse(trimmed);
    } catch (err) {
        // 送られてきた行そのものがJSONとして壊れている場合、対応する id が
        // 分からないため JSON-RPC の慣例に従い id: null で parse error を返す。
        process.stderr.write('[mt-mcp-bridge] Invalid JSON from stdin: ' + err.message + '\n');
        process.stdout.write(JSON.stringify({
            jsonrpc: '2.0',
            id: null,
            error: { code: -32700, message: 'Parse error' },
        }) + '\n');
        return;
    }

    // 通知（id を持たないメッセージ）には応答を返さないのが JSON-RPC の
    // 仕様。それ以外（id を持つリクエスト）は、上流で何が起きても必ず
    // 何らかの応答を返す（さもないと Claude Desktop が応答を待ち続ける）。
    const hasId = Object.prototype.hasOwnProperty.call(message, 'id');
    let responded = false;
    const fail = (errMessage) => {
        if (responded) {
            return;
        }
        responded = true;
        process.stderr.write('[mt-mcp-bridge] ' + errMessage + '\n');
        if (hasId) {
            process.stdout.write(JSON.stringify({
                jsonrpc: '2.0',
                id: message.id,
                error: { code: -32000, message: errMessage },
            }) + '\n');
        }
    };

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
            if (responded) {
                return;
            }
            const text = Buffer.concat(chunks).toString('utf8').trim();
            // 2xx 以外（3xxのリダイレクトも含む）は失敗として扱う。
            if (res.statusCode < 200 || res.statusCode >= 300) {
                fail('HTTP ' + res.statusCode + ': ' + text);
                return;
            }
            // 通知（notifications/*）には応答本文が無い（204/空ボディ）。
            // その場合は stdout に何も書き出さない（JSON-RPC の通知には
            // レスポンスを返さないのが正しい）。
            if (!text) {
                responded = true;
                return;
            }
            responded = true;
            process.stdout.write(text + '\n');
        });
    });

    req.on('error', (err) => {
        fail('Request error: ' + err.message);
    });

    req.setTimeout(REQUEST_TIMEOUT_MS, () => {
        req.destroy(new Error('Request timed out after ' + REQUEST_TIMEOUT_MS + 'ms'));
    });

    req.write(body);
    req.end();
});

process.stdin.resume();
