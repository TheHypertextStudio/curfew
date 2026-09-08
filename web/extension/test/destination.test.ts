import { describe, expect, it } from "vitest";

import { normalizeDestination } from "../src/destination";

describe("normalizeDestination", () => {
  it("removes credentials, query strings, fragments, and default ports", () => {
    expect(
      normalizeDestination(
        "https://alice:secret@EXAMPLE.com:443/private/../work?q=sensitive#token",
      ),
    ).toEqual({ origin: "https://example.com", path: "/work" });

    expect(normalizeDestination("http://Example.com:80/notes?draft=one")).toEqual({
      origin: "http://example.com",
      path: "/notes",
    });
  });

  it("rejects destinations outside HTTP and HTTPS", () => {
    expect(() => normalizeDestination("ftp://example.com/private")).toThrow(
      "Only HTTP and HTTPS destinations are supported",
    );
  });
});
