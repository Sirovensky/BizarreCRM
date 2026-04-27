package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import kotlinx.coroutines.flow.Flow

/**
 * FTS4-backed search queries for the `customers_fts` virtual table.
 *
 * ## Query patterns
 *
 * - [searchFts] — exact and prefix matching via FTS4 `MATCH`. The caller
 *   appends `*` to the normalised token for prefix matching (e.g. `"john*"`).
 *   Results are returned as full [CustomerEntity] rows via an `INNER JOIN` on
 *   `customers.rowid = customers_fts.rowid`.
 *
 * - [searchFtsRaw] — raw normalized token list ready for FTS MATCH (used when
 *   the caller needs the `docid` list to drive downstream logic, e.g. Levenshtein
 *   post-filtering in the search ViewModel).
 *
 * ## Why not `@RawQuery`
 *
 * Room compiles FTS `MATCH` queries at build time when expressed as `@Query`
 * strings. `@RawQuery` bypasses this safety net and prevents query-hash
 * validation. The query string is therefore kept static; the dynamic `query*`
 * token is passed as a bound parameter.
 *
 * ## Trigger maintenance
 *
 * This DAO has no write methods. The FTS virtual table is updated exclusively
 * by AFTER INSERT / AFTER UPDATE / AFTER DELETE triggers on `customers` created
 * in [com.bizarreelectronics.crm.data.local.db.Migrations.MIGRATION_11_12].
 */
@Dao
interface CustomerFtsDao {

    /**
     * Full-text prefix search on customers.
     *
     * [normalizedQuery] must be a FTS4-safe token string, e.g. `"john*"` for
     * prefix or `"john smith"` for phrase. The caller is responsible for
     * sanitizing the raw user input (strip punctuation, lowercase, append `*`
     * for prefix) — see `FtsQuerySanitizer.sanitize()` in the ViewModel.
     *
     * Returns non-deleted rows only.
     */
    @Query(
        """
        SELECT c.*
        FROM customers c
        INNER JOIN customers_fts fts ON c.rowid = fts.rowid
        WHERE customers_fts MATCH :normalizedQuery
          AND c.is_deleted = 0
        ORDER BY c.first_name ASC, c.last_name ASC
        LIMIT 50
        """
    )
    fun searchFts(normalizedQuery: String): Flow<List<CustomerEntity>>
}
