import { describe, expect, it } from 'vitest';
import worker from '../src/index.js';
import type { Env } from '../src/types.js';

describe('license service deployment identity', () => {
  it('reports the shared configuration identity without changing its health payload', async () => {
    const env = { CONFIGURATION_SHA256: 'a'.repeat(64), CONFIGURATION_COMMIT: 'b'.repeat(40) } as unknown as Env;
    const response = await worker.fetch(new Request('https://license.example.net/health'), env);
    expect(response.headers.get('x-curfew-configuration')).toBe(env.CONFIGURATION_SHA256);
    expect(response.headers.get('x-curfew-configuration-commit')).toBe(env.CONFIGURATION_COMMIT);
    expect(await response.json()).toEqual({ status: 'ok', envelope_version: 2 });
  });
  it('retires legacy license requests without redirecting refresh tokens', async () => {
    const env = { LICENSE_ORIGIN: 'https://license.example.net', RETIRED_LICENSE_HOSTS: '["old-license.example.net"]' } as unknown as Env;
    const response = await worker.fetch(new Request('https://old-license.example.net/license/refresh?token=secret'), env);
    expect(response.status).toBe(410);
    expect(response.headers.get('location')).toBeNull();
  });
});
