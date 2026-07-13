'use client';

import { memo, useMemo, useState } from 'react';
import Image from 'next/image';
import { motion, useReducedMotion } from 'framer-motion';
import {
  Check,
  Copy,
  ExternalLink,
  RefreshCw,
  RotateCcw,
  Sparkles,
  Square,
  TriangleAlert,
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { ChatMessage as ChatMessageModel } from '@/types/models';
import { linkifyPageCitations, PAGE_LINK_PREFIX } from '@/lib/chatPresentation';
import { TypingIndicator } from './TypingIndicator';

interface ChatMessageProps {
  isLastModelMessage?: boolean;
  message: ChatMessageModel;
  onNavigateToPage?: (page: number) => void;
  onRegenerate?: () => void;
  onRetry?: () => void;
}

const REMARK_PLUGINS = [remarkGfm];
const timeFormatter = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });

export const ChatMessage = memo(function ChatMessage({
  isLastModelMessage,
  message,
  onNavigateToPage,
  onRegenerate,
  onRetry,
}: ChatMessageProps) {
  const isUser = message.role === 'user';
  const isError = message.status === 'error';
  const isStreaming = message.status === 'streaming';
  const reduceMotion = useReducedMotion();
  const [copied, setCopied] = useState(false);

  const markdownComponents = useMemo(
    () => ({
      a: ({ href, children }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => {
        if (href?.startsWith(PAGE_LINK_PREFIX)) {
          const page = Number.parseInt(href.slice(PAGE_LINK_PREFIX.length), 10);
          return (
            <button
              className="mx-0.5 inline-flex items-center rounded-md bg-corio-accent-subtle px-1.5 py-0.5 font-medium text-corio-accent transition-colors hover:bg-corio-accent/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={() => Number.isFinite(page) && onNavigateToPage?.(page)}
              title={`Sayfa ${page}’ye git`}
              type="button"
            >
              {children}
            </button>
          );
        }

        return (
          <a className="inline-flex items-baseline gap-1" href={href} rel="noopener noreferrer" target="_blank">
            {children}
            <ExternalLink aria-hidden="true" className="size-3" />
          </a>
        );
      },
    }),
    [onNavigateToPage],
  );

  const handleCopy = async () => {
    if (!message.text || !navigator.clipboard) return;
    await navigator.clipboard.writeText(message.text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  };

  return (
    <motion.article
      animate={{ opacity: 1, y: 0 }}
      aria-busy={isStreaming}
      className={`group flex w-full gap-2.5 ${isUser ? 'justify-end' : 'justify-start'}`}
      data-message-role={message.role}
      initial={reduceMotion ? false : { opacity: 0, y: 8 }}
      layout="position"
      transition={{ duration: 0.2, ease: 'easeOut' }}
    >
      {!isUser && (
        <div className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-corio-accent-subtle text-corio-accent ring-1 ring-corio-accent/15">
          <Sparkles aria-hidden="true" className="size-3.5" />
        </div>
      )}

      <div className={`min-w-0 ${isUser ? 'max-w-[88%] sm:max-w-[82%]' : 'max-w-[calc(100%-2.5rem)] flex-1'}`}>
        <div
          className={
            isUser
              ? 'rounded-[20px] rounded-br-md bg-corio-accent px-4 py-2.5 text-[15px] leading-6 text-white shadow-sm'
              : isError
                ? 'rounded-2xl border border-corio-destructive/20 bg-corio-destructive/5 px-3.5 py-3 text-corio-fg'
                : 'relative rounded-[20px] rounded-bl-md border border-corio-border-subtle bg-corio-surface-1 px-4 py-3 text-[15px] leading-6 text-corio-fg shadow-sm'
          }
        >
          {message.attachment?.type === 'image' && (
            <Image
              alt="Mesaja eklenen görsel"
              className="mb-2.5 max-h-64 w-auto max-w-full rounded-xl border border-white/15 object-contain"
              height={360}
              src={`data:image/jpeg;base64,${message.attachment.content}`}
              unoptimized
              width={640}
            />
          )}

          {isError && (
            <div className="mb-1.5 flex items-center gap-2 text-sm font-medium text-corio-destructive">
              <TriangleAlert className="size-4" />
              Yanıt oluşturulamadı
            </div>
          )}

          {message.text ? (
            <div className={`prose-chat overflow-x-auto ${isUser ? '[&_a]:!text-white [&_blockquote]:!border-white/40 [&_blockquote]:!text-white/80 [&_code]:!bg-white/15' : ''}`}>
              <ReactMarkdown components={markdownComponents} remarkPlugins={REMARK_PLUGINS}>
                {isUser || !onNavigateToPage ? message.text : linkifyPageCitations(message.text)}
              </ReactMarkdown>
            </div>
          ) : (
            <TypingIndicator />
          )}

          {isStreaming && message.text && (
            <div
              aria-hidden="true"
              className="pointer-events-none absolute inset-x-3 bottom-0 h-7 bg-gradient-to-t from-corio-surface-1 to-transparent"
            />
          )}
        </div>

        {message.status === 'stopped' && (
          <div className="mt-1.5 flex items-center gap-1.5 px-1 text-[11px] text-corio-fg/45">
            <Square className="size-2.5 fill-current" />
            Yanıt durduruldu
          </div>
        )}

        {message.text && (
          <div
            className={`mt-1 flex min-h-7 items-center gap-0.5 px-1 text-corio-fg/45 transition-opacity sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100 ${isUser ? 'justify-end' : 'justify-start'}`}
          >
            <button
              aria-label={copied ? 'Kopyalandı' : 'Mesajı kopyala'}
              className="flex size-7 items-center justify-center rounded-lg transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={handleCopy}
              title={copied ? 'Kopyalandı' : 'Kopyala'}
              type="button"
            >
              {copied ? <Check className="size-3.5 text-corio-success" /> : <Copy className="size-3.5" />}
            </button>

            {isError && onRetry && (
              <button
                className="flex h-7 items-center gap-1.5 rounded-lg px-2 text-xs font-medium text-corio-accent transition-colors hover:bg-corio-accent-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
                onClick={onRetry}
                type="button"
              >
                <RotateCcw className="size-3.5" />
                Tekrar dene
              </button>
            )}

            {!isUser && !isError && isLastModelMessage && onRegenerate && !isStreaming && (
              <button
                aria-label="Yanıtı yeniden oluştur"
                className="flex size-7 items-center justify-center rounded-lg transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
                onClick={onRegenerate}
                title="Yanıtı yeniden oluştur"
                type="button"
              >
                <RefreshCw className="size-3.5" />
              </button>
            )}

            <time className="ml-1 text-[10px] tabular-nums" dateTime={message.timestamp.toISOString()}>
              {timeFormatter.format(message.timestamp)}
            </time>
          </div>
        )}
      </div>
    </motion.article>
  );
});
