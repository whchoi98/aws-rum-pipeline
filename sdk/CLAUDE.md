# SDK Module

## Role
브라우저에서 RUM 이벤트(페이지뷰, 에러, 사용자 액션, 성능 지표)를 수집하고
API Gateway로 전송하는 TypeScript 클라이언트 SDK.

## Key Files
- `src/` — SDK 소스 (TypeScript)
- `tests/` — vitest 테스트
- `esbuild.config.js` — 빌드 설정 (ESM + CJS 번들)
- `vitest.config.ts` — 테스트 설정
- `package.json` — 패키지 메타데이터 및 스크립트
- `tsconfig.json` — TypeScript 설정 (strict mode)

## Key Commands
```bash
npm install        # 의존성 설치
npm test           # vitest 실행
npm run build      # esbuild 번들
```

## Rules
- TypeScript strict 모드 유지
- 브라우저 호환성: ES2017+, no Node.js globals
- API Key는 런타임 주입 (번들에 포함 금지)
- 이벤트 배치 전송으로 네트워크 요청 최소화
- 테스트는 vitest (jest 대체)
- esbuild로 빌드 (tsc는 타입 체크만)
