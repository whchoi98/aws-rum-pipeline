import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

// ─── 공유 상수 ───

export const LAMBDA_RUNTIME = lambda.Runtime.PYTHON_3_12;
export const LAMBDA_HANDLER = 'handler.handler';
export const LOG_RETENTION = logs.RetentionDays.TWO_WEEKS;

// ─── Python Lambda 팩토리 ───

export interface PipelineLambdaProps {
  projectName: string;
  nameSuffix: string;
  sourceDir: string;
  memorySize?: number;
  timeout?: cdk.Duration;
  environment?: Record<string, string>;
}

/** Python Lambda + 자동 Role + 로그 보존 2주 */
export function createPipelineLambda(
  scope: Construct,
  id: string,
  props: PipelineLambdaProps,
): lambda.Function {
  return new lambda.Function(scope, id, {
    functionName: `${props.projectName}-${props.nameSuffix}`,
    runtime: LAMBDA_RUNTIME,
    handler: LAMBDA_HANDLER,
    code: lambda.Code.fromAsset(props.sourceDir),
    memorySize: props.memorySize ?? 128,
    timeout: props.timeout ?? cdk.Duration.seconds(30),
    environment: props.environment,
    logRetention: LOG_RETENTION,
  });
}

// ─── IAM 헬퍼 ───

/** Glue catalog/database/table 읽기 정책 */
export function glueReadPolicy(
  scope: Construct,
  databaseName: string,
  actions: string[] = ['glue:GetTable', 'glue:GetTables', 'glue:GetDatabase', 'glue:GetPartitions'],
): iam.PolicyStatement {
  const stack = cdk.Stack.of(scope);
  return new iam.PolicyStatement({
    actions,
    resources: [
      stack.formatArn({ service: 'glue', resource: 'catalog' }),
      stack.formatArn({ service: 'glue', resource: 'database', resourceName: databaseName }),
      stack.formatArn({ service: 'glue', resource: 'table', resourceName: `${databaseName}/*` }),
    ],
  });
}

/** Athena workgroup 실행 정책 */
export function athenaExecPolicy(
  scope: Construct,
  workgroupName: string,
  actions: string[] = [
    'athena:StartQueryExecution',
    'athena:GetQueryExecution',
    'athena:GetQueryResults',
    'athena:StopQueryExecution',
  ],
): iam.PolicyStatement {
  const stack = cdk.Stack.of(scope);
  return new iam.PolicyStatement({
    actions,
    resources: [
      stack.formatArn({ service: 'athena', resource: 'workgroup', resourceName: workgroupName }),
    ],
  });
}

// ─── Glue 테이블 스토리지 디스크립터 헬퍼 ───

export interface ParquetTableConfig {
  location: string;
  columns: Array<{ name: string; type: string }>;
}

/** Parquet 외부 테이블용 공통 StorageDescriptor */
export function parquetStorageDescriptor(config: ParquetTableConfig) {
  return {
    location: config.location,
    inputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
    outputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
    serdeInfo: {
      serializationLibrary: 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe',
      parameters: { 'serialization.format': '1' },
    },
    columns: config.columns,
  };
}
