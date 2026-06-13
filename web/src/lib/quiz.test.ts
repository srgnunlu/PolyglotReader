import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanJsonResponse, parseQuizResponse, generateQuiz } from './quiz';

const VALID_QUIZ = {
  questions: [
    {
      id: 1,
      question: 'Soru 1?',
      options: ['A', 'B', 'C', 'D'],
      correctAnswerIndex: 2,
      explanation: 'Çünkü C doğru.',
    },
    {
      id: 2,
      question: 'Soru 2?',
      options: ['Evet', 'Hayır'],
      correctAnswerIndex: 0,
    },
  ],
};

describe('cleanJsonResponse', () => {
  it('strips ```json fences', () => {
    const wrapped = '```json\n{"questions":[]}\n```';
    expect(cleanJsonResponse(wrapped)).toBe('{"questions":[]}');
  });

  it('strips plain ``` fences', () => {
    expect(cleanJsonResponse('```\n{"a":1}\n```')).toBe('{"a":1}');
  });

  it('trims prose around the JSON object', () => {
    const noisy = 'İşte quiz:\n{"questions":[]}\nUmarım yardımcı olur.';
    expect(cleanJsonResponse(noisy)).toBe('{"questions":[]}');
  });
});

describe('parseQuizResponse', () => {
  it('parses valid questions and preserves fields', () => {
    const result = parseQuizResponse(JSON.stringify(VALID_QUIZ));
    expect(result).toHaveLength(2);
    expect(result[0].correctAnswerIndex).toBe(2);
    expect(result[0].explanation).toBe('Çünkü C doğru.');
    expect(result[1].explanation).toBeUndefined();
  });

  it('parses a fenced response', () => {
    const result = parseQuizResponse('```json\n' + JSON.stringify(VALID_QUIZ) + '\n```');
    expect(result).toHaveLength(2);
  });

  it('drops malformed questions but keeps valid ones', () => {
    const mixed = {
      questions: [
        VALID_QUIZ.questions[0],
        { question: 'no options' }, // invalid
        { question: 'bad index', options: ['A', 'B'], correctAnswerIndex: 9 }, // out of range
      ],
    };
    const result = parseQuizResponse(JSON.stringify(mixed));
    expect(result).toHaveLength(1);
    expect(result[0].question).toBe('Soru 1?');
  });

  it('assigns a fallback id when the model omits it', () => {
    const noId = {
      questions: [{ question: 'Q', options: ['A', 'B'], correctAnswerIndex: 1 }],
    };
    const result = parseQuizResponse(JSON.stringify(noId));
    expect(result[0].id).toBe(1);
  });

  it('throws when the payload has no questions array', () => {
    expect(() => parseQuizResponse('{"foo":1}')).toThrow();
  });

  it('throws when no question is valid', () => {
    const allBad = { questions: [{ question: 'x' }] };
    expect(() => parseQuizResponse(JSON.stringify(allBad))).toThrow();
  });
});

describe('generateQuiz', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('throws on empty context without calling the API', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    await expect(generateQuiz('   ')).rejects.toThrow();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('sends the context to the generate route and returns questions', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ text: JSON.stringify(VALID_QUIZ) }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await generateQuiz('Önemli bir belge metni');

    expect(result).toHaveLength(2);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('/api/gemini/generate');
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body.prompt).toContain('Önemli bir belge metni');
    expect(body.prompt).toContain('çoktan seçmeli');
  });
});
