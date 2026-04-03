import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

export interface MonitoringProps {
  projectName: string;
  apiId: string;
  firehoseStreamName?: string;
}

const PERIOD = cdk.Duration.minutes(5);

function apiMetric(apiId: string, metricName: string, statistic: string): cloudwatch.Metric {
  return new cloudwatch.Metric({
    namespace: 'AWS/ApiGateway', metricName, statistic, period: PERIOD,
    dimensionsMap: { ApiId: apiId },
  });
}

function lambdaMetric(functionName: string, metricName: string, statistic: string): cloudwatch.Metric {
  return new cloudwatch.Metric({
    namespace: 'AWS/Lambda', metricName, statistic, period: PERIOD,
    dimensionsMap: { FunctionName: functionName },
  });
}

export class Monitoring extends Construct {
  public readonly dashboardName: string;

  constructor(scope: Construct, id: string, props: MonitoringProps) {
    super(scope, id);

    const { projectName, apiId } = props;
    const firehoseStreamName = props.firehoseStreamName ?? `${projectName}-events`;
    this.dashboardName = `${projectName}-dashboard`;

    const lambdaNames = ['authorizer', 'ingest', 'transform', 'partition-repair', 'athena-query']
      .map(suffix => `${projectName}-${suffix}`);

    const dashboard = new cloudwatch.Dashboard(this, 'Dashboard', {
      dashboardName: this.dashboardName,
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'API 요청 수',
        left: [apiMetric(apiId, 'Count', 'Sum')],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: 'API 4xx/5xx 에러',
        left: [apiMetric(apiId, '4xx', 'Sum'), apiMetric(apiId, '5xx', 'Sum')],
        width: 8,
      }),
      new cloudwatch.GraphWidget({
        title: 'API 지연시간 (p50/p90/p99)',
        left: ['p50', 'p90', 'p99'].map(s => apiMetric(apiId, 'Latency', s)),
        width: 8,
      }),
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda 호출 수',
        left: lambdaNames.map(fn => lambdaMetric(fn, 'Invocations', 'Sum')),
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda 에러',
        left: lambdaNames.map(fn => lambdaMetric(fn, 'Errors', 'Sum')),
        width: 12,
      }),
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda 실행 시간 (Average)',
        left: lambdaNames.map(fn => lambdaMetric(fn, 'Duration', 'Average')),
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda 동시 실행 & 스로틀',
        left: lambdaNames.map(fn => lambdaMetric(fn, 'ConcurrentExecutions', 'Maximum')),
        width: 12,
      }),
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'WAF 허용/차단',
        left: ['AllowedRequests', 'BlockedRequests'].map(m =>
          new cloudwatch.Metric({
            namespace: 'AWS/WAFV2', metricName: m, statistic: 'Sum', period: PERIOD,
            dimensionsMap: { WebACL: `${projectName}-waf`, Rule: 'ALL', Region: cdk.Aws.REGION },
          }),
        ),
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Firehose 수신/전송',
        left: ['IncomingRecords', 'DeliveryToS3.Records'].map(m =>
          new cloudwatch.Metric({
            namespace: 'AWS/Firehose', metricName: m, statistic: 'Sum', period: PERIOD,
            dimensionsMap: { DeliveryStreamName: firehoseStreamName },
          }),
        ),
        width: 12,
      }),
    );
  }
}
