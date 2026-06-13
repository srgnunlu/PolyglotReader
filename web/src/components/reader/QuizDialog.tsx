// Quiz dialog — web port of the iOS QuizView. Generates a 5-question
// multiple-choice quiz from the document text, then walks the user through
// question → answer reveal → explanation → result, mirroring the mobile flow.
'use client';

import { useCallback, useEffect, useState } from 'react';
import type { pdfjs } from 'react-pdf';
import {
  Loader2,
  Brain,
  AlertTriangle,
  Check,
  X as XIcon,
  Lightbulb,
  ArrowRight,
  RotateCcw,
} from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { QuizQuestion } from '@/types/models';
import { extractPdfText } from '@/lib/pdfText';
import { generateQuiz } from '@/lib/quiz';

interface QuizDialogProps {
  pdf: pdfjs.PDFDocumentProxy | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function QuizDialog({ pdf, open, onOpenChange }: QuizDialogProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [questions, setQuestions] = useState<QuizQuestion[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [score, setScore] = useState(0);
  const [selectedAnswer, setSelectedAnswer] = useState<number | null>(null);
  const [isAnswered, setIsAnswered] = useState(false);
  const [showResult, setShowResult] = useState(false);

  const resetState = useCallback(() => {
    setCurrentIndex(0);
    setScore(0);
    setSelectedAnswer(null);
    setIsAnswered(false);
    setShowResult(false);
  }, []);

  // Generate a fresh quiz whenever the dialog opens.
  useEffect(() => {
    if (!open || !pdf) return;
    let cancelled = false;

    const load = async () => {
      setIsLoading(true);
      setError(null);
      setQuestions([]);
      resetState();
      try {
        const context = await extractPdfText(pdf);
        const result = await generateQuiz(context);
        if (!cancelled) setQuestions(result);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Quiz oluşturulamadı');
        }
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };
    load();
    return () => {
      cancelled = true;
    };
  }, [open, pdf, resetState]);

  const currentQuestion = questions[currentIndex];
  const isLastQuestion = currentIndex === questions.length - 1;
  const scorePercentage =
    questions.length > 0 ? Math.round((score / questions.length) * 100) : 0;

  const selectAnswer = (index: number) => {
    if (isAnswered || !currentQuestion) return;
    setSelectedAnswer(index);
    setIsAnswered(true);
    if (index === currentQuestion.correctAnswerIndex) {
      setScore(prev => prev + 1);
    }
  };

  const nextQuestion = () => {
    if (isLastQuestion) {
      setShowResult(true);
      return;
    }
    setCurrentIndex(prev => prev + 1);
    setSelectedAnswer(null);
    setIsAnswered(false);
  };

  const restart = () => resetState();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Brain className="size-5 text-corio-accent" />
            Bilgi Sınavı
          </DialogTitle>
          <DialogDescription>
            Bu dokümandaki temel kavramları test eden bir quiz.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex flex-col items-center gap-3 py-12 text-sm text-corio-fg/60">
            <Loader2 className="size-7 animate-spin text-corio-accent" />
            Sorular hazırlanıyor...
          </div>
        ) : error || questions.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-10 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-corio-destructive/10">
              <AlertTriangle className="size-6 text-corio-destructive" />
            </div>
            <p className="text-sm text-corio-fg/70">
              {error || 'Bu dokümandan quiz oluşturulamadı.'}
            </p>
          </div>
        ) : showResult ? (
          <ResultView
            score={score}
            total={questions.length}
            percentage={scorePercentage}
            onRestart={restart}
            onClose={() => onOpenChange(false)}
          />
        ) : currentQuestion ? (
          <div className="space-y-4">
            {/* Progress + score */}
            <div className="flex items-center justify-between text-xs text-corio-fg/50">
              <span>
                Soru {currentIndex + 1} / {questions.length}
              </span>
              <span>Puan: {score}</span>
            </div>

            {/* Question */}
            <p className="text-base font-semibold leading-relaxed text-corio-fg">
              {currentQuestion.question}
            </p>

            {/* Options */}
            <div className="space-y-2">
              {currentQuestion.options.map((option, index) => (
                <OptionButton
                  key={index}
                  text={option}
                  isSelected={selectedAnswer === index}
                  isCorrect={index === currentQuestion.correctAnswerIndex}
                  isAnswered={isAnswered}
                  onClick={() => selectAnswer(index)}
                />
              ))}
            </div>

            {/* Explanation */}
            {isAnswered && currentQuestion.explanation && (
              <div className="space-y-1 rounded-xl border border-corio-border bg-corio-surface-2 p-3">
                <div className="flex items-center gap-1.5 text-xs font-medium text-corio-accent">
                  <Lightbulb className="size-3.5" />
                  Açıklama
                </div>
                <p className="text-sm leading-relaxed text-corio-fg/70">
                  {currentQuestion.explanation}
                </p>
              </div>
            )}

            {/* Next */}
            {isAnswered && (
              <button
                onClick={nextQuestion}
                className="flex w-full items-center justify-center gap-1.5 rounded-xl bg-corio-accent py-2.5 text-sm font-medium text-white transition-colors hover:bg-corio-accent-hover"
              >
                {isLastQuestion ? 'Bitir' : 'Sonraki'}
                <ArrowRight className="size-4" />
              </button>
            )}
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}

interface OptionButtonProps {
  text: string;
  isSelected: boolean;
  isCorrect: boolean;
  isAnswered: boolean;
  onClick: () => void;
}

function OptionButton({ text, isSelected, isCorrect, isAnswered, onClick }: OptionButtonProps) {
  // Before answering: neutral, with the selected option accented.
  // After answering: correct → green, wrongly-picked → red, others muted.
  let stateClass =
    'border-corio-border bg-corio-surface-1 text-corio-fg hover:bg-corio-surface-2';
  if (!isAnswered && isSelected) {
    stateClass = 'border-corio-accent bg-corio-accent/10 text-corio-fg';
  } else if (isAnswered && isCorrect) {
    stateClass = 'border-green-500 bg-green-500/10 text-corio-fg';
  } else if (isAnswered && isSelected) {
    stateClass = 'border-corio-destructive bg-corio-destructive/10 text-corio-fg';
  } else if (isAnswered) {
    stateClass = 'border-corio-border bg-corio-surface-1 text-corio-fg/50';
  }

  return (
    <button
      onClick={onClick}
      disabled={isAnswered}
      className={`flex w-full items-center justify-between gap-2 rounded-xl border px-3.5 py-2.5 text-left text-sm transition-colors disabled:cursor-default ${stateClass}`}
    >
      <span className="leading-relaxed">{text}</span>
      {isAnswered && isCorrect && <Check className="size-4 shrink-0 text-green-600" />}
      {isAnswered && isSelected && !isCorrect && (
        <XIcon className="size-4 shrink-0 text-corio-destructive" />
      )}
    </button>
  );
}

interface ResultViewProps {
  score: number;
  total: number;
  percentage: number;
  onRestart: () => void;
  onClose: () => void;
}

function ResultView({ score, total, percentage, onRestart, onClose }: ResultViewProps) {
  return (
    <div className="flex flex-col items-center gap-5 py-6 text-center">
      {/* Score ring */}
      <div className="relative flex size-32 items-center justify-center">
        <svg className="size-32 -rotate-90" viewBox="0 0 120 120">
          <circle
            cx="60"
            cy="60"
            r="52"
            fill="none"
            stroke="var(--corio-border)"
            strokeWidth="10"
          />
          <circle
            cx="60"
            cy="60"
            r="52"
            fill="none"
            stroke="var(--corio-accent)"
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={2 * Math.PI * 52}
            strokeDashoffset={2 * Math.PI * 52 * (1 - percentage / 100)}
          />
        </svg>
        <span className="absolute text-2xl font-bold text-corio-accent">%{percentage}</span>
      </div>

      <div className="space-y-1">
        <p className="text-lg font-semibold text-corio-fg">Quiz Tamamlandı</p>
        <p className="text-sm text-corio-fg/60">
          {total} sorudan {score} doğru
        </p>
      </div>

      <div className="flex w-full gap-2">
        <button
          onClick={onRestart}
          className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-corio-border bg-corio-surface-2 py-2.5 text-sm font-medium text-corio-fg transition-colors hover:bg-corio-surface-3"
        >
          <RotateCcw className="size-4" />
          Tekrar Çöz
        </button>
        <button
          onClick={onClose}
          className="flex-1 rounded-xl bg-corio-accent py-2.5 text-sm font-medium text-white transition-colors hover:bg-corio-accent-hover"
        >
          Kapat
        </button>
      </div>
    </div>
  );
}
