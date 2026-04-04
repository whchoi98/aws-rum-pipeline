<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## SDK Module

### Role
브라우저에서 RUM 이벤트(페이지뷰, 에러, 사용자 액션, 성능 지표)를 수집하고
API Gateway로 전송하는 TypeScript 클라이언트 SDK.

### Key Files
- `src/` — SDK 소스 (TypeScript)
- `tests/` — vitest 테스트
- `esbuild.config.js` — 빌드 설정 (ESM + CJS 번들)
- `vitest.config.ts` — 테스트 설정
- `package.json` — 패키지 메타데이터 및 스크립트
- `tsconfig.json` — TypeScript 설정 (strict mode)

### Key Commands
```bash
npm install        # 의존성 설치
npm test           # vitest 실행
npm run build      # esbuild 번들
```

### Rules
- TypeScript strict 모드 유지
- 브라우저 호환성: ES2017+, no Node.js globals
- API Key는 런타임 주입 (번들에 포함 금지)
- 이벤트 배치 전송으로 네트워크 요청 최소화
- 테스트는 vitest (jest 대체)
- esbuild로 빌드 (tsc는 타입 체크만)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## SDK Module

### Role
A TypeScript client SDK that collects RUM events (page views, errors, user actions, performance metrics) in the browser and sends them to the API Gateway.

### Key Files
- `src/` — SDK source (TypeScript)
- `tests/` — vitest tests
- `esbuild.config.js` — Build configuration (ESM + CJS bundles)
- `vitest.config.ts` — Test configuration
- `package.json` — Package metadata and scripts
- `tsconfig.json` — TypeScript configuration (strict mode)

### Key Commands
```bash
npm install        # Install dependencies
npm test           # Run vitest
npm run build      # esbuild bundle
```

### Rules
- Maintain TypeScript strict mode
- Browser compatibility: ES2017+, no Node.js globals
- API Key must be injected at runtime (never bundled)
- Minimize network requests with batched event transmission
- Tests use vitest (replaces jest)
- Build with esbuild (tsc for type checking only)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
