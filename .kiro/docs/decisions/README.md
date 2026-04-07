# Architecture Decision Records

프로젝트의 주요 아키텍처 결정을 기록합니다.
원본은 `docs/decisions/` 디렉토리에 있습니다.

## ADR 목록

| ADR | 제목 | 상태 |
|-----|------|------|
| [ADR-001](../../docs/decisions/ADR-001-dual-iac-terraform-cdk.md) | Terraform + CDK 듀얼 IaC 지원 | Accepted |
| [ADR-002](../../docs/decisions/ADR-002-cognito-sso-lambda-edge-auth.md) | CloudFront Lambda@Edge + Cognito SSO 인증 | Accepted |
| [ADR-003](../../docs/decisions/ADR-003-grafana-premium-dashboard-kst.md) | Grafana Premium Dashboard KST | Accepted |
| [ADR-004](../../docs/decisions/ADR-004-mobile-sdk-multi-platform.md) | Mobile SDK Multi-Platform | Accepted |
| [ADR-005](../../docs/decisions/ADR-005-agent-ui-cloudfront-alb-ec2.md) | Agent UI CloudFront + ALB + EC2 | Accepted |
| [ADR-006](../../docs/decisions/ADR-006-bedrock-agentcore-rum-analytics.md) | Bedrock AgentCore RUM Analytics | Accepted |
| [ADR-007](../../docs/decisions/ADR-007-openreplay-session-replay.md) | OpenReplay Session Replay | Accepted |

## 새 ADR 작성

```bash
# 다음 번호 확인
ls docs/decisions/ADR-*.md | sort | tail -1

# 템플릿: docs/decisions/.template.md
```

### 템플릿

```markdown
# ADR-NNN: Title

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
<!-- 결정이 필요한 배경 설명 -->

## Decision
<!-- 내린 결정 -->

## Consequences
<!-- 결정의 영향 및 트레이드오프 -->
```
