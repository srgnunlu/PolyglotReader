'use client';

import { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import { ArrowUp, ImagePlus, Quote, Square, X } from 'lucide-react';
import { normalizeChatDraft } from '@/lib/chatPresentation';

interface ChatInputProps {
  activeSelection?: string | null;
  allowsAttachments?: boolean;
  attachment?: string | null;
  autoFocus?: boolean;
  draft: string;
  isLoading: boolean;
  onAttachmentChange: (attachment: string | null) => void;
  onDraftChange: (draft: string) => void;
  onRemoveSelection?: () => void;
  onStop: () => void;
  onSubmit: () => void;
  placeholder?: string;
}

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MAX_IMAGE_DIMENSION = 1600;

function readBlobAsBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error ?? new Error('Görsel okunamadı.'));
    reader.onload = () => {
      const result = typeof reader.result === 'string' ? reader.result : '';
      resolve(result.slice(result.indexOf(',') + 1));
    };
    reader.readAsDataURL(blob);
  });
}

async function prepareImage(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) throw new Error('Yalnızca görsel dosyaları eklenebilir.');
  if (file.size > MAX_IMAGE_BYTES) throw new Error('Görsel 8 MB’dan küçük olmalı.');

  if (typeof createImageBitmap !== 'function') return readBlobAsBase64(file);

  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, MAX_IMAGE_DIMENSION / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  const context = canvas.getContext('2d');
  if (!context) {
    bitmap.close();
    return readBlobAsBase64(file);
  }
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();

  const blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.84));
  return readBlobAsBase64(blob ?? file);
}

export function ChatInput({
  activeSelection,
  allowsAttachments = true,
  attachment,
  autoFocus,
  draft,
  isLoading,
  onAttachmentChange,
  onDraftChange,
  onRemoveSelection,
  onStop,
  onSubmit,
  placeholder,
}: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [attachmentError, setAttachmentError] = useState<string | null>(null);
  const canSubmit = normalizeChatDraft(draft, Boolean(attachment)) !== null;

  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;
    textarea.style.height = '0px';
    textarea.style.height = `${Math.min(textarea.scrollHeight, 144)}px`;
  }, [draft]);

  useEffect(() => {
    if (!autoFocus) return;
    const timeout = window.setTimeout(() => textareaRef.current?.focus(), 180);
    return () => window.clearTimeout(timeout);
  }, [autoFocus]);

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    if (!isLoading && canSubmit) onSubmit();
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      if (!isLoading && canSubmit) onSubmit();
    }
  };

  const handleImageChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;

    setAttachmentError(null);
    try {
      onAttachmentChange(await prepareImage(file));
      textareaRef.current?.focus();
    } catch (error) {
      setAttachmentError(error instanceof Error ? error.message : 'Görsel eklenemedi.');
    }
  };

  return (
    <form className="px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-2 sm:px-4" onSubmit={handleSubmit}>
      <div className="mx-auto max-w-3xl rounded-[22px] border border-corio-border bg-corio-surface-1 p-2 shadow-[0_10px_35px_rgba(42,37,32,0.10)] transition-shadow focus-within:border-corio-accent/55 focus-within:shadow-[0_12px_40px_rgba(212,113,60,0.14)]">
        {activeSelection && (
          <div className="mb-2 flex items-start gap-2 rounded-2xl border border-corio-accent/15 bg-corio-accent-subtle px-3 py-2 text-xs text-corio-fg/70">
            <Quote className="mt-0.5 size-3.5 shrink-0 text-corio-accent" />
            <p className="line-clamp-3 flex-1 leading-relaxed">{activeSelection}</p>
            <button
              aria-label="Seçili metni kaldır"
              className="flex size-6 shrink-0 items-center justify-center rounded-full text-corio-fg/45 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={onRemoveSelection}
              type="button"
            >
              <X className="size-3.5" />
            </button>
          </div>
        )}

        {attachment && (
          <div className="relative mb-2 ml-1 w-fit">
            <Image
              alt="Gönderilecek görsel"
              className="h-20 max-w-36 rounded-xl border border-corio-border object-cover shadow-sm"
              height={80}
              src={`data:image/jpeg;base64,${attachment}`}
              unoptimized
              width={144}
            />
            <button
              aria-label="Görseli kaldır"
              className="absolute -right-2 -top-2 flex size-7 items-center justify-center rounded-full border-2 border-corio-surface-1 bg-corio-fg text-corio-bg shadow-sm transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={() => onAttachmentChange(null)}
              type="button"
            >
              <X className="size-3.5" />
            </button>
          </div>
        )}

        <textarea
          aria-label="Mesaj"
          className="block min-h-11 max-h-36 w-full resize-none overflow-y-auto bg-transparent px-2 py-2 text-[15px] leading-6 text-corio-fg outline-none placeholder:text-corio-fg/38"
          maxLength={8000}
          onChange={event => onDraftChange(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={
            placeholder ?? (attachment
              ? 'Görsel hakkında bir şey sor…'
              : activeSelection
                ? 'Seçili bölüm hakkında sor…'
                : 'Belge hakkında bir şey sor…')
          }
          ref={textareaRef}
          rows={1}
          value={draft}
        />

        <div className="flex items-center justify-between gap-2 pl-1">
          <div className="flex items-center gap-1">
            {allowsAttachments && (
              <>
                <input
                  accept="image/*"
                  className="sr-only"
                  onChange={handleImageChange}
                  ref={fileInputRef}
                  type="file"
                />
                <button
                  aria-label="Görsel ekle"
                  className="flex size-9 items-center justify-center rounded-xl text-corio-fg/55 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 disabled:opacity-40"
                  disabled={isLoading}
                  onClick={() => fileInputRef.current?.click()}
                  title="Görsel ekle"
                  type="button"
                >
                  <ImagePlus className="size-[18px]" />
                </button>
              </>
            )}
            <span className="hidden text-[11px] text-corio-fg/35 sm:inline">Enter gönderir · Shift+Enter satır açar</span>
          </div>

          {isLoading ? (
            <button
              aria-label="Yanıtı durdur"
              className="flex size-9 items-center justify-center rounded-full bg-corio-fg text-corio-bg shadow-sm transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={onStop}
              title="Yanıtı durdur"
              type="button"
            >
              <Square className="size-3.5 fill-current" />
            </button>
          ) : (
            <button
              aria-label="Mesaj gönder"
              className="flex size-9 items-center justify-center rounded-full bg-corio-accent text-white shadow-sm transition-all hover:scale-105 hover:bg-corio-accent-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 disabled:cursor-not-allowed disabled:bg-corio-surface-3 disabled:text-corio-fg/35 disabled:shadow-none"
              disabled={!canSubmit}
              title="Gönder"
              type="submit"
            >
              <ArrowUp className="size-[18px] stroke-[2.5]" />
            </button>
          )}
        </div>
      </div>

      {attachmentError ? (
        <p className="mx-auto mt-1.5 max-w-3xl px-2 text-xs text-corio-destructive" role="alert">
          {attachmentError}
        </p>
      ) : (
        <p className="mx-auto mt-1.5 max-w-3xl text-center text-[10px] leading-4 text-corio-fg/35">
          Corio hata yapabilir; önemli bilgileri belgeden doğrulayın.
        </p>
      )}
    </form>
  );
}
