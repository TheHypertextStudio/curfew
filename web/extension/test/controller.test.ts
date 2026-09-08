import { describe, expect, it } from "vitest";

import {
  BrowserPolicyController,
  type BrowserControllerDependencies,
  type BrowserReviewOutcome,
} from "../src/controller";
import type { BrowserPolicySnapshot, NativeResponse } from "../src/protocol";

const now = new Date("2026-09-08T18:00:00.000Z");

function policy(overrides: Partial<BrowserPolicySnapshot> = {}): BrowserPolicySnapshot {
  return {
    schemaVersion: "browser-policy/1",
    sessionID: "334838bd-3160-4a2f-bb28-8b2d61a32f37",
    task: { id: "task-1", title: "Ship the Chrome gate" },
    tracking: "running",
    scopes: [{ kind: "origin", origin: "https://docket.example" }],
    grants: [],
    breakEndsAt: null,
    connectionIsHealthy: true,
    generatedAt: now.toISOString(),
    ...overrides,
  };
}

function response(
  request: Record<string, unknown>,
  fields: Partial<NativeResponse>,
): NativeResponse {
  return {
    schemaVersion: "browser-host/1",
    requestId: request.requestId as string,
    type: request.type as NativeResponse["type"],
    generatedAt: now.toISOString(),
    ...fields,
  };
}

function harness(options: {
  stored?: Record<string, unknown>;
  native?: (request: Record<string, unknown>) => Promise<NativeResponse>;
  dynamicRulesGet?: () => Promise<Array<{ id: number }>>;
} = {}) {
  const data: Record<string, unknown> = { ...options.stored };
  const calls: string[] = [];
  const storageWrites: Record<string, unknown>[] = [];
  const nativeRequests: Record<string, unknown>[] = [];
  const ruleUpdates: Array<{ removeRuleIds: number[]; addRules: unknown[] }> = [];
  const tabUpdates: Array<{ tabId: number; url: string }> = [];
  const scheduledExpirations: Array<Date | null> = [];
  const scheduledRefreshes: number[] = [];
  let nextID = 0;
  const dependencies: BrowserControllerDependencies = {
    storage: {
      async get(keys) {
        if (keys === null) {
          return { ...data };
        }
        const names = typeof keys === "string" ? [keys] : keys;
        return Object.fromEntries(names.filter((name) => name in data).map((name) => [name, data[name]]));
      },
      async set(items) {
        storageWrites.push(structuredClone(items));
        Object.assign(data, items);
      },
      async remove(keys) {
        for (const key of typeof keys === "string" ? [keys] : keys) {
          delete data[key];
        }
      },
    },
    dynamicRules: {
      async get() {
        if (options.dynamicRulesGet) {
          return options.dynamicRulesGet();
        }
        return [{ id: 76 }, { id: 77 }];
      },
      async replace(update) {
        calls.push("rules");
        ruleUpdates.push(structuredClone(update));
      },
    },
    tabs: {
      async update(tabId, update) {
        calls.push("tab");
        tabUpdates.push({ tabId, url: update.url });
      },
    },
    native: {
      async send(hostName, request) {
        expect(hostName).toBe("studio.hypertext.curfew.dev.browser");
        nativeRequests.push(structuredClone(request));
        if (request.type === "heartbeat") {
          calls.push("heartbeat");
        }
        if (options.native) {
          return options.native(request);
        }
        throw new Error("native host unavailable");
      },
    },
    expiry: {
      async schedule(date) {
        scheduledExpirations.push(date);
      },
    },
    refresh: {
      async scheduleRecurring(periodMinutes) {
        scheduledRefreshes.push(periodMinutes);
      },
    },
    extensionURL: (path) => `chrome-extension://extension-id/${path}`,
    now: () => new Date(now),
    randomID: () => `request-${++nextID}`,
    nativeHostName: "studio.hypertext.curfew.dev.browser",
  };
  return {
    controller: new BrowserPolicyController(dependencies),
    data,
    calls,
    nativeRequests,
    ruleUpdates,
    scheduledRefreshes,
    storageWrites,
    scheduledExpirations,
    tabUpdates,
  };
}

async function routeBlockedPage(
  testHarness: ReturnType<typeof harness>,
  url = "https://alice:secret@Research.Example:443/private/../notes?q=secret#fragment",
) {
  await testHarness.controller.cachePolicy(policy());
  testHarness.calls.length = 0;
  testHarness.ruleUpdates.length = 0;
  await testHarness.controller.handleNavigationError({
    tabId: 14,
    frameId: 0,
    error: "net::ERR_BLOCKED_BY_CLIENT",
    url,
  });
}

describe("BrowserPolicyController", () => {
  it("schedules Chrome's minimum reliable 30-second policy refresh", async () => {
    const testHarness = harness();

    await testHarness.controller.initialize();

    expect(testHarness.scheduledRefreshes).toEqual([0.5]);
  });

  it("restores cached policy in one complete DNR replacement when the host is unavailable", async () => {
    const testHarness = harness({ stored: { browserPolicy: policy() } });

    await testHarness.controller.initialize();

    expect(testHarness.ruleUpdates).toHaveLength(1);
    expect(testHarness.ruleUpdates[0].removeRuleIds).toEqual([76, 77]);
    expect(testHarness.ruleUpdates[0].addRules).toEqual(
      expect.arrayContaining([expect.objectContaining({ action: { type: "block" } })]),
    );
    expect(testHarness.data.browserPolicy).toEqual(policy());
  });

  it("removes expired grants and breaks when the one expiry alarm rebuilds policy", async () => {
    const expiringPolicy = policy({
      grants: [
        {
          scope: { kind: "origin", origin: "https://temporary.example" },
          expiresAt: "2026-09-08T18:00:01.000Z",
        },
      ],
      breakEndsAt: "2026-09-08T18:00:02.000Z",
    });
    const testHarness = harness({ stored: { browserPolicy: expiringPolicy } });

    await testHarness.controller.rebuildForExpiry(new Date("2026-09-08T18:00:03.000Z"));

    expect(testHarness.ruleUpdates).toHaveLength(1);
    expect(JSON.stringify(testHarness.ruleUpdates[0].addRules)).not.toContain("temporary");
    expect(testHarness.ruleUpdates[0].addRules).toHaveLength(2);
    expect(testHarness.scheduledExpirations.at(-1)).toBeNull();
  });

  it("replaces prior-task allows before heartbeat after a recurring refresh", async () => {
    const previous = policy({
      grants: [
        {
          scope: { kind: "origin", origin: "https://previous.example" },
          expiresAt: "2026-09-08T18:30:00.000Z",
        },
      ],
    });
    const switched = policy({
      sessionID: "39f9fbe2-3c34-487d-ad75-c954237c3184",
      task: { id: "task-2", title: "Write the release runbook" },
      scopes: [{ kind: "origin", origin: "https://release.example" }],
    });
    const testHarness = harness({
      stored: { browserPolicy: previous },
      native: async (request) => response(request, {
        ...(request.type === "get_policy" ? { policy: switched } : {}),
      }),
    });

    await testHarness.controller.refreshPolicy();

    expect(testHarness.calls).toEqual(["rules", "heartbeat"]);
    expect(testHarness.data.browserPolicy).toEqual(switched);
    expect(JSON.stringify(testHarness.ruleUpdates.at(-1))).not.toContain("previous");
    expect(JSON.stringify(testHarness.ruleUpdates.at(-1))).toContain("release");
  });

  it("sends one heartbeat after each successful policy refresh", async () => {
    const testHarness = harness({
      native: async (request) => response(request, {
        ...(request.type === "get_policy" ? { policy: policy() } : {}),
      }),
    });

    await testHarness.controller.refreshPolicy();

    expect(testHarness.nativeRequests.map((request) => request.type)).toEqual([
      "get_policy",
      "heartbeat",
    ]);
  });

  it("retains cached block rules when the recurring host refresh fails", async () => {
    const testHarness = harness({ stored: { browserPolicy: policy() } });

    await testHarness.controller.initialize();

    expect(testHarness.ruleUpdates).toHaveLength(1);
    expect(testHarness.ruleUpdates[0].addRules).toEqual(
      expect.arrayContaining([expect.objectContaining({ action: { type: "block" } })]),
    );
    expect(testHarness.data.browserPolicy).toEqual(policy());
    expect(testHarness.nativeRequests.map((request) => request.type)).toEqual(["get_policy"]);
  });

  it("cannot restore an old startup snapshot over a switched-session review", async () => {
    const previous = policy({
      grants: [
        {
          scope: { kind: "origin", origin: "https://previous.example" },
          expiresAt: "2026-09-08T18:30:00.000Z",
        },
      ],
    });
    const switched = policy({
      sessionID: "39f9fbe2-3c34-487d-ad75-c954237c3184",
      task: { id: "task-2", title: "Write the release runbook" },
      scopes: [{ kind: "origin", origin: "https://release.example" }],
    });
    let releaseFirstRuleRead!: () => void;
    let signalFirstRuleRead!: () => void;
    const firstRuleRead = new Promise<void>((resolve) => {
      signalFirstRuleRead = resolve;
    });
    const firstRuleReadRelease = new Promise<void>((resolve) => {
      releaseFirstRuleRead = resolve;
    });
    let ruleReadCount = 0;
    const pending = {
      id: "pending",
      tabId: 14,
      originalURL: "https://previous.example/notes",
      destination: { origin: "https://previous.example", path: "/notes" },
      sessionID: previous.sessionID,
      task: previous.task,
      challengeIssued: false,
      createdAt: now.toISOString(),
      expiresAt: "2026-09-08T18:02:00.000Z",
    };
    const testHarness = harness({
      stored: { browserPolicy: previous, "browserRequest:pending": pending },
      dynamicRulesGet: async () => {
        ruleReadCount += 1;
        if (ruleReadCount === 1) {
          signalFirstRuleRead();
          await firstRuleReadRelease;
        }
        return [{ id: 76 }, { id: 77 }];
      },
      native: async (request) => {
        if (request.type === "get_policy") {
          throw new Error("host unavailable after startup");
        }
        return response(request, {
          policy: switched,
          result: {
            decision: "grant",
            reason: "The old review is stale.",
            scope: { kind: "origin", origin: "https://previous.example" },
          },
        });
      },
    });

    const initialization = testHarness.controller.initialize();
    await firstRuleRead;
    const review = testHarness.controller.reviewDestination({
      requestID: "pending",
      justification: "This belongs to the prior task.",
    });
    for (let step = 0; step < 10; step += 1) {
      await Promise.resolve();
    }
    const reviewStartedBeforeRestore = ruleReadCount > 1;
    releaseFirstRuleRead();
    await Promise.all([initialization, review]);

    expect(reviewStartedBeforeRestore).toBe(false);
    expect(testHarness.data.browserPolicy).toEqual(switched);
    expect(JSON.stringify(testHarness.ruleUpdates.at(-1))).not.toContain("previous");
  });

  it("routes only blocked top-level HTTP navigation through an opaque request ID", async () => {
    const testHarness = harness();
    await routeBlockedPage(testHarness);
    await testHarness.controller.handleNavigationError({
      tabId: 15,
      frameId: 2,
      error: "net::ERR_BLOCKED_BY_CLIENT",
      url: "https://ignored.example/private",
    });

    expect(testHarness.tabUpdates).toEqual([
      {
        tabId: 14,
        url: "chrome-extension://extension-id/blocker.html?request=request-1",
      },
    ]);
    expect(testHarness.tabUpdates[0].url).not.toContain("Research.Example");
    expect(testHarness.data["browserRequest:request-1"]).toEqual({
      id: "request-1",
      tabId: 14,
      originalURL:
        "https://alice:secret@Research.Example:443/private/../notes?q=secret#fragment",
      destination: { origin: "https://research.example", path: "/notes" },
      sessionID: policy().sessionID,
      task: policy().task,
      challengeIssued: false,
      createdAt: now.toISOString(),
      expiresAt: "2026-09-08T18:02:00.000Z",
    });
    expect(testHarness.scheduledExpirations.at(-1)?.toISOString()).toBe(
      "2026-09-08T18:02:00.000Z",
    );
  });

  it("preserves an unexpired blocker request for the cached session across restart", async () => {
    const pending = {
      id: "pending",
      tabId: 14,
      originalURL: "https://research.example/notes?q=private",
      destination: { origin: "https://research.example", path: "/notes" },
      sessionID: policy().sessionID,
      task: policy().task,
      challengeIssued: false,
      createdAt: now.toISOString(),
      expiresAt: "2026-09-08T18:02:00.000Z",
    };
    const testHarness = harness({
      stored: { browserPolicy: policy(), "browserRequest:pending": pending },
    });

    await testHarness.controller.initialize();

    expect(testHarness.data["browserRequest:pending"]).toEqual(pending);
  });

  it("shows only the task, host, and required justification question", async () => {
    const testHarness = harness();
    await routeBlockedPage(testHarness);

    await expect(testHarness.controller.getBlockerContext("request-1")).resolves.toEqual({
      taskTitle: "Ship the Chrome gate",
      hostname: "research.example",
      question:
        "What will you do on research.example, and what will you produce for Ship the Chrome gate?",
    });
  });

  it("installs a bounded grant before reopening the exact original URL", async () => {
    const grantedPolicy = policy({
      grants: [
        {
          scope: {
            kind: "path_prefix",
            origin: "https://research.example",
            path: "/notes",
          },
          expiresAt: "2026-09-08T18:30:00.000Z",
        },
      ],
    });
    const testHarness = harness({
      native: async (request) =>
        response(request, {
          policy: grantedPolicy,
          result: {
            decision: "grant",
            reason: "The destination is bounded to the task.",
            scope: grantedPolicy.grants[0].scope,
          },
        }),
    });
    await routeBlockedPage(testHarness);
    testHarness.calls.length = 0;
    testHarness.ruleUpdates.length = 0;

    const outcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "I need the release notes for the implementation.",
    });

    expect(outcome).toEqual({ status: "grant" });
    expect(testHarness.calls).toEqual(["rules", "tab"]);
    expect(testHarness.tabUpdates.at(-1)?.url).toBe(
      "https://alice:secret@Research.Example:443/private/../notes?q=secret#fragment",
    );
    expect(testHarness.data["browserRequest:request-1"]).toBeUndefined();
    expect(testHarness.nativeRequests.at(-1)).toMatchObject({
      schemaVersion: "browser-host/1",
      type: "review_destination",
      sessionId: policy().sessionID,
      destination: { origin: "https://research.example", path: "/notes" },
      justification: "I need the release notes for the implementation.",
    });
  });

  it("returns only one targeted challenge without persisting either private answer", async () => {
    const question = "Which release section do you need?";
    const testHarness = harness({
      native: async (request) =>
        response(request, {
          policy: policy(),
          result: { decision: "challenge", reason: "Narrow the request.", question },
        }),
    });
    await routeBlockedPage(testHarness);

    const outcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "I need this for work.",
    });

    expect(outcome).toEqual({ status: "challenge", question });
    expect(testHarness.tabUpdates).toHaveLength(1);
    expect(testHarness.data["browserRequest:request-1"]).toBeDefined();
    expect(JSON.stringify(testHarness.storageWrites)).not.toContain("I need this for work.");

    const secondOutcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "I need this for work.",
      challengeAnswer: "The packaging section.",
    });
    expect(secondOutcome).toEqual({ status: "deny", reason: "Narrow the request." });
    expect(testHarness.data["browserRequest:request-1"]).toBeUndefined();
    expect(JSON.stringify(testHarness.storageWrites)).not.toContain("The packaging section.");
  });

  it("keeps a denied destination blocked and removes its resolved request", async () => {
    const testHarness = harness({
      native: async (request) =>
        response(request, {
          policy: policy(),
          result: { decision: "deny", reason: "The destination is in cooldown." },
        }),
    });
    await routeBlockedPage(testHarness);

    const outcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "I want to check it.",
    });

    expect(outcome).toEqual({
      status: "deny",
      reason: "The destination is in cooldown.",
    } satisfies BrowserReviewOutcome);
    expect(testHarness.tabUpdates).toHaveLength(1);
    expect(testHarness.data["browserRequest:request-1"]).toBeUndefined();
  });

  it("applies a switched task policy before rejecting a stale review", async () => {
    const switched = policy({
      sessionID: "39f9fbe2-3c34-487d-ad75-c954237c3184",
      task: { id: "task-2", title: "Write the release runbook" },
      scopes: [{ kind: "origin", origin: "https://release.example" }],
    });
    const testHarness = harness({
      native: async (request) =>
        response(request, {
          policy: switched,
          result: {
            decision: "grant",
            reason: "Late result.",
            scope: { kind: "origin", origin: "https://research.example" },
          },
        }),
    });
    await routeBlockedPage(testHarness);
    testHarness.calls.length = 0;

    const outcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "This result belongs to the old task.",
    });

    expect(outcome).toEqual({ status: "stale_session" });
    expect(testHarness.calls).toEqual(["rules"]);
    expect(testHarness.data.browserPolicy).toEqual(switched);
    expect(JSON.stringify(testHarness.ruleUpdates.at(-1))).not.toContain("research\\.example");
  });

  it("keeps the cached policy and pending destination blocked after host failure", async () => {
    const testHarness = harness();
    await routeBlockedPage(testHarness);
    const beforePolicy = structuredClone(testHarness.data.browserPolicy);

    const outcome = await testHarness.controller.reviewDestination({
      requestID: "request-1",
      justification: "The host is gone.",
    });

    expect(outcome).toEqual({ status: "host_failure" });
    expect(testHarness.data.browserPolicy).toEqual(beforePolicy);
    expect(testHarness.data["browserRequest:request-1"]).toBeDefined();
    expect(testHarness.tabUpdates).toHaveLength(1);
  });

  it("expires an original URL before returning blocker context", async () => {
    const testHarness = harness({
      stored: {
        "browserRequest:expired": {
          id: "expired",
          tabId: 14,
          originalURL: "https://private.example/?secret=one",
          destination: { origin: "https://private.example", path: "/" },
          sessionID: policy().sessionID,
          task: policy().task,
          challengeIssued: false,
          createdAt: "2026-09-08T17:57:00.000Z",
          expiresAt: "2026-09-08T17:59:00.000Z",
        },
      },
    });

    await expect(testHarness.controller.getBlockerContext("expired")).resolves.toBeNull();
    expect(testHarness.data["browserRequest:expired"]).toBeUndefined();
  });

  it("deletes an expired original URL when the shared expiry alarm fires", async () => {
    const testHarness = harness({
      stored: {
        browserPolicy: policy(),
        "browserRequest:expired": {
          id: "expired",
          tabId: 14,
          originalURL: "https://private.example/?secret=one",
          destination: { origin: "https://private.example", path: "/" },
          sessionID: policy().sessionID,
          task: policy().task,
          challengeIssued: false,
          createdAt: "2026-09-08T17:58:00.000Z",
          expiresAt: "2026-09-08T18:00:02.000Z",
        },
      },
    });

    await testHarness.controller.rebuildForExpiry(new Date("2026-09-08T18:00:03.000Z"));

    expect(testHarness.data["browserRequest:expired"]).toBeUndefined();
    expect(testHarness.scheduledExpirations.at(-1)).toBeNull();
  });
});
