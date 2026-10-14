import { describe, expect, it } from 'vitest';
import worker from '../src/index.js';
import type { Env } from '../src/types.js';

describe('license service deployment identity', () => {
  it('retires legacy license requests without redirecting refresh tokens', async () => {
    const env = { LICENSE_ORIGIN: 'https://license.example.net', RETIRED_LICENSE_HOSTS: '["old-license.example.net"]' } as unknown as Env;
    const response = await worker.fetch(new Request('https://old-license.example.net/license/refresh?token=secret'), env);
    expect(response.status).toBe(410);
    expect(response.headers.get('location')).toBeNull();
  });
});
