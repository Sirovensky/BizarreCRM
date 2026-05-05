import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';

const dataDir = path.dirname(config.dbPath);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const db: import('better-sqlite3').Database = new Database(config.dbPath);

// Performance pragmas
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');
db.pragma('journal_size_limit = 67108864'); // 64MB
db.pragma('synchronous = NORMAL');
db.pragma('cache_size = -64000'); // 64MB cache
db.pragma('busy_timeout = 5000');
db.pragma('mmap_size = 268435456'); // 256MB memory-mapped I/O
db.pragma('temp_store = MEMORY');    // temp tables in RAM
db.pragma('wal_autocheckpoint = 10000'); // reduce checkpoint frequency (default 1000 pages ~4MB)

export default db;
export { db };
