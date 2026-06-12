import { beforeEach, describe, expect, it } from "vitest";
import { useReaderStore } from "./useReaderStore";

describe("useReaderStore", () => {
  beforeEach(() => {
    useReaderStore.getState().reset();
  });

  it("starts with chat and translation mode closed", () => {
    const state = useReaderStore.getState();
    expect(state.isChatOpen).toBe(false);
    expect(state.isTranslationMode).toBe(false);
  });

  it("toggles chat open and closed", () => {
    useReaderStore.getState().toggleChat();
    expect(useReaderStore.getState().isChatOpen).toBe(true);
    useReaderStore.getState().toggleChat();
    expect(useReaderStore.getState().isChatOpen).toBe(false);
  });

  it("sets chat open explicitly", () => {
    useReaderStore.getState().setChatOpen(true);
    expect(useReaderStore.getState().isChatOpen).toBe(true);
    useReaderStore.getState().setChatOpen(false);
    expect(useReaderStore.getState().isChatOpen).toBe(false);
  });

  it("toggles translation mode independently of chat", () => {
    useReaderStore.getState().toggleTranslationMode();
    expect(useReaderStore.getState().isTranslationMode).toBe(true);
    expect(useReaderStore.getState().isChatOpen).toBe(false);
  });

  it("reset closes everything", () => {
    useReaderStore.getState().setChatOpen(true);
    useReaderStore.getState().toggleTranslationMode();
    useReaderStore.getState().reset();
    const state = useReaderStore.getState();
    expect(state.isChatOpen).toBe(false);
    expect(state.isTranslationMode).toBe(false);
  });
});
