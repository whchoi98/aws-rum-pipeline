#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RumPipelineStack } from '../lib/rum-pipeline-stack';

const app = new cdk.App();

// 컨텍스트에서 환경 설정 읽기
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: app.node.tryGetContext('region') || 'ap-northeast-2',
};

new RumPipelineStack(app, 'RumPipelineStack', {
  env,
  // cdk.json 또는 --context로 전달
  projectName: app.node.tryGetContext('projectName') || 'rum-pipeline',
  environment: app.node.tryGetContext('environment') || 'dev',
  vpcId: app.node.tryGetContext('vpcId'),
  publicSubnetIds: app.node.tryGetContext('publicSubnetIds'),
  agentcoreEndpointArn: app.node.tryGetContext('agentcoreEndpointArn'),
  allowedOrigins: app.node.tryGetContext('allowedOrigins') || ['*'],
});
