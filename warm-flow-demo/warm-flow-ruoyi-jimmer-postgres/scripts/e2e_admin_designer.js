#!/usr/bin/env node
'use strict';

/**
 * Browser-level smoke for the full RuoYi admin shell and embedded Warm-Flow UI.
 *
 * The script deliberately checks two independent regressions that plain HTTP
 * smoke tests cannot catch:
 * 1. History-mode admin routes must render the complete RuoYi SPA after a
 *    direct browser refresh.
 * 2. The Warm-Flow designer must overwrite a stale localStorage token with the
 *    current RuoYi Admin-Token cookie before it calls Warm-Flow APIs.
 */
const net = require('net');
const { chromium } = require('playwright');

const BASE = env('WARM_FLOW_BASE', 'http://192.168.2.226:18080/');
const REDIS_HOST = env('REDIS_HOST', '192.168.2.226');
const REDIS_PORT = Number(env('REDIS_PORT', '6379'));
const REDIS_DATABASE = env('REDIS_DATABASE', '0');
const REDIS_PASSWORD = env('REDIS_PASSWORD', '');
const USERNAME = env('WARM_FLOW_USER', 'admin');
const PASSWORD = env('WARM_FLOW_PASSWORD', 'admin123');
const HEADLESS = env('PLAYWRIGHT_HEADLESS', 'true').toLowerCase() !== 'false';
const NAVIGATION_TIMEOUT_MS = Number(env('PLAYWRIGHT_NAVIGATION_TIMEOUT_MS', '20000'));
const REDIS_TIMEOUT_MS = Number(env('REDIS_TIMEOUT_MS', '5000'));

function env(name, defaultValue) {
  const value = process.env[name];
  return value == null || value === '' ? defaultValue : value;
}

function absoluteUrl(path) {
  return new URL(path.replace(/^\//, ''), BASE).toString();
}

async function jsonFetch(path, options = {}) {
  const res = await fetch(absoluteUrl(path), {
    ...options,
    headers: {
      Accept: 'application/json',
      ...(options.body ? {'Content-Type': 'application/json;charset=UTF-8'} : {}),
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let body = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = {raw: text};
  }
  if (!res.ok) {
    throw new Error(`${path} HTTP ${res.status}: ${text.slice(0, 200)}`);
  }
  return body;
}

function encodeRedis(parts) {
  return `*${parts.length}\r\n` + parts.map(part => {
    const value = String(part);
    return `$${Buffer.byteLength(value)}\r\n${value}\r\n`;
  }).join('');
}

function parseRedisResponse(buffer, offset) {
  const prefix = String.fromCharCode(buffer[offset]);
  const lineEnd = buffer.indexOf('\r\n', offset, 'utf8');
  if (lineEnd < 0) {
    return null;
  }
  const line = buffer.toString('utf8', offset + 1, lineEnd);
  if (prefix === '+') {
    return {value: line, next: lineEnd + 2};
  }
  if (prefix === '-') {
    throw new Error(line);
  }
  if (prefix === ':') {
    return {value: Number(line), next: lineEnd + 2};
  }
  if (prefix === '$') {
    const length = Number(line);
    const dataStart = lineEnd + 2;
    if (length < 0) {
      return {value: null, next: dataStart};
    }
    const dataEnd = dataStart + length;
    if (buffer.length < dataEnd + 2) {
      return null;
    }
    return {value: buffer.toString('utf8', dataStart, dataEnd), next: dataEnd + 2};
  }
  throw new Error(`Unsupported Redis reply prefix: ${prefix}`);
}

async function redisGetCaptcha(uuid) {
  const commands = [];
  if (REDIS_PASSWORD) {
    commands.push(['AUTH', REDIS_PASSWORD]);
  }
  commands.push(['SELECT', REDIS_DATABASE]);
  commands.push(['GET', `captcha_codes:${uuid}`]);

  return await new Promise((resolve, reject) => {
    const socket = net.createConnection({host: REDIS_HOST, port: REDIS_PORT});
    let buffer = Buffer.alloc(0);
    let offset = 0;
    const replies = [];
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`Redis timeout for captcha uuid=${uuid}`));
    }, REDIS_TIMEOUT_MS);

    socket.on('connect', () => socket.write(commands.map(encodeRedis).join('')));
    socket.on('data', chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      try {
        while (replies.length < commands.length) {
          const parsed = parseRedisResponse(buffer, offset);
          if (!parsed) {
            break;
          }
          replies.push(parsed.value);
          offset = parsed.next;
        }
        if (replies.length === commands.length) {
          clearTimeout(timer);
          socket.end();
          resolve(normalizeRedisValue(replies[replies.length - 1]));
        }
      } catch (err) {
        clearTimeout(timer);
        socket.destroy();
        reject(describeRedisCaptchaError(err));
      }
    });
    socket.on('error', err => {
      clearTimeout(timer);
      reject(describeRedisCaptchaError(err));
    });
  });
}

function describeRedisCaptchaError(err) {
  const message = String(err && err.message || err);
  if (message.includes('NOAUTH') || message.includes('WRONGPASS') || message.includes('AUTH')) {
    return new Error(`${message}; captcha Redis requires REDIS_PASSWORD in the environment`);
  }
  return err;
}

function normalizeRedisValue(value) {
  if (!value) {
    return '';
  }
  const raw = String(value).trim();
  if (!raw) {
    return '';
  }
  try {
    const decoded = JSON.parse(raw);
    return decoded == null ? '' : String(decoded).trim();
  } catch {
    return raw;
  }
}

async function loginToken() {
  const captcha = await jsonFetch('/captchaImage');
  const uuid = String(captcha.uuid || '');
  let code = '';
  if (captcha.captchaEnabled !== false) {
    if (!uuid) {
      throw new Error('captcha uuid missing');
    }
    code = await redisGetCaptcha(uuid);
    if (!code) {
      throw new Error(`captcha value missing for uuid=${uuid}`);
    }
  }
  const login = await jsonFetch('/login', {
    method: 'POST',
    body: JSON.stringify({username: USERNAME, password: PASSWORD, code, uuid}),
  });
  if (!login.token) {
    throw new Error(`login token missing: ${JSON.stringify(login)}`);
  }
  return login.token;
}

async function readJsonResponse(resp) {
  try {
    const text = await resp.text();
    try {
      return JSON.parse(text);
    } catch {
      return {raw: text.slice(0, 200)};
    }
  } catch (err) {
    return {error: String(err.message || err)};
  }
}

async function verifyAdminRoutes(context, bad) {
  const appRoutes = ['/index', '/system/user', '/monitor/server', '/tool/gen', '/flow/definition', '/flow/1'];
  for (const route of appRoutes) {
    const page = await context.newPage();
    const pageErrors = [];
    const consoleErrors = [];
    const httpErrors = [];
    page.on('pageerror', err => pageErrors.push(String(err.message || err)));
    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });
    page.on('response', resp => {
      const status = resp.status();
      const respUrl = resp.url();
      if (status >= 400 && !respUrl.includes('/favicon')) {
        httpErrors.push(`${status} ${respUrl}`);
      }
    });

    await page.goto(route, {waitUntil: 'domcontentloaded', timeout: NAVIGATION_TIMEOUT_MS});
    await page.waitForTimeout(2500);
    const finalUrl = page.url();
    const title = await page.title().catch(() => '');
    const bodyText = (await page.locator('body').innerText({timeout: 5000}).catch(() => ''))
      .slice(0, 300)
      .replace(/\s+/g, ' ');
    const loginLike = /登录|验证码|用户名|密码/.test(bodyText) && !/首页|系统管理|流程|监控|代码生成/.test(bodyText);
    if (finalUrl.includes('/login') || loginLike || pageErrors.length || httpErrors.length) {
      bad.push({route, finalUrl, title, bodyText, pageErrors, consoleErrors, httpErrors});
    }
    console.log(`PAGE ${route} title=${JSON.stringify(title)} url=${finalUrl} pageErrors=${pageErrors.length} httpErrors=${httpErrors.length}`);
    await page.close();
  }
}

async function verifyDesignerTokenBootstrap(context, token, bad) {
  await context.addInitScript(() => {
    localStorage.setItem('Warm-TokenName', 'Authorization');
    localStorage.setItem('Warm-Authorization', 'Bearer stale-token-from-e2e');
  });

  const page = await context.newPage();
  const pageErrors = [];
  const consoleErrors = [];
  const httpErrors = [];
  const warmFlowResponses = [];
  page.on('pageerror', err => pageErrors.push(String(err.message || err)));
  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });
  page.on('response', async resp => {
    const respUrl = resp.url();
    const status = resp.status();
    if (status >= 400 && !respUrl.includes('/favicon')) {
      httpErrors.push(`${status} ${respUrl}`);
    }
    if (respUrl.includes('/warm-flow/query-def') || respUrl.includes('/warm-flow/listener-list')) {
      warmFlowResponses.push({url: respUrl, status, body: await readJsonResponse(resp)});
    }
  });

  await page.goto('/warm-flow-ui/index.html', {waitUntil: 'domcontentloaded', timeout: NAVIGATION_TIMEOUT_MS});
  await page.waitForTimeout(6000);

  const storedAuth = await page.evaluate(() => localStorage.getItem('Warm-Authorization'));
  const storedName = await page.evaluate(() => localStorage.getItem('Warm-TokenName'));
  const designerBody = (await page.locator('body').innerText({timeout: 5000}).catch(() => ''))
    .slice(0, 300)
    .replace(/\s+/g, ' ');
  const missing = ['query-def', 'listener-list']
    .filter(name => !warmFlowResponses.some(resp => resp.url.includes(`/warm-flow/${name}`) && resp.status === 200 && resp.body && resp.body.code === 200));

  if (!storedAuth || storedAuth === 'Bearer stale-token-from-e2e' || !storedAuth.endsWith(token) || storedName !== 'Authorization' || missing.length || pageErrors.length || httpErrors.length) {
    bad.push({
      route: '/warm-flow-ui/index.html',
      storedName,
      storedAuthPrefix: storedAuth ? storedAuth.slice(0, 32) : null,
      stale: storedAuth === 'Bearer stale-token-from-e2e',
      missing,
      designerBody,
      pageErrors,
      consoleErrors,
      httpErrors,
      warmFlowResponses,
    });
  }

  console.log(`DESIGNER storedName=${storedName} authOverwritten=${storedAuth === 'Bearer ' + token} warmFlowResponses=${JSON.stringify(warmFlowResponses.map(resp => ({path: new URL(resp.url).pathname, status: resp.status, code: resp.body && resp.body.code})))} pageErrors=${pageErrors.length} httpErrors=${httpErrors.length}`);
  await page.close();
}

async function main() {
  const token = await loginToken();
  console.log(`LOGIN token-len=${token.length}`);

  const browser = await chromium.launch({headless: HEADLESS});
  const context = await browser.newContext({baseURL: BASE, viewport: {width: 1440, height: 960}});
  const bad = [];
  try {
    await context.addCookies([{name: 'Admin-Token', value: token, url: BASE}]);
    await verifyAdminRoutes(context, bad);
    await verifyDesignerTokenBootstrap(context, token, bad);
  } finally {
    await browser.close();
  }

  console.log(`bad=${JSON.stringify(bad, null, 2)}`);
  if (bad.length) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error(err && err.stack || err);
  process.exit(1);
});
