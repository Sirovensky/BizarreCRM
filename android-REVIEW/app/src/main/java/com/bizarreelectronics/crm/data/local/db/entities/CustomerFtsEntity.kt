package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Fts4

/**
 * FTS4 virtual table shadowing [CustomerEntity] for prefix-aware full-text search.
 *
 * ## Why FTS4 not FTS5
 *
 * Room's `@Fts4` annotation is the supported path; FTS5 virtual tables cannot be
 * declared with Room's annotation processor on all API levels and require raw
 * `execSQL` in a migration. FTS4 is available on all API levels Bizarre CRM targets
 * (min SDK 26+) and supports `MATCH` with trailing-wildcard prefix queries
 * (`query*`), which is sufficient for §18.1 and §18.3.
 *
 * ## Sync strategy
 *
 * A SQLite AFTER INSERT / AFTER UPDATE / AFTER DELETE trigger (added in
 * [com.bizarreelectronics.crm.data.local.db.Migrations.MIGRATION_11_12]) keeps
 * this shadow table in sync with `customers` automatically on every upsert.
 * [CustomerFtsDao] is the query interface; writes happen exclusively through
 * the triggers.
 *
 * ## Columns
 *
 * The FTS table mirrors only the text columns that are meaningfully searchable.
 * Numeric and timestamp columns are excluded — FTS4 treats all content as
 * plain text, so indexing integers would produce unhelpful matches.
 *
 * The `rowid` column in the virtual table corresponds to `customers.id` via the
 * `content` table directive in the trigger DDL. Joins in [CustomerFtsDao] use
 * `customers.rowid = customers_fts.docid` to retrieve full entity rows.
 */
@Fts4(contentEntity = CustomerEntity::class)
@Entity(tableName = "customers_fts")
data class CustomerFtsEntity(
    @ColumnInfo(name = "first_name")  val firstName: String?,
    @ColumnInfo(name = "last_name")   val lastName: String?,
    val email: String?,
    val phone: String?,
    val mobile: String?,
    val organization: String?,
    val tags: String?,
)
