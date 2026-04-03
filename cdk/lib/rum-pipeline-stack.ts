import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { S3DataLake } from './constructs/s3-data-lake';
import { GlueCatalog } from './constructs/glue-catalog';
import { Firehose } from './constructs/firehose';
import { Security } from './constructs/security';
import { ApiGateway } from './constructs/api-gateway';
import { Monitoring } from './constructs/monitoring';
import { Grafana } from './constructs/grafana';
import { PartitionRepair } from './constructs/partition-repair';
import { AthenaQuery } from './constructs/athena-query';
import { AgentUi } from './constructs/agent-ui';

export interface RumPipelineStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
  vpcId?: string;
  publicSubnetIds?: string[];
  agentcoreEndpointArn?: string;
  allowedOrigins?: string[];
}

export class RumPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RumPipelineStackProps) {
    super(scope, id, props);

    const {
      projectName,
      environment: envName,
      vpcId,
      publicSubnetIds,
      agentcoreEndpointArn,
      allowedOrigins = ['*'],
    } = props;

    // Lambda 소스 경로 (cdk/ 기준 상대 경로)
    const lambdaBase = `${__dirname}/../../lambda`;

    // ─── 1. S3 Data Lake ───
    const dataLake = new S3DataLake(this, 'S3DataLake', {
      projectName,
    });

    // ─── 2. Glue Catalog ───
    const glueCatalog = new GlueCatalog(this, 'GlueCatalog', {
      projectName,
      s3BucketName: dataLake.bucket.bucketName,
    });

    // ─── 3. Firehose ───
    const firehose = new Firehose(this, 'Firehose', {
      projectName,
      s3Bucket: dataLake.bucket,
      glueDatabaseName: glueCatalog.databaseName,
      glueTableName: glueCatalog.eventsTableName,
      lambdaSourceDir: `${lambdaBase}/transform`,
    });

    // ─── 4. Security (WAF + Authorizer) ───
    const security = new Security(this, 'Security', {
      projectName,
      environment: envName,
      lambdaSourceDir: `${lambdaBase}/authorizer`,
    });

    // ─── 5. API Gateway ───
    const apiGw = new ApiGateway(this, 'ApiGateway', {
      projectName,
      firehoseStreamName: firehose.deliveryStreamName,
      firehoseStreamArn: firehose.deliveryStreamArn,
      lambdaSourceDir: `${lambdaBase}/ingest`,
      allowedOrigins,
      authorizerFunction: security.authorizerFunction,
      wafAclArn: security.wafAclArn,
    });

    // ─── 6. Grafana + Athena Workgroup ───
    const grafana = new Grafana(this, 'Grafana', {
      projectName,
      s3Bucket: dataLake.bucket,
      glueDatabaseName: glueCatalog.databaseName,
    });

    // ─── 7. Monitoring ───
    new Monitoring(this, 'Monitoring', {
      projectName,
      apiId: apiGw.apiId,
      firehoseStreamName: firehose.deliveryStreamName,
    });

    // ─── 8. Partition Repair ───
    new PartitionRepair(this, 'PartitionRepair', {
      projectName,
      glueDatabaseName: glueCatalog.databaseName,
      glueTableName: glueCatalog.eventsTableName,
      athenaWorkgroup: grafana.athenaWorkgroupName,
      s3Bucket: dataLake.bucket,
      lambdaSourceDir: `${lambdaBase}/partition-repair`,
    });

    // ─── 9. Athena Query (AgentCore 용) ───
    const athenaQuery = new AthenaQuery(this, 'AthenaQuery', {
      projectName,
      glueDatabaseName: glueCatalog.databaseName,
      athenaWorkgroup: grafana.athenaWorkgroupName,
      s3Bucket: dataLake.bucket,
      lambdaSourceDir: `${lambdaBase}/athena-query`,
    });

    // ─── 10. Agent UI (선택) ───
    if (vpcId && publicSubnetIds && agentcoreEndpointArn) {
      new AgentUi(this, 'AgentUi', {
        projectName,
        vpcId,
        publicSubnetIds,
        agentcoreEndpointArn,
      });
    }

    // ─── Outputs ───
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: apiGw.apiEndpoint,
      description: 'RUM API Gateway 엔드포인트',
    });
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: dataLake.bucket.bucketName,
      description: 'S3 Data Lake 버킷',
    });
    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueCatalog.databaseName,
      description: 'Glue 데이터베이스',
    });
    new cdk.CfnOutput(this, 'AthenaWorkgroup', {
      value: grafana.athenaWorkgroupName,
      description: 'Athena 워크그룹',
    });
    new cdk.CfnOutput(this, 'AthenaQueryFunctionName', {
      value: athenaQuery.functionName,
      description: 'Athena Query Lambda (AgentCore 연동)',
    });
  }
}
