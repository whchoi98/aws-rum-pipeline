<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: EKS Simulator CronJob 배포

### 개요
EKS 클러스터에 RUM 트래픽 시뮬레이터를 CronJob으로 배포하여 5분 간격 자동 트래픽 생성.

### 사전 조건
- EKS 클러스터 kubeconfig 설정 완료
- ECR에 `rum-simulator` 이미지 빌드/푸시 완료

### 이미지 빌드 및 푸시

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

# ECR 로그인
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# 이미지 빌드 및 푸시
cd simulator
docker build -t rum-simulator .
docker tag rum-simulator:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-simulator:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-simulator:latest
```

### CronJob 배포

```bash
# kubeconfig 설정
aws eks update-kubeconfig --name <your-cluster-name> --region ap-northeast-2

# 네임스페이스 생성
kubectl create namespace rum 2>/dev/null || true

# API Key 시크릿 생성
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text)
kubectl create secret generic rum-api-key \
  --from-literal=api-key="${API_KEY}" -n rum 2>/dev/null || true

# CronJob 배포 (cronjob.yaml의 이미지/엔드포인트를 환경에 맞게 수정 후)
kubectl apply -f simulator/k8s/cronjob.yaml -n rum
```

### 검증

```bash
# CronJob 상태
kubectl get cronjob -n rum

# 최근 실행 결과
kubectl get jobs -n rum --sort-by=.metadata.creationTimestamp | tail -5

# Pod 로그
kubectl logs -n rum $(kubectl get pods -n rum --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

### 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| ImagePullBackOff | ECR 권한 없음 | EKS 노드 IAM 역할에 ECR 읽기 추가 |
| CrashLoopBackOff | API Key 시크릿 누락 | `kubectl get secret rum-api-key -n rum` 확인 |
| 0 events sent | 잘못된 API 엔드포인트 | cronjob.yaml의 RUM_API_ENDPOINT 확인 |

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: EKS Simulator CronJob Deployment

### Overview
Deploy the RUM traffic simulator as a CronJob on an EKS cluster to automatically generate traffic every 5 minutes.

### Prerequisites
- EKS cluster kubeconfig configured
- `rum-simulator` image built and pushed to ECR

### Build and Push Image

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

# ECR login
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build and push image
cd simulator
docker build -t rum-simulator .
docker tag rum-simulator:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-simulator:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-simulator:latest
```

### Deploy CronJob

```bash
# Configure kubeconfig
aws eks update-kubeconfig --name <your-cluster-name> --region ap-northeast-2

# Create namespace
kubectl create namespace rum 2>/dev/null || true

# Create API Key secret
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text)
kubectl create secret generic rum-api-key \
  --from-literal=api-key="${API_KEY}" -n rum 2>/dev/null || true

# Deploy CronJob (update image/endpoint in cronjob.yaml for your environment first)
kubectl apply -f simulator/k8s/cronjob.yaml -n rum
```

### Verification

```bash
# CronJob status
kubectl get cronjob -n rum

# Recent execution results
kubectl get jobs -n rum --sort-by=.metadata.creationTimestamp | tail -5

# Pod logs
kubectl logs -n rum $(kubectl get pods -n rum --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

### Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| ImagePullBackOff | No ECR permissions | Add ECR read access to EKS node IAM role |
| CrashLoopBackOff | API Key secret missing | Verify with `kubectl get secret rum-api-key -n rum` |
| 0 events sent | Incorrect API endpoint | Check RUM_API_ENDPOINT in cronjob.yaml |

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
