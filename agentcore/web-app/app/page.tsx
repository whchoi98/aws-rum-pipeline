'use client';

import { useState, useRef, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface Message {
  role: 'user' | 'bot';
  content: string;
}

const QUICK_QUESTIONS = [
  { label: '📊 오늘 현황', text: '오늘 전체 현황을 알려주세요' },
  { label: '🐢 느린 페이지', text: 'LCP가 4초 넘는 페이지를 찾아주세요' },
  { label: '🚨 에러 분석', text: '에러율이 높은 원인을 분석해주세요' },
  { label: '📱 플랫폼 비교', text: 'iOS vs Android 성능 비교해주세요' },
  { label: '📈 일간 비교', text: '어제 대비 오늘 변화를 분석해주세요' },
  { label: '🌐 브라우저별', text: '가장 많은 에러가 발생하는 브라우저는?' },
];

// ─── 다운로드 유틸리티 ─────────────────────────────────────────────────────────
function downloadBlob(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function getTimestamp() {
  return new Date().toISOString().slice(0, 16).replace('T', '_').replace(':', '');
}

function stripStatusLines(text: string): string {
  const STATUS_PATTERNS = ['조회 중', '분석 중', '조회 완료', '추가 조회', '리포트를 생성중', 'Athena', 'CW Logs', 'Metrics', 'Alarms', 'Glue', 'Grafana', 'SNS'];
  return text.split('\n').filter(line => {
    const t = line.trim();
    if (!t) return true;
    if (t === '---') return false;
    if (t.length < 50 && STATUS_PATTERNS.some(p => t.includes(p)) && (t.includes('...') || t.includes('완료'))) return false;
    return true;
  }).join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

function downloadMarkdown(content: string) {
  downloadBlob(`rum-analysis-${getTimestamp()}.md`, stripStatusLines(content), 'text/markdown;charset=utf-8');
}

function downloadRendered(msgId: string, mode: 'pdf' | 'word') {
  // 렌더링된 마크다운 DOM을 복제하여 PDF/Word로 출력
  const source = document.getElementById(msgId);
  if (!source) return;

  const PRINT_STYLES = [
    'body { font-family: "Malgun Gothic", -apple-system, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; color: #1a1a1a; }',
    'h1 { font-size: 16pt; border-bottom: 2px solid #1f6feb; padding-bottom: 4px; }',
    'h2 { font-size: 14pt; color: #1f6feb; }',
    'h3 { font-size: 12pt; }',
    'table { border-collapse: collapse; width: 100%; margin: 8px 0; }',
    'th, td { border: 1px solid #d0d7de; padding: 6px 10px; text-align: left; font-size: 10pt; }',
    'th { background: #f6f8fa; font-weight: 600; }',
    'pre { background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 12px; overflow-x: auto; font-size: 9pt; white-space: pre-wrap; }',
    'code { background: #f0f0f0; padding: 2px 4px; border-radius: 3px; font-size: 9pt; }',
    'pre code { background: none; padding: 0; }',
    'strong { color: #1a1a1a; }',
    'ul, ol { padding-left: 20px; }',
    'p { margin: 4px 0; line-height: 1.6; }',
    '@media print { body { padding: 0; } }',
  ].join('\n');

  const cloned = source.cloneNode(true) as HTMLElement;
  // 상태 메시지 DOM 요소 제거 + 다크 테마 색상 제거
  const STATUS_KW = ['조회 중', '분석 중', '조회 완료', '추가 조회', '리포트를 생성중'];
  cloned.querySelectorAll('p').forEach(p => {
    const t = (p.textContent || '').trim();
    if (t.length < 50 && STATUS_KW.some(k => t.includes(k))) p.remove();
    else if (t.length < 50 && (t.includes('완료') || t.includes('...'))) p.remove();
  });
  cloned.querySelectorAll('hr').forEach(hr => hr.remove());
  cloned.querySelectorAll('*').forEach(el => {
    (el as HTMLElement).style.color = '';
    (el as HTMLElement).style.background = '';
    (el as HTMLElement).style.backgroundColor = '';
  });

  if (mode === 'word') {
    const html = [
      '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word">',
      '<head><meta charset="utf-8"><style>' + PRINT_STYLES + '</style></head><body>',
      '<h1>RUM 분석 리포트</h1>',
      '<p style="color:#666;font-size:9pt;">',
      `생성: ${new Date().toLocaleString('ko-KR')} | 모델: Claude Sonnet 4.6</p><hr>`,
      cloned.outerHTML,
      '</body></html>',
    ].join('\n');
    downloadBlob(`rum-analysis-${getTimestamp()}.doc`, html, 'application/msword;charset=utf-8');
    return;
  }

  // PDF: 인쇄 다이얼로그
  const printWindow = window.open('', '_blank');
  if (!printWindow) return;
  const doc = printWindow.document;
  const meta = doc.createElement('meta');
  meta.setAttribute('charset', 'utf-8');
  doc.head.appendChild(meta);
  doc.title = 'RUM Analysis Report';
  const style = doc.createElement('style');
  style.textContent = PRINT_STYLES;
  doc.head.appendChild(style);
  const h1 = doc.createElement('h1');
  h1.textContent = 'RUM 분석 리포트';
  doc.body.appendChild(h1);
  const info = doc.createElement('p');
  info.style.cssText = 'color:#666;font-size:9pt;';
  info.textContent = `생성: ${new Date().toLocaleString('ko-KR')} | 모델: Claude Sonnet 4.6 | DB: rum_pipeline_db`;
  doc.body.appendChild(info);
  doc.body.appendChild(doc.createElement('hr'));
  doc.body.appendChild(cloned);
  setTimeout(() => { printWindow.print(); }, 300);
}

// ─── 다운로드 버튼 컴포넌트 ──────────────────────────────────────────────────
function DownloadMenu({ content, msgId }: { content: string; msgId: string }) {
  const [open, setOpen] = useState(false);

  if (!content || content.startsWith('\u26A0')) return null;

  return (
    <div style={{ position: 'relative', display: 'inline-block', marginTop: '8px' }}>
      <button style={dlStyles.toggle} onClick={() => setOpen(!open)}>
        {'📥 다운로드 '}{open ? '▲' : '▼'}
      </button>
      {open && (
        <div style={dlStyles.menu}>
          <button style={dlStyles.item} onClick={() => { downloadMarkdown(content); setOpen(false); }}>
            {'📝 Markdown (.md)'}
          </button>
          <button style={dlStyles.item} onClick={() => { downloadRendered(msgId, 'pdf'); setOpen(false); }}>
            {'📄 PDF (렌더링)'}
          </button>
          <button style={dlStyles.item} onClick={() => { downloadRendered(msgId, 'word'); setOpen(false); }}>
            {'📃 Word (렌더링)'}
          </button>
        </div>
      )}
    </div>
  );
}

const dlStyles: Record<string, React.CSSProperties> = {
  toggle: { background: '#21262d', border: '1px solid #30363d', color: '#8b949e', padding: '4px 10px', borderRadius: '6px', fontSize: '12px', cursor: 'pointer' },
  menu: { position: 'absolute', bottom: '100%', left: 0, marginBottom: '4px', background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '4px', zIndex: 10, display: 'flex', flexDirection: 'column', gap: '2px', minWidth: '160px' },
  item: { background: 'none', border: 'none', color: '#c9d1d9', padding: '8px 12px', fontSize: '13px', cursor: 'pointer', textAlign: 'left', borderRadius: '6px', whiteSpace: 'nowrap' },
};

// ─── 메인 컴포넌트 ──────────────────────────────────────────────────────────
export default function Home() {
  const [messages, setMessages] = useState<Message[]>([
    {
      role: 'bot',
      content:
        '안녕하세요! **RUM 분석 에이전트**입니다.\n\n실시간 사용자 모니터링 데이터를 자연어로 분석할 수 있습니다.\n아래 빠른 질문을 클릭하거나 직접 질문을 입력해 주세요.',
    },
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [streaming, setStreaming] = useState('');
  const [sessionId] = useState(() => `session-${Date.now()}`);
  const chatRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages, streaming]);

  const sendMessage = async (text?: string) => {
    const message = text || input.trim();
    if (!message || loading) return;

    setInput('');
    setMessages((prev) => [...prev, { role: 'user', content: message }]);
    setLoading(true);
    setStreaming('');

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt: message, sessionId }),
      });

      if (!res.ok) {
        const errorText = await res.text().catch(() => res.statusText);
        setMessages((prev) => [...prev, { role: 'bot', content: `\u26A0\uFE0F 서버 오류 (${res.status}): ${errorText}` }]);
        setStreaming('');
        setLoading(false);
        return;
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      let accumulated = '';
      let buffer = '';

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });

          const events = buffer.split('\n\n');
          buffer = events.pop() || '';

          for (const event of events) {
            const lines = event.split('\n');
            for (const line of lines) {
              if (line.startsWith(':')) continue;
              if (!line.startsWith('data: ')) continue;
              try {
                const data = JSON.parse(line.slice(6));
                if (data.type === 'chunk') {
                  accumulated += data.content;
                  setStreaming(accumulated);
                } else if (data.type === 'error') {
                  accumulated += `\n\n\u26A0\uFE0F 오류: ${data.content}`;
                  setStreaming(accumulated);
                }
              } catch {
                // JSON 파싱 실패
              }
            }
          }
        }
      }

      setMessages((prev) => [...prev, { role: 'bot', content: accumulated || '응답을 받지 못했습니다.' }]);
      setStreaming('');
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: 'bot', content: `\u26A0\uFE0F 연결 오류: ${err instanceof Error ? err.message : '알 수 없는 오류'}` },
      ]);
      setStreaming('');
    }
    setLoading(false);
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <h1 style={styles.title}>RUM 분석 에이전트</h1>
          <span style={styles.poweredBy}>Powered by Amazon Bedrock AgentCore</span>
        </div>
        <div style={{ display: 'flex', gap: '8px', marginLeft: 'auto' }}>
          <span style={styles.badge}>Agentic AI</span>
          <span style={styles.badge2}>Claude Sonnet 4.6</span>
        </div>
      </header>

      <div ref={chatRef} style={styles.chatArea}>
        {messages.map((msg, i) => (
          <div key={i} style={{ ...styles.message, flexDirection: msg.role === 'user' ? 'row-reverse' : 'row' }}>
            <div style={{ ...styles.avatar, background: msg.role === 'bot' ? '#1f6feb' : '#238636' }}>
              {msg.role === 'bot' ? '\uD83E\uDD16' : '\uD83D\uDC64'}
            </div>
            <div style={{ maxWidth: msg.role === 'user' ? '75%' : '80%' }}>
              <div style={msg.role === 'user' ? styles.userBubble : styles.botBubble}>
                {msg.role === 'bot' ? (
                  <div className="markdown-body" id={`bot-msg-${i}`}>
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{msg.content}</ReactMarkdown>
                  </div>
                ) : (
                  msg.content
                )}
              </div>
              {msg.role === 'bot' && i > 0 && <DownloadMenu content={msg.content} msgId={`bot-msg-${i}`} />}
            </div>
          </div>
        ))}
        {streaming && (
          <div style={styles.message}>
            <div style={{ ...styles.avatar, background: '#1f6feb' }}>{'\uD83E\uDD16'}</div>
            <div style={styles.botBubble}>
              <div className="markdown-body">
                <ReactMarkdown remarkPlugins={[remarkGfm]}>{streaming}</ReactMarkdown>
              </div>
            </div>
          </div>
        )}
        {loading && !streaming && (
          <div style={styles.message}>
            <div style={{ ...styles.avatar, background: '#1f6feb' }}>{'\uD83E\uDD16'}</div>
            <div style={styles.botBubble}>분석 중...</div>
          </div>
        )}
      </div>

      <div style={styles.inputArea}>
        <div style={styles.inputWrapper}>
          <textarea
            style={styles.textarea}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
              }
            }}
            placeholder="RUM 데이터에 대해 물어보세요..."
            rows={1}
          />
          <button
            style={{ ...styles.sendBtn, ...(loading || !input.trim() ? styles.sendBtnDisabled : {}) }}
            onClick={() => sendMessage()}
            disabled={loading || !input.trim()}
          >
            전송
          </button>
        </div>
        <div style={styles.quickActions}>
          {QUICK_QUESTIONS.map((q) => (
            <button key={q.label} style={styles.quickBtn} onClick={() => sendMessage(q.text)}>
              {q.label}
            </button>
          ))}
        </div>
        <div style={styles.statusBar}>
          <span>모델: Claude Sonnet 4.6</span>
          <span>DB: rum_pipeline_db</span>
          <span>리전: ap-northeast-2</span>
          <span>세션: {sessionId.slice(-8)}</span>
        </div>
      </div>

      <style>{`
        .markdown-body { color: #c9d1d9; line-height: 1.6; }
        .markdown-body table { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 13px; }
        .markdown-body th, .markdown-body td { border: 1px solid #30363d; padding: 6px 10px; text-align: left; }
        .markdown-body th { background: #21262d; font-weight: 600; }
        .markdown-body pre { background: #0d1117; border: 1px solid #30363d; border-radius: 8px; padding: 12px; overflow-x: auto; }
        .markdown-body code { background: #21262d; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
        .markdown-body pre code { background: none; padding: 0; }
        .markdown-body strong { color: #f0f6fc; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3 { color: #f0f6fc; margin: 12px 0 8px; }
        .markdown-body ul, .markdown-body ol { padding-left: 20px; margin: 4px 0; }
        .markdown-body p { margin: 4px 0; }
        button:hover { opacity: 0.85; }
      `}</style>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: { display: 'flex', flexDirection: 'column', height: '100vh', background: '#0d1117', color: '#c9d1d9', fontFamily: '-apple-system, sans-serif' },
  header: { background: '#161b22', borderBottom: '1px solid #30363d', padding: '16px 24px', display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '8px' },
  title: { fontSize: '18px', fontWeight: 600, color: '#f0f6fc', margin: 0 },
  poweredBy: { fontSize: '11px', color: '#8b949e', fontStyle: 'italic' },
  badge: { background: '#238636', color: '#fff', fontSize: '11px', padding: '2px 8px', borderRadius: '12px', fontWeight: 500 },
  badge2: { background: '#1f6feb', color: '#fff', fontSize: '11px', padding: '2px 8px', borderRadius: '12px', fontWeight: 500 },
  chatArea: { flex: 1, overflow: 'auto', padding: '16px', display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '900px', width: '100%', margin: '0 auto' },
  message: { display: 'flex', gap: '12px' },
  avatar: { width: '36px', height: '36px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '16px', flexShrink: 0 },
  botBubble: { padding: '12px 16px', borderRadius: '12px', background: '#161b22', border: '1px solid #30363d', fontSize: '14px' },
  userBubble: { padding: '12px 16px', borderRadius: '12px', background: '#1f6feb', color: '#fff', fontSize: '14px', whiteSpace: 'pre-wrap' as const },
  inputArea: { padding: '16px', borderTop: '1px solid #30363d', maxWidth: '900px', width: '100%', margin: '0 auto' },
  inputWrapper: { display: 'flex', gap: '8px', background: '#161b22', border: '1px solid #30363d', borderRadius: '12px', padding: '8px 12px' },
  textarea: { flex: 1, background: 'none', border: 'none', color: '#c9d1d9', fontSize: '14px', fontFamily: 'inherit', resize: 'none' as const, outline: 'none', lineHeight: 1.5 },
  sendBtn: { background: '#1f6feb', color: '#fff', border: 'none', borderRadius: '8px', padding: '8px 16px', fontSize: '14px', cursor: 'pointer' },
  sendBtnDisabled: { background: '#30363d', cursor: 'not-allowed' },
  quickActions: { display: 'flex', gap: '8px', marginTop: '8px', flexWrap: 'wrap' as const },
  quickBtn: { background: '#21262d', border: '1px solid #30363d', color: '#8b949e', padding: '6px 12px', borderRadius: '20px', fontSize: '12px', cursor: 'pointer' },
  statusBar: { display: 'flex', gap: '16px', fontSize: '11px', color: '#484f58', padding: '8px 0' },
};
