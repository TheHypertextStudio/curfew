import type { NormalizedDestination } from "./protocol";

export function normalizeDestination(rawValue: string): NormalizedDestination {
  let url: URL;
  try {
    url = new URL(rawValue);
  } catch {
    throw new Error("The destination is not a valid URL");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("Only HTTP and HTTPS destinations are supported");
  }
  if (url.hostname.length === 0) {
    throw new Error("The destination must have a host");
  }

  url.username = "";
  url.password = "";
  url.search = "";
  url.hash = "";
  if ((url.protocol === "https:" && url.port === "443") ||
      (url.protocol === "http:" && url.port === "80")) {
    url.port = "";
  }

  return {
    origin: url.origin,
    path: url.pathname.length === 0 ? "/" : url.pathname,
  };
}
