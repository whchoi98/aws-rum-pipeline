'use strict';

/**
 * Lambda@Edge viewer-request: Cognito JWT 인증
 *
 * Lambda@Edge는 환경 변수를 사용할 수 없으므로, 설정은 config.json에서 번들.
 * 배포 전 config.json을 환경에 맞게 설정해야 함.
 */

const https = require('https');
const crypto = require('crypto');
const config = require('./config.json');

// JWKS 캐시 (콜드스타트 간 유지)
let jwksCache = null;
let jwksCacheTime = 0;
const JWKS_CACHE_TTL = 3600000; // 1시간

// ─── JWKS 관련 유틸 ───

async function fetchJwks() {
  const now = Date.now();
  if (jwksCache && (now - jwksCacheTime) < JWKS_CACHE_TTL) {
    return jwksCache;
  }

  const jwksUrl = `https://cognito-idp.${config.region}.amazonaws.com/${config.userPoolId}/.well-known/jwks.json`;
  const data = await httpGet(jwksUrl);
  jwksCache = JSON.parse(data);
  jwksCacheTime = now;
  return jwksCache;
}

function httpGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => resolve(body));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function httpPost(url, body, contentType) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const options = {
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: 'POST',
      headers: {
        'Content-Type': contentType,
        'Content-Length': Buffer.byteLength(body),
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => resolve({ statusCode: res.statusCode, body: data }));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// Base64url 디코딩
function base64urlDecode(str) {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  while (str.length % 4) str += '=';
  return Buffer.from(str, 'base64');
}

// JWT 디코딩 (검증 없이)
function decodeJwt(token) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Invalid JWT');
  return {
    header: JSON.parse(base64urlDecode(parts[0]).toString()),
    payload: JSON.parse(base64urlDecode(parts[1]).toString()),
    signature: parts[2],
  };
}

// RSA 공개키로 JWT 서명 검증
function verifyJwtSignature(token, jwk) {
  const parts = token.split('.');
  const signedContent = parts[0] + '.' + parts[1];
  const signature = base64urlDecode(parts[2]);

  const key = crypto.createPublicKey({
    key: {
      kty: 'RSA',
      n: jwk.n,
      e: jwk.e,
    },
    format: 'jwk',
  });

  return crypto.verify(
    'RSA-SHA256',
    Buffer.from(signedContent),
    key,
    signature,
  );
}

// JWT 전체 검증
async function verifyToken(token) {
  const decoded = decodeJwt(token);
  const { header, payload } = decoded;

  // kid 매칭
  const jwks = await fetchJwks();
  const jwk = jwks.keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error('JWK not found for kid: ' + header.kid);

  // 서명 검증
  if (!verifyJwtSignature(token, jwk)) {
    throw new Error('Invalid signature');
  }

  // 클레임 검증
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) throw new Error('Token expired');
  if (payload.iss !== `https://cognito-idp.${config.region}.amazonaws.com/${config.userPoolId}`) {
    throw new Error('Invalid issuer');
  }
  if (payload.token_use !== 'id') throw new Error('Not an id_token');

  return payload;
}

// ─── 쿠키 유틸 ───

function parseCookies(headers) {
  const cookies = {};
  if (!headers.cookie) return cookies;
  headers.cookie.forEach((c) => {
    c.value.split(';').forEach((pair) => {
      const [name, ...rest] = pair.trim().split('=');
      cookies[name] = rest.join('=');
    });
  });
  return cookies;
}

function setCookieHeader(name, value, maxAge) {
  return `${name}=${value}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=${maxAge}`;
}

function clearCookieHeader(name) {
  return `${name}=; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=0`;
}

// ─── Cognito URL 생성 ───

function getLoginUrl(callbackUrl) {
  const params = new URLSearchParams({
    client_id: config.clientId,
    response_type: 'code',
    scope: 'openid email profile',
    redirect_uri: callbackUrl,
  });
  if (config.identityProvider) {
    params.set('identity_provider', config.identityProvider);
  }
  return `https://${config.cognitoDomain}/oauth2/authorize?${params}`;
}

function getLogoutUrl(redirectUrl) {
  const params = new URLSearchParams({
    client_id: config.clientId,
    logout_uri: redirectUrl,
  });
  return `https://${config.cognitoDomain}/logout?${params}`;
}

// ─── 메인 핸들러 ───

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  const uri = request.uri;
  const host = headers.host[0].value;
  const callbackUrl = `https://${host}/auth/callback`;

  // 1. 콜백 처리: authorization code → token 교환
  if (uri === '/auth/callback') {
    const qs = new URLSearchParams(request.querystring);
    const code = qs.get('code');

    if (!code) {
      return redirect(getLoginUrl(callbackUrl));
    }

    try {
      const tokenBody = new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: config.clientId,
        code,
        redirect_uri: callbackUrl,
      }).toString();

      const tokenUrl = `https://${config.cognitoDomain}/oauth2/token`;
      const resp = await httpPost(tokenUrl, tokenBody, 'application/x-www-form-urlencoded');

      if (resp.statusCode !== 200) {
        return redirect(getLoginUrl(callbackUrl));
      }

      const tokens = JSON.parse(resp.body);
      const idPayload = decodeJwt(tokens.id_token).payload;
      const maxAge = idPayload.exp - Math.floor(Date.now() / 1000);

      return {
        status: '302',
        statusDescription: 'Found',
        headers: {
          location: [{ value: `https://${host}/` }],
          'set-cookie': [
            { value: setCookieHeader('id_token', tokens.id_token, maxAge) },
            { value: setCookieHeader('access_token', tokens.access_token, maxAge) },
          ],
          'cache-control': [{ value: 'no-cache, no-store' }],
        },
      };
    } catch (err) {
      console.error('Token exchange failed:', err);
      return redirect(getLoginUrl(callbackUrl));
    }
  }

  // 2. 로그아웃 처리
  if (uri === '/auth/logout') {
    return {
      status: '302',
      statusDescription: 'Found',
      headers: {
        location: [{ value: getLogoutUrl(`https://${host}/`) }],
        'set-cookie': [
          { value: clearCookieHeader('id_token') },
          { value: clearCookieHeader('access_token') },
        ],
        'cache-control': [{ value: 'no-cache, no-store' }],
      },
    };
  }

  // 3. JWT 검증
  const cookies = parseCookies(headers);
  const idToken = cookies['id_token'];

  if (!idToken) {
    return redirect(getLoginUrl(callbackUrl));
  }

  try {
    const payload = await verifyToken(idToken);

    // x-user-sub 헤더 주입 (Origin으로 전달)
    request.headers['x-user-sub'] = [{ value: payload.sub }];
    request.headers['x-user-email'] = [{ value: payload.email || '' }];

    return request;
  } catch (err) {
    console.error('JWT verification failed:', err.message);
    // 토큰 만료/무효 → 쿠키 삭제 후 재로그인
    return {
      status: '302',
      statusDescription: 'Found',
      headers: {
        location: [{ value: getLoginUrl(callbackUrl) }],
        'set-cookie': [
          { value: clearCookieHeader('id_token') },
          { value: clearCookieHeader('access_token') },
        ],
        'cache-control': [{ value: 'no-cache, no-store' }],
      },
    };
  }
};

function redirect(url) {
  return {
    status: '302',
    statusDescription: 'Found',
    headers: {
      location: [{ value: url }],
      'cache-control': [{ value: 'no-cache, no-store' }],
    },
  };
}
