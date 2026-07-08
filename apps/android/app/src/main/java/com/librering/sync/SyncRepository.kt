package com.librering.sync

import android.content.Context
import com.librering.app.BuildConfig

/**
 * Sync port — mirrors iOS SyncRepository and web @librering/sdk SyncService.
 * Single Responsibility: cloud sync only; BLE lives in a separate module.
 */
interface SyncRepository {
    val isEnabled: Boolean
    suspend fun pushPendingRecords()
    suspend fun pullRemoteDelta()

    companion object {
        fun create(context: Context): SyncRepository = SupabaseSyncRepository(context)

        fun isEnabled(context: Context): Boolean = create(context).isEnabled
    }
}

class SupabaseSyncRepository(private val context: Context) : SyncRepository {
    override val isEnabled: Boolean
        get() = BuildConfig.SUPABASE_URL.isNotBlank() &&
            BuildConfig.SUPABASE_ANON_KEY.isNotBlank() &&
            !BuildConfig.SUPABASE_URL.contains("your-project")

    override suspend fun pushPendingRecords() {
        if (!isEnabled) return
        // TODO: read Room DAO, call push_sync_batch RPC
    }

    override suspend fun pullRemoteDelta() {
        if (!isEnabled) return
        // TODO: call pull_sync_delta RPC, merge into Room
    }
}
