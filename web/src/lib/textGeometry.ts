// Geometry-aware text assembly shared by the text-selection hook and the
// in-document search. pdf.js emits text runs in content-stream order, which on
// multi-column PDFs interleaves the columns; these helpers cluster runs into
// columns by x-position, order them into reading order (column → line → x),
// and merge hyphenated line breaks so downstream consumers (translation,
// search) see natural text.

export interface PositionedText {
  text: string;
  /** Left edge. Any unit, as long as all items on a page share it. */
  left: number;
  /** Top edge — must increase downward (callers flip PDF-space y). */
  top: number;
  /** Approximate line height of the run, used for line grouping. */
  height: number;
  /** Right edge if known — enables gap-based intra-line joining. */
  right?: number;
}

// A gap between clustered left edges wider than this fraction of the page
// width is treated as a column gutter. Intra-column indentation steps are far
// narrower than the gutter between two columns of an A4/letter page.
const COLUMN_GAP_RATIO = 0.12;

// Trailing hyphen-minus, unicode hyphen (U+2010) or soft hyphen (U+00AD):
// the signature of a word broken across lines by justification.
const TRAILING_HYPHEN = /[-‐­]$/;

/**
 * Finds x positions that split the items' left edges into column clusters.
 * Returns the midpoints of gaps wider than the gutter threshold, sorted.
 */
export function clusterColumnBoundaries(lefts: number[], pageWidth: number): number[] {
  const sorted = [...new Set(lefts)].sort((a, b) => a - b);
  const threshold = pageWidth * COLUMN_GAP_RATIO;
  const boundaries: number[] = [];
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i] - sorted[i - 1] > threshold) {
      boundaries.push((sorted[i] + sorted[i - 1]) / 2);
    }
  }
  return boundaries;
}

function columnIndexFor(left: number, boundaries: number[]): number {
  let index = 0;
  for (const boundary of boundaries) {
    if (left >= boundary) index++;
  }
  return index;
}

/**
 * Groups items into visual lines by vertical proximity (half a line height of
 * tolerance absorbs sub/superscripts and slightly misaligned runs), then
 * orders each line left-to-right.
 */
export function groupIntoLines<T extends PositionedText>(items: T[]): T[][] {
  const sorted = [...items].sort((a, b) => a.top - b.top || a.left - b.left);
  const lines: T[][] = [];
  let current: T[] = [];
  let currentTop = 0;
  let currentHeight = 0;

  for (const item of sorted) {
    if (current.length === 0) {
      current = [item];
      currentTop = item.top;
      currentHeight = item.height;
      continue;
    }
    const tolerance = 0.5 * Math.max(item.height, currentHeight, 1);
    if (Math.abs(item.top - currentTop) <= tolerance) {
      current.push(item);
    } else {
      lines.push(current);
      current = [item];
      currentTop = item.top;
      currentHeight = item.height;
    }
  }
  if (current.length > 0) lines.push(current);

  for (const line of lines) {
    line.sort((a, b) => a.left - b.left);
  }
  return lines;
}

/**
 * Joins the runs of one visual line. When edge geometry is available, runs
 * separated by less than ~a fifth of the line height are considered the same
 * word (pdf.js splits words across runs on font changes) and joined without a
 * space; wider gaps get one.
 */
function joinLineItems(line: PositionedText[]): string {
  let out = "";
  let prev: PositionedText | null = null;
  for (const item of line) {
    if (!prev) {
      out = item.text;
      prev = item;
      continue;
    }
    const needsSpace = prev.right === undefined
      ? true
      : item.left - prev.right > 0.2 * Math.max(prev.height, item.height, 1);
    if (needsSpace && !/\s$/.test(out) && !/^\s/.test(item.text)) {
      out += " ";
    }
    out += item.text;
    prev = item;
  }
  return out.replace(/\s+/g, " ").trim();
}

/**
 * Joins lines (already in reading order) into flowing text. A line ending in
 * a hyphen followed by a lowercase-starting line is a justification break
 * inside a word ("bilgi-" + "lendirme") — join without the hyphen. Uppercase
 * continuations keep the hyphen (likely a real compound) and get a space.
 */
export function joinLinesMergingHyphens(lines: string[]): string {
  let out = "";
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;
    if (!out) {
      out = line;
      continue;
    }
    if (TRAILING_HYPHEN.test(out) && /^\p{Ll}/u.test(line)) {
      out = out.replace(TRAILING_HYPHEN, "") + line;
    } else {
      out += ` ${line}`;
    }
  }
  return out;
}

/**
 * Full pipeline: cluster into columns, order lines within each column
 * top-to-bottom, then emit column after column with hyphenation merged.
 */
export function assembleReadingOrderText(items: PositionedText[], pageWidth: number): string {
  const textual = items.filter(item => item.text.trim().length > 0);
  if (textual.length === 0) return "";

  const boundaries = clusterColumnBoundaries(textual.map(item => item.left), pageWidth);
  const columns: PositionedText[][] = Array.from({ length: boundaries.length + 1 }, () => []);
  for (const item of textual) {
    columns[columnIndexFor(item.left, boundaries)].push(item);
  }

  const lineTexts: string[] = [];
  for (const column of columns) {
    for (const line of groupIntoLines(column)) {
      lineTexts.push(joinLineItems(line));
    }
  }
  return joinLinesMergingHyphens(lineTexts);
}
