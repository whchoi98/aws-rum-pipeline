# 런북: CloudWatch 모니터링 및 알림 대응

## 개요
CloudWatch Dashboard (`rum-pipeline-dashboard`) 에서 이상 징후 감지 및 대응 절차.

## 대시보드 접근

```
https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards/dashboard/rum-pipeline-dashboard
```

## 핵심 메트릭 및 임계값

| 메트릭 | 정상 범위 | 경고 | 위험 |
|--------|----------|------|------|
| API 5xx 에러율 | < 0.1% | > 1% | > 5% |
| API 지연시간 p99 | < 500ms | > 1s | > 3s |
| Lambda 에러 | 0 | > 5/5min | > 50/5min |
| Lambda 스로틀 | 0 | > 0 | > 10/5min |
| WAF 차단 비율 | < 5% | > 20% | > 50% |
| Firehose 전송 실패 | 0 | > 0 | > 100/5min |

## 대응 절차

### API 5xx 급증
1. Ingest Lambda 로그 확인: `aws logs filter-log-events --log-group-name /aws/lambda/rum-pipeline-ingest --filter-pattern ERROR`
2. Firehose 상태 확인: 스트림이 ACTIVE인지 확인
3. Lambda 동시 실행 한도 확인

### Lambda 스로틀
1. 현재 동시 실행 수 확인
2. Reserved Concurrency 증가 검토
3. API Gateway 스로틀링 조정 (현재: burst 1000, rate 500)

### WAF 차단율 이상 증가
1. WAF 샘플 요청 확인 (AWS WAF 콘솔)
2. 정상 트래픽이 차단되는지 확인
3. Rate Limit 조정 (현재: 2000 req/5min per IP)

### Firehose 전송 실패
1. `errors/` S3 접두사에서 실패 레코드 분석
2. Transform Lambda 에러 로그 확인
3. S3 버킷 권한 확인
