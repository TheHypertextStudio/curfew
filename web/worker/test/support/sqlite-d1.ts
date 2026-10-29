import { DatabaseSync } from 'node:sqlite';
import { readFileSync, existsSync } from 'node:fs';

export class SQLiteD1 {
  readonly sqlite = new DatabaseSync(':memory:');
  batches = 0;
  failNextBatch = false;
  failAfterStatements: number | null = null;
  beforeBatch: (() => void) | null = null;
  reads = 0;
  constructor() {
    const migration = new URL('../../migrations/0001_license_store.sql', import.meta.url);
    if (existsSync(migration)) {
      this.sqlite.exec(readFileSync(migration, 'utf8'));
      this.sqlite.exec('UPDATE curfew_license_meta SET ready=1');
    }
  }
  prepare(query: string) {
    const database = this;
    const statement = (values: unknown[] = []): any => ({
      bind: (...bound: unknown[]) => statement(bound),
      first: async () => {
        database.reads++;
        return database.sqlite.prepare(query).get(...(values as any[])) ?? null;
      },
      all: async () => {
        database.reads++;
        return { results: database.sqlite.prepare(query).all(...(values as any[])), success: true };
      },
      run: async () => {
        const result = database.sqlite.prepare(query).run(...(values as any[]));
        return { success: true, meta: { changes: Number(result.changes) } };
      },
      execute: () => {
        if (values.length > 100) throw new Error('D1 statement parameter limit');
        return database.sqlite.prepare(query).all(...(values as any[]));
      },
    });
    return statement();
  }
  async batch(statements: any[]) {
    this.batches += 1;
    this.beforeBatch?.();
    this.sqlite.exec('BEGIN');
    try {
      if (this.failNextBatch) {
        this.failNextBatch = false;
        throw new Error('injected database failure');
      }
      const results = statements.map((statement, index) => {
        const result = { results: statement.execute(), success: true };
        if (this.failAfterStatements === index + 1) {
          this.failAfterStatements = null;
          throw new Error('injected mid-batch failure');
        }
        return result;
      });
      this.sqlite.exec('COMMIT');
      return results;
    } catch (error) {
      this.sqlite.exec('ROLLBACK');
      throw error;
    }
  }
  async exec(sql: string) {
    this.sqlite.exec(sql);
    return { count: 0, duration: 0 };
  }
}
