import { describe, expect, it } from "vitest";

import { buildDynamicRules } from "../src/rules";
import type { BrowserPolicySnapshot } from "../src/protocol";

const at = new Date("2026-09-08T18:00:00.000Z");

function policy(overrides: Partial<BrowserPolicySnapshot> = {}): BrowserPolicySnapshot {
  return {
    schemaVersion: "browser-policy/1",
    sessionID: "334838bd-3160-4a2f-bb28-8b2d61a32f37",
    task: { id: "task-1", title: "Ship the Chrome gate" },
    tracking: "running",
    scopes: [
      { kind: "origin", origin: "https://docket.example" },
      { kind: "path_prefix", origin: "https://docs.example", path: "/curfew" },
    ],
    grants: [
      {
        scope: { kind: "origin", origin: "https://expired.example" },
        expiresAt: "2026-09-08T17:59:59.000Z",
      },
      {
        scope: { kind: "path_prefix", origin: "https://github.com", path: "/curfew/app" },
        expiresAt: "2026-09-08T18:30:00.000Z",
      },
    ],
    breakEndsAt: null,
    connectionIsHealthy: true,
    generatedAt: at.toISOString(),
    ...overrides,
  };
}

describe("buildDynamicRules", () => {
  it("puts bounded allow rules above one HTTP and HTTPS block rule", () => {
    const rules = buildDynamicRules(policy(), at);
    const block = rules.find((rule) => rule.action.type === "block");
    const allows = rules.filter((rule) => rule.action.type === "allow");

    expect(block).toEqual({
      id: 1,
      priority: 1,
      action: { type: "block" },
      condition: {
        regexFilter: "^https?://",
        isUrlFilterCaseSensitive: true,
        resourceTypes: ["main_frame"],
      },
    });
    expect(allows).toHaveLength(3);
    expect(allows.every((rule) => rule.priority > 1)).toBe(true);
    expect(
      allows.some((rule) => rule.condition.regexFilter.includes("expired\\.example")),
    ).toBe(false);
  });

  it("matches a path prefix without allowing sibling paths", () => {
    const rule = buildDynamicRules(policy(), at).find((candidate) =>
      candidate.condition.regexFilter.includes("docs\\.example"),
    );

    expect(rule).toBeDefined();
    const regex = new RegExp(rule!.condition.regexFilter);
    expect(regex.test("https://docs.example/curfew")).toBe(true);
    expect(regex.test("https://docs.example/curfew/release?q=one")).toBe(true);
    expect(regex.test("https://docs.example/curfew-notes")).toBe(false);
  });

  it("keeps path matching case-sensitive", () => {
    const rule = buildDynamicRules(
      policy({
        scopes: [
          { kind: "path_prefix", origin: "https://docs.example", path: "/Admin" },
        ],
        grants: [],
      }),
      at,
    ).find((candidate) => candidate.action.type === "allow");

    expect(rule?.condition.isUrlFilterCaseSensitive).toBe(true);
    const regex = new RegExp(rule!.condition.regexFilter);
    expect(regex.test("https://docs.example/Admin/users")).toBe(true);
    expect(regex.test("https://docs.example/admin/users")).toBe(false);
  });

  it("excludes every subresource type", () => {
    expect(
      buildDynamicRules(policy(), at).every(
        (rule) => rule.condition.resourceTypes.length === 1 &&
          rule.condition.resourceTypes[0] === "main_frame",
      ),
    ).toBe(true);
  });

  it("uses Chrome RE2-compatible regular expressions", () => {
    expect(
      buildDynamicRules(policy(), at).every(
        (rule) => !rule.condition.regexFilter.includes("(?:"),
      ),
    ).toBe(true);
  });

  it("allows every top-level destination only while a break remains active", () => {
    const active = buildDynamicRules(
      policy({ breakEndsAt: "2026-09-08T18:00:01.000Z" }),
      at,
    );
    const expired = buildDynamicRules(
      policy({ breakEndsAt: "2026-09-08T18:00:00.000Z" }),
      at,
    );

    expect(active).toContainEqual({
      id: 2,
      priority: 100,
      action: { type: "allow" },
      condition: {
        regexFilter: "^https?://",
        isUrlFilterCaseSensitive: true,
        resourceTypes: ["main_frame"],
      },
    });
    expect(expired.some((rule) => rule.id === 2)).toBe(false);
  });
});
