import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { Construct } from 'constructs';

export interface AgentUiProps {
  projectName: string;
  vpcId: string;
  publicSubnetIds: string[];
  agentcoreEndpointArn: string;
  instanceType?: string;
  edgeAuthFunction?: cloudfront.experimental.EdgeFunction;
}

export class AgentUi extends Construct {
  public readonly cloudfrontUrl: string;
  public readonly cloudfrontDomainName: string;

  constructor(scope: Construct, id: string, props: AgentUiProps) {
    super(scope, id);

    const {
      projectName,
      vpcId,
      publicSubnetIds,
      agentcoreEndpointArn,
      instanceType = 't4g.large',
    } = props;

    // ─── VPC 참조 ───
    const vpc = ec2.Vpc.fromLookup(this, 'Vpc', { vpcId });

    const subnets = publicSubnetIds.map((subnetId, i) =>
      ec2.Subnet.fromSubnetId(this, `Subnet${i}`, subnetId),
    );

    // ─── Security Groups ───
    const albSg = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc,
      description: 'ALB - CloudFront 접근만 허용',
      allowAllOutbound: true,
    });
    // CloudFront Managed Prefix List로 제한
    albSg.addIngressRule(
      ec2.Peer.prefixList('pl-22a6434b'), // CloudFront 서울 리전
      ec2.Port.tcp(80),
      'CloudFront only',
    );

    const ec2Sg = new ec2.SecurityGroup(this, 'Ec2Sg', {
      vpc,
      description: 'EC2 - ALB에서만 접근',
      allowAllOutbound: true,
    });
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(3000), 'ALB only');

    // ─── IAM Role ───
    const role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // AgentCore + Bedrock 권한 (최소 권한으로 제한)
    role.addToPolicy(new iam.PolicyStatement({
      actions: [
        'bedrock-agentcore:InvokeAgent',
        'bedrock:InvokeModel',
        'bedrock:InvokeModelWithResponseStream',
      ],
      resources: [agentcoreEndpointArn, `arn:${cdk.Aws.PARTITION}:bedrock:${cdk.Aws.REGION}::foundation-model/anthropic.*`],
    }));

    // ─── EC2 인스턴스 ───
    const ami = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    const instance = new ec2.Instance(this, 'Instance', {
      vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ami,
      securityGroup: ec2Sg,
      role,
      vpcSubnets: { subnets },
      userData: ec2.UserData.custom(`#!/bin/bash
set -e
# Node.js 20 설치
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs
mkdir -p /opt/agent-ui
chown ec2-user:ec2-user /opt/agent-ui
cat > /etc/systemd/system/agent-ui.service <<'SVC'
[Unit]
Description=RUM Agent UI
After=network.target
[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/agent-ui
ExecStart=/usr/bin/node server.js
Restart=on-failure
Environment=PORT=3000
Environment=AGENTCORE_ENDPOINT_ARN=${agentcoreEndpointArn}
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
`),
    });

    // ─── ALB ───
    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      vpc,
      internetFacing: true,
      securityGroup: albSg,
      vpcSubnets: { subnets },
    });

    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      vpc,
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2_targets.InstanceTarget(instance, 3000)],
      healthCheck: {
        path: '/',
        interval: cdk.Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    alb.addListener('HttpListener', {
      port: 80,
      defaultTargetGroups: [targetGroup],
    });

    // ─── CloudFront ───
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
        origin: new origins.HttpOrigin(alb.loadBalancerDnsName, {
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
        edgeLambdas: edgeLambdas.length > 0 ? edgeLambdas : undefined,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
    });

    this.cloudfrontUrl = `https://${distribution.distributionDomainName}`;
    this.cloudfrontDomainName = distribution.distributionDomainName;

    new cdk.CfnOutput(this, 'AgentUiUrl', {
      value: this.cloudfrontUrl,
      description: 'Agent UI CloudFront URL',
    });
  }
}
