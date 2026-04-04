# 운영 런북

프로젝트 운영 절차를 기록합니다.
원본은 `docs/runbooks/` 디렉토리에 있습니다.

## 런북 목록

| # | 제목 | 설명 |
|---|------|------|
| [01](../../docs/runbooks/01-initial-deployment.md) | 초기 배포 | Terraform 인프라 최초 배포 |
| [02](../../docs/runbooks/02-api-key-rotation.md) | API Key 로테이션 | SSM API Key 교체 절차 |
| [03](../../docs/runbooks/03-pipeline-failure-response.md) | 파이프라인 장애 대응 | Firehose/Lambda 장애 시 대응 |
| [04](../../docs/runbooks/04-grafana-management.md) | Grafana 관리 | 대시보드/사용자 관리 |
| [05](../../docs/runbooks/05-e2e-integration-test.md) | E2E 통합 테스트 | 인제스천 파이프라인 검증 |
| [06](../../docs/runbooks/06-eks-simulator-deployment.md) | EKS 시뮬레이터 배포 | CronJob 배포/관리 |
| [07](../../docs/runbooks/07-monitoring-alerting.md) | 모니터링/알림 | CloudWatch 알람 설정 |
| [08](../../docs/runbooks/08-agentcore-setup.md) | AgentCore 설정 | Bedrock AgentCore 환경 구성 |
| [09](../../docs/runbooks/09-cognito-sso-setup.md) | Cognito SSO 설정 | SSO + Lambda@Edge 인증 구성 |

## 새 런북 작성

```markdown
# Runbook: Title

## Overview
<!-- 이 런북의 목적 -->

## Prerequisites
<!-- 필요한 권한, 도구, 환경 변수 -->

## Procedure
1. Step 1
2. Step 2

## Rollback
<!-- 문제 발생 시 복구 절차 -->
```
