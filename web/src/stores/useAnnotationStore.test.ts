import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Annotation } from "@/types/models";

// annotationSync talks to Supabase — replace it entirely for unit tests.
vi.mock("@/lib/annotationSync", () => ({
  loadAnnotations: vi.fn(),
  saveAnnotation: vi.fn(),
  updateAnnotation: vi.fn(),
  deleteAnnotation: vi.fn(),
}));

import {
  loadAnnotations,
  saveAnnotation,
  updateAnnotation,
  deleteAnnotation,
} from "@/lib/annotationSync";
import { useAnnotationStore } from "./useAnnotationStore";

function makeAnnotation(overrides: Partial<Annotation> = {}): Annotation {
  return {
    id: "ann-1",
    fileId: "file-1",
    pageNumber: 1,
    type: "highlight",
    color: "#fef08a",
    rects: [{ x: 10, y: 10, width: 30, height: 5 }],
    text: "selected text",
    isAiGenerated: false,
    createdAt: new Date("2026-06-12T10:00:00Z"),
    ...overrides,
  };
}

describe("useAnnotationStore", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useAnnotationStore.setState({
      annotations: [],
      selectedTool: null,
      selectedColor: "#fef08a",
      isLoading: false,
    });
  });

  it("loads annotations for a file", async () => {
    const loaded = [makeAnnotation(), makeAnnotation({ id: "ann-2", pageNumber: 3 })];
    vi.mocked(loadAnnotations).mockResolvedValue(loaded);

    await useAnnotationStore.getState().loadFileAnnotations("file-1");

    expect(loadAnnotations).toHaveBeenCalledWith("file-1");
    expect(useAnnotationStore.getState().annotations).toEqual(loaded);
    expect(useAnnotationStore.getState().isLoading).toBe(false);
  });

  it("keeps previous state and stops loading when load fails", async () => {
    vi.mocked(loadAnnotations).mockRejectedValue(new Error("network down"));
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

    await useAnnotationStore.getState().loadFileAnnotations("file-1");

    expect(useAnnotationStore.getState().annotations).toEqual([]);
    expect(useAnnotationStore.getState().isLoading).toBe(false);
    consoleError.mockRestore();
  });

  it("appends the saved annotation on add", async () => {
    const saved = makeAnnotation({ id: "ann-new" });
    vi.mocked(saveAnnotation).mockResolvedValue(saved);

    await useAnnotationStore.getState().addAnnotation({
      fileId: saved.fileId,
      pageNumber: saved.pageNumber,
      type: saved.type,
      color: saved.color,
      rects: saved.rects,
      text: saved.text,
    });

    expect(useAnnotationStore.getState().annotations).toEqual([saved]);
  });

  it("does not append anything when save returns null", async () => {
    vi.mocked(saveAnnotation).mockResolvedValue(null);

    await useAnnotationStore.getState().addAnnotation({
      fileId: "file-1",
      pageNumber: 1,
      type: "highlight",
      color: "#fef08a",
      rects: [],
    });

    expect(useAnnotationStore.getState().annotations).toEqual([]);
  });

  it("removes an annotation only when deletion succeeds", async () => {
    useAnnotationStore.setState({ annotations: [makeAnnotation()] });

    vi.mocked(deleteAnnotation).mockResolvedValue(false);
    await useAnnotationStore.getState().removeAnnotation("ann-1");
    expect(useAnnotationStore.getState().annotations).toHaveLength(1);

    vi.mocked(deleteAnnotation).mockResolvedValue(true);
    await useAnnotationStore.getState().removeAnnotation("ann-1");
    expect(useAnnotationStore.getState().annotations).toHaveLength(0);
  });

  it("updates the note of the matching annotation", async () => {
    useAnnotationStore.setState({
      annotations: [makeAnnotation(), makeAnnotation({ id: "ann-2" })],
    });
    vi.mocked(updateAnnotation).mockResolvedValue(true);

    await useAnnotationStore.getState().updateAnnotationNote("ann-2", "önemli kısım");

    const annotations = useAnnotationStore.getState().annotations;
    expect(annotations.find((a) => a.id === "ann-2")?.note).toBe("önemli kısım");
    expect(annotations.find((a) => a.id === "ann-1")?.note).toBeUndefined();
  });

  it("reset clears annotations and tool selection", () => {
    useAnnotationStore.setState({
      annotations: [makeAnnotation()],
      selectedTool: "highlight",
      isLoading: true,
    });

    useAnnotationStore.getState().reset();

    const state = useAnnotationStore.getState();
    expect(state.annotations).toEqual([]);
    expect(state.selectedTool).toBeNull();
    expect(state.isLoading).toBe(false);
  });
});
