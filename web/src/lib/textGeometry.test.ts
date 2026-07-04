import { describe, expect, it } from 'vitest';
import {
  assembleReadingOrderText,
  clusterColumnBoundaries,
  groupIntoLines,
  joinLinesMergingHyphens,
  type PositionedText,
} from './textGeometry';

const PAGE_WIDTH = 595;

function item(text: string, left: number, top: number, height = 12): PositionedText {
  return { text, left, top, height, right: left + text.length * 6 };
}

describe('clusterColumnBoundaries', () => {
  it('finds the gutter between two columns', () => {
    const boundaries = clusterColumnBoundaries([50, 52, 320, 322], PAGE_WIDTH);
    expect(boundaries).toHaveLength(1);
    expect(boundaries[0]).toBeGreaterThan(52);
    expect(boundaries[0]).toBeLessThan(320);
  });

  it('treats small indentation steps as one column', () => {
    expect(clusterColumnBoundaries([50, 70, 90], PAGE_WIDTH)).toEqual([]);
  });
});

describe('groupIntoLines', () => {
  it('groups items with near-equal tops and orders lines top-down, items left-right', () => {
    const lines = groupIntoLines([
      item('world', 60, 101), // 1px jitter, same line as "hello"
      item('second', 10, 120),
      item('hello', 10, 100),
    ]);
    expect(lines.map(line => line.map(i => i.text))).toEqual([
      ['hello', 'world'],
      ['second'],
    ]);
  });
});

describe('joinLinesMergingHyphens', () => {
  it('merges a hyphen break followed by a lowercase continuation', () => {
    expect(joinLinesMergingHyphens(['bilgi-', 'lendirme süreci'])).toBe('bilgilendirme süreci');
  });

  it('merges the U+2010 unicode hyphen too', () => {
    expect(joinLinesMergingHyphens(['know‐', 'ledge'])).toBe('knowledge');
  });

  it('keeps the hyphen before an uppercase continuation', () => {
    expect(joinLinesMergingHyphens(['X-', 'Ray'])).toBe('X- Ray');
  });

  it('handles Turkish lowercase after a hyphen break', () => {
    expect(joinLinesMergingHyphens(['değerlendir-', 'ilmesi'])).toBe('değerlendirilmesi');
  });

  it('skips empty lines', () => {
    expect(joinLinesMergingHyphens(['bir', '', 'iki'])).toBe('bir iki');
  });
});

describe('assembleReadingOrderText', () => {
  it('emits column 1 fully before column 2 on a two-column page', () => {
    const text = assembleReadingOrderText(
      [
        item('acil servis', 50, 100),
        item('hasta sayısı', 320, 100),
        item('triyaj puanı', 50, 112),
        item('yatak durumu', 320, 112),
      ],
      PAGE_WIDTH
    );
    expect(text).toBe('acil servis triyaj puanı hasta sayısı yatak durumu');
  });

  it('joins runs split mid-word (tiny gap) without a space', () => {
    const trans: PositionedText = { text: 'trans', left: 10, top: 100, height: 12, right: 40 };
    const lation: PositionedText = { text: 'lation', left: 40.5, top: 100, height: 12, right: 76 };
    expect(assembleReadingOrderText([trans, lation], PAGE_WIDTH)).toBe('translation');
  });

  it('separates runs with a word-sized gap by a space', () => {
    const first: PositionedText = { text: 'acil', left: 10, top: 100, height: 12, right: 34 };
    const second: PositionedText = { text: 'servis', left: 44, top: 100, height: 12, right: 80 };
    expect(assembleReadingOrderText([first, second], PAGE_WIDTH)).toBe('acil servis');
  });

  it('merges a hyphenated break across a column boundary', () => {
    const text = assembleReadingOrderText(
      [
        item('değerlendir-', 50, 700), // bottom of column 1
        item('ilmesi gerekir', 320, 100), // top of column 2
      ],
      PAGE_WIDTH
    );
    expect(text).toBe('değerlendirilmesi gerekir');
  });

  it('ignores whitespace-only runs and returns empty for no content', () => {
    expect(assembleReadingOrderText([item('  ', 10, 100)], PAGE_WIDTH)).toBe('');
    expect(assembleReadingOrderText([], PAGE_WIDTH)).toBe('');
  });
});
