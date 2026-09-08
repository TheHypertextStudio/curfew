export interface NormalizedDestination {
  origin: string;
  path: string;
}

export interface OriginScope {
  kind: "origin";
  origin: string;
}

export interface PathPrefixScope {
  kind: "path_prefix";
  origin: string;
  path: string;
}

export type BrowserDestinationScope = OriginScope | PathPrefixScope;

export interface BrowserPolicySnapshot {
  schemaVersion: "browser-policy/1";
  sessionID: string;
  task: {
    id: string;
    title: string;
  };
  tracking: "running" | "paused" | "idle";
  scopes: BrowserDestinationScope[];
  grants: Array<{
    scope: BrowserDestinationScope;
    expiresAt: string;
  }>;
  breakEndsAt: string | null;
  connectionIsHealthy: boolean;
  generatedAt: string;
}

export interface NativeReviewResult {
  decision: "grant" | "challenge" | "deny";
  reason: string;
  scope?: BrowserDestinationScope;
  question?: string;
}

export interface NativeResponse {
  schemaVersion: "browser-host/1";
  requestId: string;
  type: "get_policy" | "review_destination" | "heartbeat";
  policy?: BrowserPolicySnapshot;
  result?: NativeReviewResult;
  error?: string;
  generatedAt: string;
}
