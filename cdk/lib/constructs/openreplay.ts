import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface OpenReplayProps {
  projectName: string;
  environment: string;
  vpcId: string;
  publicSubnetIds: string[];
  privateSubnetIds: string[];
  instanceType?: string;
  dbInstanceClass?: string;
  edgeAuthFunction?: cloudfront.experimental.EdgeFunction;
}

export class OpenReplay extends Construct {
  public readonly cloudfrontDomain: string;
  public readonly ingestEndpoint: string;

  constructor(scope: Construct, id: string, props: OpenReplayProps) {
    super(scope, id);

    const {
      projectName,
      environment: envName,
      vpcId,
      publicSubnetIds,
      privateSubnetIds,
      instanceType = 'm7g.xlarge',
      dbInstanceClass = 'db.t4g.medium',
    } = props;

    // ─── VPC 참조 ───
    const vpc = ec2.Vpc.fromLookup(this, 'Vpc', { vpcId });

    const publicSubnets = publicSubnetIds.map((subnetId, i) =>
      ec2.Subnet.fromSubnetId(this, `PublicSubnet${i}`, subnetId),
    );
    const privateSubnets = privateSubnetIds.map((subnetId, i) =>
      ec2.Subnet.fromSubnetId(this, `PrivateSubnet${i}`, subnetId),
    );

    // ─── S3 버킷 (세션 녹화 저장) ───
    const recordingsBucket = new s3.Bucket(this, 'RecordingsBucket', {
      bucketName: `${projectName}-openreplay-recordings-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [
        {
          id: 'recordings-lifecycle',
          transitions: [
            { storageClass: s3.StorageClass.INFREQUENT_ACCESS, transitionAfter: cdk.Duration.days(30) },
            { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
    });

    // ─── Security Groups ───

    // ALB SG — CloudFront Prefix List에서만 80 포트 허용
    const albSg = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc,
      description: 'OpenReplay ALB - CloudFront 접근만 허용',
      allowAllOutbound: true,
    });
    albSg.addIngressRule(
      ec2.Peer.prefixList('pl-22a6434b'), // CloudFront 서울 리전
      ec2.Port.tcp(80),
      'CloudFront only',
    );

    // EC2 SG — ALB에서 80(대시보드) + 9443(ingest) 허용
    const ec2Sg = new ec2.SecurityGroup(this, 'Ec2Sg', {
      vpc,
      description: 'OpenReplay EC2 - ALB에서만 접근',
      allowAllOutbound: true,
    });
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(80), 'Dashboard from ALB');
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(9443), 'Ingest from ALB');

    // RDS SG — EC2에서만 5432 허용
    const rdsSg = new ec2.SecurityGroup(this, 'RdsSg', {
      vpc,
      description: 'OpenReplay RDS - EC2에서만 접근',
      allowAllOutbound: true,
    });
    rdsSg.addIngressRule(ec2Sg, ec2.Port.tcp(5432), 'PostgreSQL from EC2 only');

    // Redis SG — EC2에서만 6379 허용
    const redisSg = new ec2.SecurityGroup(this, 'RedisSg', {
      vpc,
      description: 'OpenReplay Redis - EC2에서만 접근',
      allowAllOutbound: true,
    });
    redisSg.addIngressRule(ec2Sg, ec2.Port.tcp(6379), 'Redis from EC2 only');

    // ─── RDS PostgreSQL 16 ───
    const dbInstance = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: new ec2.InstanceType(dbInstanceClass),
      vpc,
      vpcSubnets: { subnets: privateSubnets },
      securityGroups: [rdsSg],
      databaseName: 'openreplay',
      credentials: rds.Credentials.fromGeneratedSecret('openreplay', {
        secretName: `/rum-pipeline/${envName}/openreplay/db-credentials`,
      }),
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      multiAz: envName === 'prod',
      backupRetention: cdk.Duration.days(7),
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // ─── ElastiCache Redis 7.1 (CfnCacheCluster + CfnSubnetGroup) ───
    const redisSubnetGroup = new elasticache.CfnSubnetGroup(this, 'RedisSubnetGroup', {
      description: `${projectName} OpenReplay Redis subnet group`,
      subnetIds: privateSubnetIds,
      cacheSubnetGroupName: `${projectName}-openreplay-redis`,
    });

    const redisCluster = new elasticache.CfnCacheCluster(this, 'RedisCluster', {
      clusterName: `${projectName}-or-redis`,
      engine: 'redis',
      engineVersion: '7.1',
      cacheNodeType: 'cache.t4g.micro',
      numCacheNodes: 1,
      cacheSubnetGroupName: redisSubnetGroup.cacheSubnetGroupName!,
      vpcSecurityGroupIds: [redisSg.securityGroupId],
    });
    redisCluster.addDependency(redisSubnetGroup);

    // ─── IAM Role ───
    const role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // S3 녹화 버킷 접근 정책
    recordingsBucket.grantReadWrite(role);

    // SSM Parameter Store 읽기 정책 (OpenReplay 시크릿)
    role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'ssm:GetParameter',
        'ssm:GetParameters',
        'ssm:GetParametersByPath',
      ],
      resources: [
        `arn:${cdk.Aws.PARTITION}:ssm:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:parameter/rum-pipeline/${envName}/openreplay/*`,
      ],
    }));

    // RDS 시크릿 읽기 권한
    if (dbInstance.secret) {
      dbInstance.secret.grantRead(role);
    }

    // ─── EC2 인스턴스 ───
    const ami = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    // DB 엔드포인트와 Redis 엔드포인트를 UserData에 전달
    const userData = ec2.UserData.custom(`#!/bin/bash
set -euo pipefail

REGION="${cdk.Aws.REGION}"
ENVIRONMENT="${envName}"
RDS_ENDPOINT="${dbInstance.dbInstanceEndpointAddress}"
REDIS_ENDPOINT="${redisCluster.attrRedisEndpointAddress}"
S3_BUCKET="${recordingsBucket.bucketName}"

echo "=== OpenReplay 설치 시작 ==="

# Docker + Docker Compose v2 설치
dnf update -y
dnf install -y docker git jq
systemctl enable docker
systemctl start docker

mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
curl -SL "https://github.com/docker/compose/releases/download/\${COMPOSE_VERSION}/docker-compose-linux-aarch64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# DB 비밀번호 읽기 (Secrets Manager)
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "/rum-pipeline/\${ENVIRONMENT}/openreplay/db-credentials" \
  --region "\${REGION}" \
  --query 'SecretString' --output text | jq -r '.password')

# JWT 시크릿 읽기/생성
JWT_SECRET=$(aws ssm get-parameter \
  --name "/rum-pipeline/\${ENVIRONMENT}/openreplay/jwt-secret" \
  --with-decryption --region "\${REGION}" \
  --query 'Parameter.Value' --output text 2>/dev/null || true)

if [ -z "\${JWT_SECRET}" ]; then
  JWT_SECRET=$(openssl rand -hex 32)
  aws ssm put-parameter \
    --name "/rum-pipeline/\${ENVIRONMENT}/openreplay/jwt-secret" \
    --type SecureString --value "\${JWT_SECRET}" --region "\${REGION}"
fi

# OpenReplay 리포지토리 클론
cd /opt
git clone https://github.com/openreplay/openreplay.git
cd openreplay

# 외부 서비스 사용 시 내장 컨테이너 비활성화
cat > docker-compose.override.yml << 'OVERRIDE'
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]
OVERRIDE

# .env 파일 설정
cat > .env << ENV
ENVIRONMENT=\${ENVIRONMENT}
AWS_REGION=\${REGION}
POSTGRES_HOST=\${RDS_ENDPOINT}
POSTGRES_PORT=5432
POSTGRES_DB=openreplay
POSTGRES_USER=openreplay
POSTGRES_PASSWORD=\${DB_PASSWORD}
REDIS_HOST=\${REDIS_ENDPOINT}
REDIS_PORT=6379
S3_BUCKET=\${S3_BUCKET}
S3_REGION=\${REGION}
JWT_SECRET=\${JWT_SECRET}
ENV

docker compose up -d

echo "=== OpenReplay 설치 완료 ==="
`);

    const instance = new ec2.Instance(this, 'Instance', {
      vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ami,
      securityGroup: ec2Sg,
      role,
      vpcSubnets: { subnets: publicSubnets },
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(50, { volumeType: ec2.EbsDeviceVolumeType.GP3 }),
        },
      ],
      userData,
    });

    // DB, Redis 준비 후 EC2 시작
    instance.node.addDependency(dbInstance);
    instance.node.addDependency(redisCluster);

    // ─── ALB ───
    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      vpc,
      internetFacing: true,
      securityGroup: albSg,
      vpcSubnets: { subnets: publicSubnets },
    });

    // 대시보드 타겟 그룹 (포트 80)
    const dashboardTg = new elbv2.ApplicationTargetGroup(this, 'DashboardTg', {
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2_targets.InstanceTarget(instance, 80)],
      healthCheck: {
        path: '/',
        interval: cdk.Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Ingest 타겟 그룹 (포트 9443)
    const ingestTg = new elbv2.ApplicationTargetGroup(this, 'IngestTg', {
      vpc,
      port: 9443,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2_targets.InstanceTarget(instance, 9443)],
      healthCheck: {
        path: '/',
        interval: cdk.Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // HTTP 리스너 — 기본: 대시보드
    const listener = alb.addListener('HttpListener', {
      port: 80,
      defaultTargetGroups: [dashboardTg],
    });

    // /ingest/* 규칙 → ingest 타겟 그룹
    listener.addTargetGroups('IngestRule', {
      priority: 100,
      conditions: [elbv2.ListenerCondition.pathPatterns(['/ingest/*'])],
      targetGroups: [ingestTg],
    });

    // ─── CloudFront ───

    // /ingest/* 동작 — Lambda@Edge 인증 없이 통과 (SDK 데이터 수집용)
    const albOrigin = new origins.HttpOrigin(alb.loadBalancerDnsName, {
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
    });

    // 기본 동작 — 대시보드 (선택적 Lambda@Edge SSO 인증)
    const edgeLambdas: cloudfront.EdgeLambda[] = [];
    if (props.edgeAuthFunction) {
      edgeLambdas.push({
        eventType: cloudfront.LambdaEdgeEventType.VIEWER_REQUEST,
        functionVersion: props.edgeAuthFunction.currentVersion,
        includeBody: false,
      });
    }

    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: albOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
        edgeLambdas: edgeLambdas.length > 0 ? edgeLambdas : undefined,
      },
      additionalBehaviors: {
        '/ingest/*': {
          origin: albOrigin,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
          // /ingest/* 는 Lambda@Edge 인증 없음 (SDK 데이터 수집용)
        },
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
    });

    this.cloudfrontDomain = distribution.distributionDomainName;
    this.ingestEndpoint = `https://${distribution.distributionDomainName}/ingest`;

    new cdk.CfnOutput(this, 'OpenReplayUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'OpenReplay Session Replay URL',
    });

    new cdk.CfnOutput(this, 'IngestEndpoint', {
      value: this.ingestEndpoint,
      description: 'OpenReplay Tracker Ingest Endpoint',
    });
  }
}
