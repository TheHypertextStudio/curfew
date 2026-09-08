import type { BrowserDestinationScope, BrowserPolicySnapshot } from "./protocol";

export interface DynamicRule {
  id: number;
  priority: number;
  action: { type: "allow" | "block" };
  condition: {
    regexFilter: string;
    resourceTypes: ["main_frame"];
  };
}

const blockRule: DynamicRule = {
  id: 1,
  priority: 1,
  action: { type: "block" },
  condition: { regexFilter: "^https?://", resourceTypes: ["main_frame"] },
};

const breakRule: DynamicRule = {
  id: 2,
  priority: 100,
  action: { type: "allow" },
  condition: { regexFilter: "^https?://", resourceTypes: ["main_frame"] },
};

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function scopeKey(scope: BrowserDestinationScope): string {
  return `${scope.kind}\u0000${scope.origin}\u0000${scope.kind === "path_prefix" ? scope.path : ""}`;
}

function scopeRegex(scope: BrowserDestinationScope): string {
  const origin = escapeRegex(scope.origin);
  if (scope.kind === "origin" || scope.path === "/") {
    return `^${origin}(/|$)`;
  }
  const path = scope.path.endsWith("/") ? scope.path.slice(0, -1) : scope.path;
  return `^${origin}${escapeRegex(path)}(/|[?#]|$)`;
}

export function buildDynamicRules(
  policy: BrowserPolicySnapshot | null,
  now: Date,
): DynamicRule[] {
  if (policy === null) {
    return [];
  }

  const rules = [blockRule];
  if (policy.breakEndsAt !== null && new Date(policy.breakEndsAt).getTime() > now.getTime()) {
    rules.push(breakRule);
    return rules;
  }

  const scopes = new Map<string, BrowserDestinationScope>();
  for (const scope of policy.scopes) {
    scopes.set(scopeKey(scope), scope);
  }
  for (const grant of policy.grants) {
    if (new Date(grant.expiresAt).getTime() > now.getTime()) {
      scopes.set(scopeKey(grant.scope), grant.scope);
    }
  }

  const sortedScopes = [...scopes.entries()].sort(([left], [right]) => left.localeCompare(right));
  rules.push(
    ...sortedScopes.map(([, scope], index): DynamicRule => ({
      id: 1_000 + index,
      priority: 100,
      action: { type: "allow" },
      condition: { regexFilter: scopeRegex(scope), resourceTypes: ["main_frame"] },
    })),
  );
  return rules;
}
