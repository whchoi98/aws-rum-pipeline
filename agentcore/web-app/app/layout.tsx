import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'RUM 분석 에이전트',
  description: 'AI 기반 RUM 데이터 분석 도구',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
