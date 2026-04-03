import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as firehose from 'aws-cdk-lib/aws-kinesisfirehose';
import { Construct } from 'constructs';
import { createPipelineLambda, glueReadPolicy, LOG_RETENTION } from './helpers';

export interface FirehoseProps {
  projectName: string;
  s3Bucket: s3.IBucket;
  glueDatabaseName: string;
  glueTableName: string;
  lambdaSourceDir: string;
  bufferingSizeMb?: number;
  bufferingIntervalSec?: number;
}

export class Firehose extends Construct {
  public readonly deliveryStreamName: string;
  public readonly deliveryStreamArn: string;

  constructor(scope: Construct, id: string, props: FirehoseProps) {
    super(scope, id);

    const {
      projectName,
      s3Bucket,
      glueDatabaseName,
      glueTableName,
      lambdaSourceDir,
      bufferingSizeMb = 64,
      bufferingIntervalSec = 60,
    } = props;

    const streamName = `${projectName}-events`;
    const logGroupName = `/aws/firehose/${streamName}`;

    const transformFn = createPipelineLambda(this, 'TransformFunction', {
      projectName,
      nameSuffix: 'transform',
      sourceDir: lambdaSourceDir,
      memorySize: 256,
      timeout: cdk.Duration.seconds(60),
    });

    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
    });

    s3Bucket.grantReadWrite(firehoseRole);
    transformFn.grantInvoke(firehoseRole);
    firehoseRole.addToPolicy(glueReadPolicy(this, glueDatabaseName, [
      'glue:GetTable', 'glue:GetTableVersion', 'glue:GetTableVersions',
    ]));

    const stack = cdk.Stack.of(this);
    firehoseRole.addToPolicy(new iam.PolicyStatement({
      actions: ['logs:PutLogEvents'],
      resources: [stack.formatArn({
        service: 'logs', resource: 'log-group', resourceName: `${logGroupName}:*`, arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
      })],
    }));

    new logs.LogGroup(this, 'FirehoseLogs', {
      logGroupName,
      retention: LOG_RETENTION,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // L1 — L2 가 동적 파티셔닝 + Parquet 변환을 지원하지 않음
    const stream = new firehose.CfnDeliveryStream(this, 'DeliveryStream', {
      deliveryStreamName: streamName,
      deliveryStreamType: 'DirectPut',
      extendedS3DestinationConfiguration: {
        bucketArn: s3Bucket.bucketArn,
        roleArn: firehoseRole.roleArn,
        prefix: 'raw/platform=!{partitionKeyFromLambda:platform}/year=!{partitionKeyFromLambda:year}/month=!{partitionKeyFromLambda:month}/day=!{partitionKeyFromLambda:day}/hour=!{partitionKeyFromLambda:hour}/',
        errorOutputPrefix: 'errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/',
        bufferingHints: {
          sizeInMBs: bufferingSizeMb,
          intervalInSeconds: bufferingIntervalSec,
        },
        compressionFormat: 'UNCOMPRESSED',
        dataFormatConversionConfiguration: {
          enabled: true,
          inputFormatConfiguration: { deserializer: { openXJsonSerDe: {} } },
          outputFormatConfiguration: { serializer: { parquetSerDe: { compression: 'SNAPPY' } } },
          schemaConfiguration: {
            databaseName: glueDatabaseName,
            tableName: glueTableName,
            roleArn: firehoseRole.roleArn,
            region: cdk.Aws.REGION,
          },
        },
        processingConfiguration: {
          enabled: true,
          processors: [{
            type: 'Lambda',
            parameters: [
              { parameterName: 'LambdaArn', parameterValue: transformFn.functionArn },
              { parameterName: 'BufferSizeInMBs', parameterValue: '1' },
              { parameterName: 'BufferIntervalInSeconds', parameterValue: '60' },
            ],
          }],
        },
        dynamicPartitioningConfiguration: { enabled: true },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName,
          logStreamName: 'S3Delivery',
        },
      },
    });

    this.deliveryStreamName = streamName;
    this.deliveryStreamArn = stream.attrArn;
  }
}
