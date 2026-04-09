<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Agent UI Module

### Role
CloudFront -> ALB -> EC2 아키텍처로 Bedrock AgentCore UI (Next.js)를 호스팅하는 인프라를 관리.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_cloudfront_distribution` | HTTPS 종단, Lambda@Edge 인증 (선택), ALB 오리진 |
| `aws_lb` | ALB — CloudFront에서만 접근 가능 (Managed Prefix List) |
| `aws_lb_target_group` + `aws_lb_listener` | EC2:3000 포트로 HTTP 포워딩 + 헬스체크 |
| `aws_instance` | AL2023 ARM64 EC2 — Next.js 앱 호스팅 (t4g.large 기본) |
| `aws_iam_instance_profile` | EC2 IAM (Bedrock AgentCore + SSM 접근) |
| `aws_security_group` (x2) | ALB SG (CloudFront 전용) + EC2 SG (ALB:3000만 허용) |
| `rum-agent.service` | proxy.py systemd 서비스 | AgentCore Runtime HTTP 프록시 (port 8080) |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `vpc_id` | VPC ID | - |
| `public_subnet_ids` | 퍼블릭 서브넷 목록 (ALB + EC2) | - |
| `instance_type` | EC2 인스턴스 타입 | `t4g.large` |
| `agentcore_endpoint_arn` | Bedrock AgentCore 엔드포인트 ARN | - |
| `edge_auth_qualified_arn` | Lambda@Edge 인증 함수 ARN (빈 문자열이면 비활성) | `""` |

### Rules
- ALB는 CloudFront Managed Prefix List로만 인바운드 허용 — 직접 접근 불가
- EC2 user_data에서 Node.js 20 설치, proxy.py 의존성(pip3), rum-agent systemd 서비스 등록을 수행
- CloudFront 캐시 TTL은 모두 0 — 동적 Next.js 앱이므로 캐싱하지 않음
- Lambda@Edge 인증은 `edge_auth_qualified_arn`이 빈 문자열이 아닐 때만 viewer-request에 연결
- AMI는 최신 AL2023 ARM64를 자동 조회 (`data.aws_ami`)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Agent UI Module

### Role
Manages infrastructure to host the Bedrock AgentCore UI (Next.js) via a CloudFront -> ALB -> EC2 architecture.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_cloudfront_distribution` | HTTPS termination, optional Lambda@Edge auth, ALB origin |
| `aws_lb` | ALB — accessible only from CloudFront (Managed Prefix List) |
| `aws_lb_target_group` + `aws_lb_listener` | HTTP forwarding to EC2:3000 + health checks |
| `aws_instance` | AL2023 ARM64 EC2 — hosts Next.js app (t4g.large default) |
| `aws_iam_instance_profile` | EC2 IAM (Bedrock AgentCore + SSM access) |
| `aws_security_group` (x2) | ALB SG (CloudFront only) + EC2 SG (ALB:3000 only) |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_id` | VPC ID | - |
| `public_subnet_ids` | Public subnet list (ALB + EC2) | - |
| `instance_type` | EC2 instance type | `t4g.large` |
| `agentcore_endpoint_arn` | Bedrock AgentCore endpoint ARN | - |
| `edge_auth_qualified_arn` | Lambda@Edge auth function ARN (empty string disables) | `""` |

### Rules
- ALB inbound is restricted to CloudFront Managed Prefix List only — no direct access
- EC2 user_data installs Node.js 20, proxy.py dependencies (pip3), and registers rum-agent systemd service
- CloudFront cache TTL is all 0 — no caching since this is a dynamic Next.js app
- Lambda@Edge auth is attached to viewer-request only when `edge_auth_qualified_arn` is not empty
- AMI auto-resolves to latest AL2023 ARM64 via `data.aws_ami`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
