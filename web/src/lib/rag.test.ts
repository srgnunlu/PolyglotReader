import { describe, expect, it } from 'vitest';
import { rrfFusion, VectorSearchResult, BM25SearchResult } from './rag';

// RRF score for a result at zero-based `rank`, given k = 60 (RAG_CONFIG.rrfK).
const K = 60;
const rrf = (rank: number) => 1.0 / (K + rank + 1);
const VECTOR_WEIGHT = 0.65;
const BM25_WEIGHT = 0.35;

function vec(id: string, page: number | null = 1): VectorSearchResult {
  return { id, file_id: 'f', chunk_index: 0, content: `vec-${id}`, page_number: page, similarity: 0.9 };
}
function bm(id: string, page: number | null = 1): BM25SearchResult {
  return { id, file_id: 'f', chunk_index: 0, content: `bm-${id}`, page_number: page, rank: 0 };
}

describe('rrfFusion', () => {
  it('returns empty for empty inputs', () => {
    expect(rrfFusion([], [])).toEqual([]);
  });

  it('weights vector-only results by the vector weight', () => {
    const result = rrfFusion([vec('a')], []);
    expect(result).toHaveLength(1);
    expect(result[0].vectorScore).toBeCloseTo(rrf(0) * VECTOR_WEIGHT, 10);
    expect(result[0].bm25Score).toBe(0);
    expect(result[0].rrfScore).toBeCloseTo(rrf(0) * VECTOR_WEIGHT, 10);
  });

  it('weights bm25-only results by the bm25 weight', () => {
    const result = rrfFusion([], [bm('a')]);
    expect(result[0].bm25Score).toBeCloseTo(rrf(0) * BM25_WEIGHT, 10);
    expect(result[0].vectorScore).toBe(0);
  });

  it('combines scores for a chunk present in both lists', () => {
    // Chunk "a": rank 0 in vector, rank 1 in bm25.
    const result = rrfFusion([vec('a'), vec('b')], [bm('b'), bm('a')]);
    const a = result.find(c => c.id === 'a')!;
    const expected = rrf(0) * VECTOR_WEIGHT + rrf(1) * BM25_WEIGHT;
    expect(a.vectorScore).toBeCloseTo(rrf(0) * VECTOR_WEIGHT, 10);
    expect(a.bm25Score).toBeCloseTo(rrf(1) * BM25_WEIGHT, 10);
    expect(a.rrfScore).toBeCloseTo(expected, 10);
  });

  it('deduplicates: a chunk in both lists appears once', () => {
    const result = rrfFusion([vec('a')], [bm('a')]);
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('a');
  });

  it('sorts by descending rrf score', () => {
    // "shared" ranks high in both lists; "vonly"/"bonly" only appear once.
    const result = rrfFusion(
      [vec('shared'), vec('vonly')],
      [bm('shared'), bm('bonly')]
    );
    const scores = result.map(c => c.rrfScore);
    expect(scores).toEqual([...scores].sort((x, y) => y - x));
    expect(result[0].id).toBe('shared');
  });

  it('preserves page_number through fusion', () => {
    const result = rrfFusion([vec('a', 7)], []);
    expect(result[0].page_number).toBe(7);
  });
});
