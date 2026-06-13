// Citation extraction — finds the document's DOI on its first pages, resolves
// bibliographic metadata via the Crossref API, and produces BibTeX / RIS. When
// no DOI is present, falls back to Gemini-based metadata extraction from the
// first-page text.
import type { pdfjs } from 'react-pdf';
import { generateRaw } from './gemini';

export interface CitationMetadata {
  type: 'article' | 'book' | 'misc';
  title: string;
  authors: string[]; // "Family, Given"
  year?: string;
  journal?: string;
  volume?: string;
  issue?: string;
  pages?: string;
  publisher?: string;
  doi?: string;
  url?: string;
}

export type CitationSource = 'crossref' | 'ai';

interface TextItemLike {
  str?: string;
}

// DOI syntax per Crossref's recommended regex (trailing punctuation trimmed).
const DOI_REGEX = /10\.\d{4,9}\/[-._;()/:A-Z0-9]+/i;

async function getFirstPagesText(pdf: pdfjs.PDFDocumentProxy, maxPages = 2): Promise<string> {
  const pages = Math.min(maxPages, pdf.numPages);
  const parts: string[] = [];
  for (let i = 1; i <= pages; i++) {
    const page = await pdf.getPage(i);
    const content = await page.getTextContent();
    parts.push((content.items as TextItemLike[]).map(item => item.str ?? '').join(' '));
  }
  return parts.join('\n').replace(/\s+/g, ' ').trim();
}

export function findDoi(text: string): string | null {
  const match = text.match(DOI_REGEX);
  if (!match) return null;
  // Strip trailing punctuation that commonly clings to an inline DOI.
  return match[0].replace(/[.,;)]+$/, '');
}

interface CrossrefAuthor {
  given?: string;
  family?: string;
  name?: string;
}

interface CrossrefMessage {
  title?: string[];
  author?: CrossrefAuthor[];
  'container-title'?: string[];
  volume?: string;
  issue?: string;
  page?: string;
  publisher?: string;
  DOI?: string;
  URL?: string;
  type?: string;
  'published-print'?: { 'date-parts'?: number[][] };
  'published-online'?: { 'date-parts'?: number[][] };
  issued?: { 'date-parts'?: number[][] };
}

function crossrefYear(msg: CrossrefMessage): string | undefined {
  const source = msg.issued ?? msg['published-print'] ?? msg['published-online'];
  const year = source?.['date-parts']?.[0]?.[0];
  return year ? String(year) : undefined;
}

function mapCrossref(msg: CrossrefMessage): CitationMetadata {
  const authors = (msg.author ?? []).map(a => {
    if (a.family && a.given) return `${a.family}, ${a.given}`;
    return a.family ?? a.name ?? a.given ?? '';
  }).filter(Boolean);

  return {
    type: msg.type === 'book' || msg.type === 'monograph' ? 'book' : 'article',
    title: msg.title?.[0] ?? 'Başlıksız',
    authors,
    year: crossrefYear(msg),
    journal: msg['container-title']?.[0],
    volume: msg.volume,
    issue: msg.issue,
    pages: msg.page,
    publisher: msg.publisher,
    doi: msg.DOI,
    url: msg.URL,
  };
}

async function fetchCrossref(doi: string): Promise<CitationMetadata | null> {
  try {
    const res = await fetch(`https://api.crossref.org/works/${encodeURIComponent(doi)}`, {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (!data?.message) return null;
    return mapCrossref(data.message as CrossrefMessage);
  } catch {
    return null;
  }
}

async function extractViaAI(text: string): Promise<CitationMetadata | null> {
  const snippet = text.slice(0, 2500);
  const prompt = `Aşağıda bir akademik dokümanın ilk sayfasının metni var. Bibliyografik künyeyi çıkar ve SADECE şu JSON formatında yanıt ver (kod bloğu kullanma, açıklama ekleme):
{"title":"","authors":["Soyad, Ad"],"year":"","journal":"","volume":"","issue":"","pages":"","publisher":"","doi":""}
Bilinmeyen alanları boş bırak. Yazarları "Soyad, Ad" formatında ver.

Metin:
"""${snippet}"""`;

  try {
    const raw = (await generateRaw(prompt)).trim();
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    if (jsonStart === -1 || jsonEnd === -1) return null;
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    const authors = Array.isArray(parsed.authors) ? parsed.authors.filter(Boolean) : [];
    if (!parsed.title && authors.length === 0) return null;
    return {
      type: parsed.journal ? 'article' : 'misc',
      title: parsed.title || 'Başlıksız',
      authors,
      year: parsed.year || undefined,
      journal: parsed.journal || undefined,
      volume: parsed.volume || undefined,
      issue: parsed.issue || undefined,
      pages: parsed.pages || undefined,
      publisher: parsed.publisher || undefined,
      doi: parsed.doi || undefined,
    };
  } catch {
    return null;
  }
}

/**
 * Resolves a citation for the document: DOI → Crossref first, AI extraction as
 * fallback. Returns null when neither yields usable metadata.
 */
export async function resolveCitation(
  pdf: pdfjs.PDFDocumentProxy
): Promise<{ metadata: CitationMetadata; source: CitationSource } | null> {
  const text = await getFirstPagesText(pdf);

  const doi = findDoi(text);
  if (doi) {
    const metadata = await fetchCrossref(doi);
    if (metadata) return { metadata, source: 'crossref' };
  }

  const aiMetadata = await extractViaAI(text);
  if (aiMetadata) return { metadata: aiMetadata, source: 'ai' };

  return null;
}

// MARK: - Formatters

function citeKey(meta: CitationMetadata): string {
  const firstAuthor = meta.authors[0]?.split(',')[0]?.replace(/[^A-Za-z]/g, '') || 'kaynak';
  const year = meta.year || 'nd';
  const firstWord = meta.title.split(/\s+/)[0]?.replace(/[^A-Za-z0-9]/g, '') || '';
  return `${firstAuthor.toLowerCase()}${year}${firstWord.toLowerCase()}`;
}

export function toBibtex(meta: CitationMetadata): string {
  const entryType = meta.type === 'book' ? 'book' : meta.type === 'article' ? 'article' : 'misc';
  const fields: [string, string | undefined][] = [
    ['title', meta.title],
    ['author', meta.authors.length ? meta.authors.join(' and ') : undefined],
    ['journal', meta.journal],
    ['year', meta.year],
    ['volume', meta.volume],
    ['number', meta.issue],
    ['pages', meta.pages?.replace('-', '--')],
    ['publisher', meta.publisher],
    ['doi', meta.doi],
    ['url', meta.url],
  ];
  const body = fields
    .filter((f): f is [string, string] => Boolean(f[1]))
    .map(([key, value]) => `  ${key} = {${value}}`)
    .join(',\n');
  return `@${entryType}{${citeKey(meta)},\n${body}\n}`;
}

export function toRis(meta: CitationMetadata): string {
  const lines: string[] = [];
  lines.push(`TY  - ${meta.type === 'book' ? 'BOOK' : meta.type === 'article' ? 'JOUR' : 'GEN'}`);
  lines.push(`TI  - ${meta.title}`);
  for (const author of meta.authors) lines.push(`AU  - ${author}`);
  if (meta.year) lines.push(`PY  - ${meta.year}`);
  if (meta.journal) lines.push(`JO  - ${meta.journal}`);
  if (meta.volume) lines.push(`VL  - ${meta.volume}`);
  if (meta.issue) lines.push(`IS  - ${meta.issue}`);
  if (meta.pages) {
    const [start, end] = meta.pages.split(/[-–]/);
    if (start) lines.push(`SP  - ${start.trim()}`);
    if (end) lines.push(`EP  - ${end.trim()}`);
  }
  if (meta.publisher) lines.push(`PB  - ${meta.publisher}`);
  if (meta.doi) lines.push(`DO  - ${meta.doi}`);
  if (meta.url) lines.push(`UR  - ${meta.url}`);
  lines.push('ER  - ');
  return lines.join('\r\n');
}
