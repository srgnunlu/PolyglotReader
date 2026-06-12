import { afterEach, describe, expect, it, vi } from "vitest";
import { translateText } from "./gemini";

// The client facade talks to /api/gemini/* — stub fetch to test the contract.
function mockFetchOnce(response: Partial<Response> & { json?: () => Promise<unknown> }) {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => ({}),
    ...response,
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

describe("translateText", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("posts the text to the server-side generate route and returns the translation", async () => {
    const fetchMock = mockFetchOnce({ json: async () => ({ text: "Merhaba dünya" }) });

    const result = await translateText("Hello world", "tr");

    expect(result).toBe("Merhaba dünya");
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/gemini/generate");
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body.prompt).toContain("Hello world");
    expect(body.prompt).toContain("tr");
  });

  it("throws the server error message when the API responds with an error", async () => {
    mockFetchOnce({
      ok: false,
      status: 401,
      json: async () => ({ error: "Unauthorized" }),
    });

    await expect(translateText("Hello", "tr")).rejects.toThrow("Unauthorized");
  });

  it("falls back to a status-based message when the error body is not JSON", async () => {
    mockFetchOnce({
      ok: false,
      status: 502,
      json: async () => {
        throw new Error("not json");
      },
    });

    await expect(translateText("Hello", "tr")).rejects.toThrow("AI request failed (502)");
  });
});
