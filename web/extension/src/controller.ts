import { normalizeDestination } from "./destination";
import type {
  BrowserDestinationScope,
  BrowserPolicySnapshot,
  NativeResponse,
  NormalizedDestination,
} from "./protocol";
import { buildDynamicRules, type DynamicRule } from "./rules";

const policyKey = "browserPolicy";
const requestKeyPrefix = "browserRequest:";
const requestLifetimeMilliseconds = 2 * 60 * 1_000;

interface StoredBrowserRequest {
  id: string;
  tabId: number;
  originalURL: string;
  destination: NormalizedDestination;
  sessionID: string;
  task: BrowserPolicySnapshot["task"];
  challengeIssued: boolean;
  createdAt: string;
  expiresAt: string;
}

export interface BrowserControllerDependencies {
  storage: {
    get(keys: string | string[] | null): Promise<Record<string, unknown>>;
    set(items: Record<string, unknown>): Promise<void>;
    remove(keys: string | string[]): Promise<void>;
  };
  dynamicRules: {
    get(): Promise<Array<{ id: number }>>;
    replace(update: { removeRuleIds: number[]; addRules: DynamicRule[] }): Promise<void>;
  };
  tabs: {
    update(tabId: number, update: { url: string }): Promise<void>;
  };
  native: {
    send(hostName: string, request: Record<string, unknown>): Promise<unknown>;
  };
  expiry: {
    schedule(date: Date | null): Promise<void>;
  };
  refresh: {
    scheduleRecurring(periodMinutes: number): Promise<void>;
  };
  extensionURL(path: string): string;
  now(): Date;
  randomID(): string;
  nativeHostName: string;
}

export interface NavigationError {
  tabId: number;
  frameId: number;
  error: string;
  url: string;
}

export type BrowserReviewOutcome =
  | { status: "grant" }
  | { status: "challenge"; question: string }
  | { status: "deny"; reason: string }
  | { status: "stale_session" }
  | { status: "host_failure" }
  | { status: "expired" };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasValidDate(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function isScope(value: unknown): value is BrowserDestinationScope {
  if (!isRecord(value) || typeof value.origin !== "string") {
    return false;
  }
  let destination: NormalizedDestination;
  try {
    destination = normalizeDestination(value.origin);
  } catch {
    return false;
  }
  if (destination.origin !== value.origin || destination.path !== "/") {
    return false;
  }
  if (value.kind === "origin") {
    return !("path" in value);
  }
  if (value.kind !== "path_prefix" || typeof value.path !== "string" ||
      !value.path.startsWith("/")) {
    return false;
  }
  try {
    const normalized = normalizeDestination(value.origin + value.path);
    return normalized.origin === value.origin && normalized.path === value.path;
  } catch {
    return false;
  }
}

function isPolicy(value: unknown): value is BrowserPolicySnapshot {
  if (!isRecord(value) || value.schemaVersion !== "browser-policy/1" ||
      typeof value.sessionID !== "string" || !isRecord(value.task) ||
      typeof value.task.id !== "string" || typeof value.task.title !== "string" ||
      !["running", "paused", "idle"].includes(String(value.tracking)) ||
      !Array.isArray(value.scopes) || !value.scopes.every(isScope) ||
      !Array.isArray(value.grants) || typeof value.connectionIsHealthy !== "boolean" ||
      !hasValidDate(value.generatedAt)) {
    return false;
  }
  if (value.breakEndsAt !== null && !hasValidDate(value.breakEndsAt)) {
    return false;
  }
  return value.grants.every((grant) =>
    isRecord(grant) && isScope(grant.scope) && hasValidDate(grant.expiresAt));
}

function isStoredRequest(value: unknown): value is StoredBrowserRequest {
  return isRecord(value) && typeof value.id === "string" &&
    Number.isInteger(value.tabId) && typeof value.originalURL === "string" &&
    isRecord(value.destination) && typeof value.destination.origin === "string" &&
    typeof value.destination.path === "string" && typeof value.sessionID === "string" &&
    isRecord(value.task) && typeof value.task.id === "string" &&
    typeof value.task.title === "string" && typeof value.challengeIssued === "boolean" &&
    hasValidDate(value.createdAt) &&
    hasValidDate(value.expiresAt);
}

function scopeAllows(
  scope: BrowserDestinationScope,
  destination: NormalizedDestination,
): boolean {
  if (scope.origin !== destination.origin) {
    return false;
  }
  if (scope.kind === "origin" || scope.path === "/") {
    return true;
  }
  const prefix = scope.path.endsWith("/") ? scope.path.slice(0, -1) : scope.path;
  return destination.path === prefix || destination.path.startsWith(`${prefix}/`);
}

function policyAllows(
  policy: BrowserPolicySnapshot,
  destination: NormalizedDestination,
  now: Date,
): boolean {
  if (policy.breakEndsAt !== null && Date.parse(policy.breakEndsAt) > now.getTime()) {
    return true;
  }
  if (policy.scopes.some((scope) => scopeAllows(scope, destination))) {
    return true;
  }
  return policy.grants.some((grant) =>
    Date.parse(grant.expiresAt) > now.getTime() && scopeAllows(grant.scope, destination));
}

function nextExpiry(policy: BrowserPolicySnapshot | null, now: Date): Date | null {
  if (policy === null) {
    return null;
  }
  const candidates = [
    policy.breakEndsAt,
    ...policy.grants.map((grant) => grant.expiresAt),
  ].filter((value): value is string => value !== null)
    .map((value) => Date.parse(value))
    .filter((value) => value > now.getTime());
  return candidates.length === 0 ? null : new Date(Math.min(...candidates));
}

function readNativeResponse(
  value: unknown,
  requestID: string,
  type: NativeResponse["type"],
): NativeResponse {
  if (!isRecord(value) || value.schemaVersion !== "browser-host/1" ||
      value.requestId !== requestID || value.type !== type || !hasValidDate(value.generatedAt)) {
    throw new Error("The native host returned an invalid response");
  }
  if ("policy" in value && value.policy !== undefined && !isPolicy(value.policy)) {
    throw new Error("The native host returned an invalid policy");
  }
  if ("result" in value && value.result !== undefined) {
    if (!isRecord(value.result) ||
        !["grant", "challenge", "deny"].includes(String(value.result.decision)) ||
        typeof value.result.reason !== "string" ||
        ("scope" in value.result && value.result.scope !== undefined && !isScope(value.result.scope)) ||
        ("question" in value.result && value.result.question !== undefined &&
          typeof value.result.question !== "string")) {
      throw new Error("The native host returned an invalid review");
    }
  }
  if ("error" in value && value.error !== undefined && typeof value.error !== "string") {
    throw new Error("The native host returned an invalid error");
  }
  return value as unknown as NativeResponse;
}

export class BrowserPolicyController {
  private policyOperations: Promise<void> = Promise.resolve();

  constructor(private readonly dependencies: BrowserControllerDependencies) {}

  async initialize(): Promise<void> {
    await this.serializePolicyOperation(async () => {
      const cached = await this.readPolicy();
      await this.pruneStoredRequests(cached?.sessionID);
      if (cached !== null) {
        await this.cachePolicy(cached);
      }
    });
    await this.dependencies.refresh.scheduleRecurring(0.5);
    await this.refreshPolicy();
  }

  async refreshPolicy(): Promise<void> {
    await this.serializePolicyOperation(async () => {
      const requestID = this.dependencies.randomID();
      try {
        const response = readNativeResponse(
          await this.dependencies.native.send(this.dependencies.nativeHostName, {
            schemaVersion: "browser-host/1",
            requestId: requestID,
            type: "get_policy",
          }),
          requestID,
          "get_policy",
        );
        if (response.error !== undefined) {
          return;
        }
        await this.cachePolicy(response.policy ?? null);
        await this.sendHeartbeat();
      } catch {
        // The cached dynamic rules remain authoritative while Curfew is unavailable.
      }
    });
  }

  async cachePolicy(policy: BrowserPolicySnapshot | null, at = this.dependencies.now()): Promise<void> {
    const dynamicRules = await this.dependencies.dynamicRules.get();
    await this.dependencies.dynamicRules.replace({
      removeRuleIds: dynamicRules.map((rule) => rule.id),
      addRules: buildDynamicRules(policy, at),
    });
    if (policy === null) {
      await this.dependencies.storage.remove(policyKey);
    } else {
      await this.dependencies.storage.set({ [policyKey]: policy });
    }
    await this.pruneStoredRequests(policy?.sessionID, at);
    await this.scheduleNextExpiry(policy, at);
  }

  async rebuildForExpiry(at = this.dependencies.now()): Promise<void> {
    await this.serializePolicyOperation(async () => {
      await this.cachePolicy(await this.readPolicy(), at);
    });
  }

  async handleNavigationError(details: NavigationError): Promise<void> {
    if (details.frameId !== 0 || !details.error.endsWith("ERR_BLOCKED_BY_CLIENT")) {
      return;
    }
    let destination: NormalizedDestination;
    try {
      destination = normalizeDestination(details.url);
    } catch {
      return;
    }
    const policy = await this.readPolicy();
    if (policy === null) {
      return;
    }
    const createdAt = this.dependencies.now();
    const id = this.dependencies.randomID();
    const request: StoredBrowserRequest = {
      id,
      tabId: details.tabId,
      originalURL: details.url,
      destination,
      sessionID: policy.sessionID,
      task: policy.task,
      challengeIssued: false,
      createdAt: createdAt.toISOString(),
      expiresAt: new Date(createdAt.getTime() + requestLifetimeMilliseconds).toISOString(),
    };
    await this.dependencies.storage.set({ [`${requestKeyPrefix}${id}`]: request });
    await this.scheduleNextExpiry(policy, createdAt);
    const page = new URL(this.dependencies.extensionURL("blocker.html"));
    page.searchParams.set("request", id);
    await this.dependencies.tabs.update(details.tabId, { url: page.toString() });
  }

  async getBlockerContext(requestID: string): Promise<{
    taskTitle: string;
    hostname: string;
    question: string;
  } | null> {
    const request = await this.readStoredRequest(requestID);
    if (request === null) {
      return null;
    }
    const hostname = new URL(request.destination.origin).hostname;
    return {
      taskTitle: request.task.title,
      hostname,
      question: `What will you do on ${hostname}, and what will you produce for ${request.task.title}?`,
    };
  }

  async reviewDestination(input: {
    requestID: string;
    justification: string;
    challengeAnswer?: string;
  }): Promise<BrowserReviewOutcome> {
    return this.serializePolicyOperation(() => this.reviewDestinationNow(input));
  }

  private async reviewDestinationNow(input: {
    requestID: string;
    justification: string;
    challengeAnswer?: string;
  }): Promise<BrowserReviewOutcome> {
    const request = await this.readStoredRequest(input.requestID);
    if (request === null) {
      return { status: "expired" };
    }
    const policy = await this.readPolicy();
    if (policy === null || policy.sessionID !== request.sessionID) {
      await this.removeStoredRequest(input.requestID, policy);
      return { status: "stale_session" };
    }

    const nativeRequestID = this.dependencies.randomID();
    const nativeRequest: Record<string, unknown> = {
      schemaVersion: "browser-host/1",
      requestId: nativeRequestID,
      type: "review_destination",
      sessionId: request.sessionID,
      destination: request.destination,
      justification: input.justification,
    };
    if (input.challengeAnswer !== undefined && request.challengeIssued) {
      nativeRequest.challengeAnswer = input.challengeAnswer;
    }

    let response: NativeResponse;
    try {
      response = readNativeResponse(
        await this.dependencies.native.send(this.dependencies.nativeHostName, nativeRequest),
        nativeRequestID,
        "review_destination",
      );
    } catch {
      return { status: "host_failure" };
    }

    if (response.policy !== undefined) {
      await this.cachePolicy(response.policy);
    }
    if (response.policy !== undefined && response.policy.sessionID !== request.sessionID) {
      await this.removeStoredRequest(input.requestID, response.policy);
      return { status: "stale_session" };
    }
    if (response.error !== undefined || response.result === undefined) {
      return { status: "host_failure" };
    }
    if (response.result.decision === "challenge") {
      if (!response.result.question) {
        return { status: "host_failure" };
      }
      if (request.challengeIssued) {
        await this.removeStoredRequest(input.requestID, response.policy ?? policy);
        return { status: "deny", reason: response.result.reason };
      }
      await this.dependencies.storage.set({
        [`${requestKeyPrefix}${input.requestID}`]: { ...request, challengeIssued: true },
      });
      return { status: "challenge", question: response.result.question };
    }
    if (response.result.decision === "deny") {
      await this.removeStoredRequest(input.requestID, response.policy ?? policy);
      return { status: "deny", reason: response.result.reason };
    }
    if (response.policy === undefined || response.result.scope === undefined ||
        !scopeAllows(response.result.scope, request.destination) ||
        !policyAllows(response.policy, request.destination, this.dependencies.now())) {
      return { status: "host_failure" };
    }

    await this.removeStoredRequest(input.requestID, response.policy);
    await this.dependencies.tabs.update(request.tabId, { url: request.originalURL });
    return { status: "grant" };
  }

  private async readPolicy(): Promise<BrowserPolicySnapshot | null> {
    const stored = (await this.dependencies.storage.get(policyKey))[policyKey];
    return isPolicy(stored) ? stored : null;
  }

  private async readStoredRequest(requestID: string): Promise<StoredBrowserRequest | null> {
    const key = `${requestKeyPrefix}${requestID}`;
    const stored = (await this.dependencies.storage.get(key))[key];
    if (!isStoredRequest(stored) || Date.parse(stored.expiresAt) <= this.dependencies.now().getTime()) {
      await this.dependencies.storage.remove(key);
      return null;
    }
    return stored;
  }

  private async pruneStoredRequests(
    sessionID?: string,
    at = this.dependencies.now(),
  ): Promise<void> {
    const stored = await this.dependencies.storage.get(null);
    const now = at.getTime();
    const expired = Object.entries(stored)
      .filter(([key]) => key.startsWith(requestKeyPrefix))
      .filter(([, value]) =>
        !isStoredRequest(value) || Date.parse(value.expiresAt) <= now ||
          sessionID === undefined || value.sessionID !== sessionID)
      .map(([key]) => key);
    if (expired.length > 0) {
      await this.dependencies.storage.remove(expired);
    }
  }

  private async scheduleNextExpiry(
    policy: BrowserPolicySnapshot | null,
    at: Date,
  ): Promise<void> {
    const policyExpiry = nextExpiry(policy, at)?.getTime();
    const stored = await this.dependencies.storage.get(null);
    const requestExpiries = Object.entries(stored)
      .filter(([key]) => key.startsWith(requestKeyPrefix))
      .map(([, value]) => value)
      .filter((value): value is StoredBrowserRequest =>
        isStoredRequest(value) && policy !== null && value.sessionID === policy.sessionID)
      .map((value) => Date.parse(value.expiresAt))
      .filter((value) => value > at.getTime());
    const expiries = policyExpiry === undefined
      ? requestExpiries
      : [policyExpiry, ...requestExpiries];
    await this.dependencies.expiry.schedule(
      expiries.length === 0 ? null : new Date(Math.min(...expiries)),
    );
  }

  private async removeStoredRequest(
    requestID: string,
    policy: BrowserPolicySnapshot | null,
  ): Promise<void> {
    await this.dependencies.storage.remove(`${requestKeyPrefix}${requestID}`);
    await this.scheduleNextExpiry(policy, this.dependencies.now());
  }

  private async serializePolicyOperation<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.policyOperations.then(operation, operation);
    this.policyOperations = result.then(() => undefined, () => undefined);
    return result;
  }

  private async sendHeartbeat(): Promise<void> {
    const requestID = this.dependencies.randomID();
    const response = await this.dependencies.native.send(this.dependencies.nativeHostName, {
      schemaVersion: "browser-host/1",
      requestId: requestID,
      type: "heartbeat",
    });
    readNativeResponse(response, requestID, "heartbeat");
  }
}
