// Quiz generation — web port of the iOS GeminiAnalysisService.generateQuiz.
// Builds the same Turkish multiple-choice prompt, sends it through the
// server-side /api/gemini/generate route (so the API key stays on the server),
// then cleans and parses the model's JSON reply into QuizQuestion[].
import { generateRaw } from './gemini';
import { QuizQuestion } from '@/types/models';

// Keep the context budget aligned with the mobile app (context.prefix(15000)).
const MAX_CONTEXT_CHARS = 15000;

// Builds the quiz prompt. Matches the mobile wording so both platforms produce
// comparable quizzes.
function buildQuizPrompt(context: string): string {
  return `Aşağıdaki metne dayalı 5 soruluk çoktan seçmeli bir quiz oluştur.
Her soru temel kavramları test etmeli.

JSON formatında döndür:
{
    "questions": [
        {
            "id": 1,
            "question": "Soru metni",
            "options": ["A şıkkı", "B şıkkı", "C şıkkı", "D şıkkı"],
            "correctAnswerIndex": 0,
            "explanation": "Açıklama"
        }
    ]
}

Metin:
${context.slice(0, MAX_CONTEXT_CHARS)}`;
}

// Strips Markdown code fences the model often wraps JSON in, and trims to the
// outermost { } so trailing prose can't break JSON.parse. Mirrors iOS cleanJSON.
export function cleanJsonResponse(text: string): string {
  let cleaned = text.trim();
  cleaned = cleaned.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();

  const firstBrace = cleaned.indexOf('{');
  const lastBrace = cleaned.lastIndexOf('}');
  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    cleaned = cleaned.slice(firstBrace, lastBrace + 1);
  }
  return cleaned;
}

// Validates the shape of a single decoded question, discarding anything the
// model returned malformed rather than rendering a broken quiz card.
function isValidQuestion(value: unknown): value is QuizQuestion {
  if (!value || typeof value !== 'object') return false;
  const q = value as Record<string, unknown>;
  return (
    typeof q.question === 'string' &&
    q.question.trim().length > 0 &&
    Array.isArray(q.options) &&
    q.options.length >= 2 &&
    q.options.every(opt => typeof opt === 'string') &&
    typeof q.correctAnswerIndex === 'number' &&
    q.correctAnswerIndex >= 0 &&
    q.correctAnswerIndex < q.options.length
  );
}

export function parseQuizResponse(raw: string): QuizQuestion[] {
  const parsed = JSON.parse(cleanJsonResponse(raw)) as { questions?: unknown };
  if (!parsed || !Array.isArray(parsed.questions)) {
    throw new Error('Quiz yanıtı beklenen formatta değil');
  }

  const questions = parsed.questions
    .filter(isValidQuestion)
    .map((q, index) => ({
      id: typeof q.id === 'number' ? q.id : index + 1,
      question: q.question,
      options: q.options,
      correctAnswerIndex: q.correctAnswerIndex,
      explanation: typeof q.explanation === 'string' ? q.explanation : undefined,
    }));

  if (questions.length === 0) {
    throw new Error('Geçerli soru üretilemedi');
  }
  return questions;
}

/**
 * Generates a multiple-choice quiz from document text. Throws on empty context,
 * AI failure, or an unparseable reply so the UI can surface an error state.
 */
export async function generateQuiz(context: string): Promise<QuizQuestion[]> {
  if (!context.trim()) {
    throw new Error('Quiz oluşturmak için yeterli metin yok');
  }
  const raw = await generateRaw(buildQuizPrompt(context));
  return parseQuizResponse(raw);
}
