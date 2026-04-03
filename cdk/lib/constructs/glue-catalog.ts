import * as cdk from 'aws-cdk-lib';
import * as glue from 'aws-cdk-lib/aws-glue';
import { Construct } from 'constructs';
import { parquetStorageDescriptor } from './helpers';

export interface GlueCatalogProps {
  projectName: string;
  s3BucketName: string;
}

export class GlueCatalog extends Construct {
  public readonly databaseName: string;
  public readonly eventsTableName: string;

  constructor(scope: Construct, id: string, props: GlueCatalogProps) {
    super(scope, id);

    const { projectName, s3BucketName } = props;
    this.databaseName = projectName.replace(/-/g, '_') + '_db';
    this.eventsTableName = 'rum_events';

    const parquetParams = { 'classification': 'parquet', 'parquet.compression': 'SNAPPY' };

    const database = new glue.CfnDatabase(this, 'Database', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseInput: {
        name: this.databaseName,
        description: `RUM Pipeline 데이터베이스 (${projectName})`,
      },
    });

    new glue.CfnTable(this, 'RumEventsTable', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseName: this.databaseName,
      tableInput: {
        name: this.eventsTableName,
        description: 'RUM 이벤트 원시 데이터',
        tableType: 'EXTERNAL_TABLE',
        parameters: parquetParams,
        storageDescriptor: parquetStorageDescriptor({
          location: `s3://${s3BucketName}/raw/`,
          columns: [
            { name: 'session_id', type: 'string' },
            { name: 'user_id', type: 'string' },
            { name: 'device_id', type: 'string' },
            { name: 'timestamp', type: 'bigint' },
            { name: 'app_version', type: 'string' },
            { name: 'event_type', type: 'string' },
            { name: 'event_name', type: 'string' },
            { name: 'payload', type: 'string' },
            { name: 'context', type: 'string' },
          ],
        }),
        partitionKeys: [
          { name: 'platform', type: 'string' },
          { name: 'year', type: 'string' },
          { name: 'month', type: 'string' },
          { name: 'day', type: 'string' },
          { name: 'hour', type: 'string' },
        ],
      },
    }).addDependency(database);

    new glue.CfnTable(this, 'HourlyMetricsTable', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseName: this.databaseName,
      tableInput: {
        name: 'rum_hourly_metrics',
        description: '시간별 집계 메트릭',
        tableType: 'EXTERNAL_TABLE',
        parameters: parquetParams,
        storageDescriptor: parquetStorageDescriptor({
          location: `s3://${s3BucketName}/aggregated/hourly/`,
          columns: [
            { name: 'metric_name', type: 'string' },
            { name: 'platform', type: 'string' },
            { name: 'period_start', type: 'bigint' },
            { name: 'p50', type: 'double' },
            { name: 'p75', type: 'double' },
            { name: 'p95', type: 'double' },
            { name: 'p99', type: 'double' },
            { name: 'count', type: 'bigint' },
            { name: 'error_count', type: 'bigint' },
            { name: 'active_users', type: 'bigint' },
          ],
        }),
        partitionKeys: [
          { name: 'metric', type: 'string' },
          { name: 'dt', type: 'string' },
        ],
      },
    }).addDependency(database);

    new glue.CfnTable(this, 'DailySummaryTable', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseName: this.databaseName,
      tableInput: {
        name: 'rum_daily_summary',
        description: '일간 요약 데이터',
        tableType: 'EXTERNAL_TABLE',
        parameters: parquetParams,
        storageDescriptor: parquetStorageDescriptor({
          location: `s3://${s3BucketName}/aggregated/daily/`,
          columns: [
            { name: 'date', type: 'string' },
            { name: 'platform', type: 'string' },
            { name: 'dau', type: 'bigint' },
            { name: 'sessions', type: 'bigint' },
            { name: 'avg_session_duration_sec', type: 'double' },
            { name: 'new_users', type: 'bigint' },
            { name: 'returning_users', type: 'bigint' },
            { name: 'top_pages', type: 'string' },
            { name: 'top_errors', type: 'string' },
            { name: 'device_distribution', type: 'string' },
            { name: 'geo_distribution', type: 'string' },
          ],
        }),
        partitionKeys: [
          { name: 'dt', type: 'string' },
        ],
      },
    }).addDependency(database);
  }
}
