"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import { useAuth } from "@/components/AuthProvider";
import { deleteAccount } from "@/lib/auth";
import { isWorkerEnabled } from "@/lib/config";
import { syncWithCloud, uploadExportToCloud } from "@/lib/sync";
import { exportAllData, clearAllData, getTotalRecordCount, getImportHistory } from "@/lib/queries";
import type { ImportRecord } from "@/lib/db";

function SettingsContent() {
  const { email, cloudEnabled, logout } = useAuth();
  const workerEnabled = isWorkerEnabled();
  const [recordCount, setRecordCount] = useState(0);
  const [imports, setImports] = useState<ImportRecord[]>([]);
  const [syncStatus, setSyncStatus] = useState<string | null>(null);
  const [backupStatus, setBackupStatus] = useState<string | null>(null);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  useEffect(() => {
    getTotalRecordCount().then(setRecordCount);
    getImportHistory().then(setImports);
  }, []);

  const handleExport = async () => {
    const json = await exportAllData();
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `librering-export-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleCloudBackup = async () => {
    setBackupStatus("Uploading...");
    const json = await exportAllData();
    const filename = `librering-export-${new Date().toISOString().slice(0, 10)}.json`;
    const result = await uploadExportToCloud(json, filename);
    setBackupStatus(
      result.ok ? `Backed up to R2 (${result.objectKey})` : (result.error ?? "Backup failed")
    );
  };

  const handleClear = async () => {
    await clearAllData();
    setRecordCount(0);
    setImports([]);
    setShowClearConfirm(false);
  };

  const handleDelete = async () => {
    await clearAllData();
    await deleteAccount();
    await logout();
    window.location.href = "/signup";
  };

  const handleCloudSync = async () => {
    setSyncStatus("Syncing...");
    const result = await syncWithCloud();
    if (result.ok) {
      const inserted = result.inserted ?? 0;
      const skipped = result.skipped ?? 0;
      const pulled = result.pulled ?? 0;

      if (inserted === 0 && skipped === 0 && pulled === 0) {
        setSyncStatus("Already up to date — no new changes");
      } else {
        const parts = [
          inserted ? `↑ ${inserted} new` : null,
          skipped ? `${skipped} unchanged` : null,
          pulled ? `↓ ${pulled} pulled` : null,
        ].filter(Boolean);
        setSyncStatus(parts.join(", "));
      }
      getTotalRecordCount().then(setRecordCount);
    } else {
      setSyncStatus(result.error ?? "Sync failed");
    }
  };

  return (
    <div className="flex min-h-screen">
      <NavSidebar />
      <main className="flex-1 p-8 overflow-auto">
        <h2 className="text-xl font-semibold mb-6">Settings</h2>

        <div className="max-w-xl space-y-6">
          <section className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
            <h3 className="text-sm font-medium mb-3">Account</h3>
            <div className="text-sm text-foreground/60 space-y-1">
              <p>Email: {email}</p>
              <p>Total records: {recordCount.toLocaleString()}</p>
              <p>Cloud: {cloudEnabled ? "Supabase connected" : "Local only"}</p>
              {cloudEnabled && (
                <p>Blob storage: {workerEnabled ? "R2 connected" : "Not configured"}</p>
              )}
            </div>
          </section>

          <section className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
            <h3 className="text-sm font-medium mb-3">Cloud Sync</h3>
            {cloudEnabled ? (
              <>
                <p className="text-xs text-foreground/40 mb-3">
                  Two-way sync with Supabase. Imports auto-sync when cloud is enabled.
                </p>
                <div className="flex flex-wrap gap-2">
                  <button
                    onClick={handleCloudSync}
                    disabled={recordCount === 0}
                    className="px-4 py-2 rounded-lg bg-foreground/10 text-sm font-medium hover:bg-foreground/15 transition-colors disabled:opacity-30"
                  >
                    Sync Now
                  </button>
                  {workerEnabled && (
                    <button
                      onClick={handleCloudBackup}
                      disabled={recordCount === 0}
                      className="px-4 py-2 rounded-lg bg-foreground/10 text-sm font-medium hover:bg-foreground/15 transition-colors disabled:opacity-30"
                    >
                      Backup to R2
                    </button>
                  )}
                </div>
                {syncStatus && <p className="text-xs text-foreground/50 mt-2">{syncStatus}</p>}
                {backupStatus && <p className="text-xs text-foreground/50 mt-1">{backupStatus}</p>}
              </>
            ) : (
              <p className="text-xs text-foreground/40">
                Copy <code className="text-foreground/60">apps/web/.env.example</code> to{" "}
                <code className="text-foreground/60">.env.local</code> and set Supabase keys.
                See <code className="text-foreground/60">docs/SETUP_CLOUD.md</code>.
              </p>
            )}
          </section>

          <section className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
            <h3 className="text-sm font-medium mb-3">Data Export</h3>
            <p className="text-xs text-foreground/40 mb-3">Download all your health data as a JSON file. This file is compatible with LibreRing iOS for re-import.</p>
            <button
              onClick={handleExport}
              disabled={recordCount === 0}
              className="px-4 py-2 rounded-lg bg-foreground/10 text-sm font-medium hover:bg-foreground/15 transition-colors disabled:opacity-30"
            >
              Export All Data
            </button>
          </section>

          <section className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
            <h3 className="text-sm font-medium mb-3">Import History</h3>
            {imports.length === 0 ? (
              <p className="text-xs text-foreground/40">No imports yet.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-foreground/40">
                      <th className="pb-2 font-medium">File</th>
                      <th className="pb-2 font-medium">Source</th>
                      <th className="pb-2 font-medium">Records</th>
                      <th className="pb-2 font-medium">Date</th>
                    </tr>
                  </thead>
                  <tbody className="text-foreground/60">
                    {imports.map((imp) => (
                      <tr key={imp.id} className="border-t border-foreground/5">
                        <td className="py-2 truncate max-w-[200px]">{imp.filename}</td>
                        <td className="py-2">{imp.source === "librering" ? "LibreRing" : "Oura"}</td>
                        <td className="py-2">{imp.recordCount.toLocaleString()}</td>
                        <td className="py-2">{new Date(imp.importedAt).toLocaleDateString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="rounded-xl border border-red-500/20 bg-red-500/5 p-5">
            <h3 className="text-sm font-medium mb-3 text-red-500">Danger Zone</h3>
            <div className="flex gap-3">
              {!showClearConfirm ? (
                <button
                  onClick={() => setShowClearConfirm(true)}
                  className="px-4 py-2 rounded-lg border border-red-500/30 text-sm text-red-500 hover:bg-red-500/10 transition-colors"
                >
                  Clear All Data
                </button>
              ) : (
                <div className="flex items-center gap-2">
                  <span className="text-sm text-red-500">Are you sure?</span>
                  <button onClick={handleClear} className="px-3 py-1.5 rounded-lg bg-red-500 text-white text-sm">Yes, clear</button>
                  <button onClick={() => setShowClearConfirm(false)} className="px-3 py-1.5 rounded-lg border border-foreground/15 text-sm">Cancel</button>
                </div>
              )}

              {!showDeleteConfirm ? (
                <button
                  onClick={() => setShowDeleteConfirm(true)}
                  className="px-4 py-2 rounded-lg border border-red-500/30 text-sm text-red-500 hover:bg-red-500/10 transition-colors"
                >
                  Delete Account
                </button>
              ) : (
                <div className="flex items-center gap-2">
                  <span className="text-sm text-red-500">Delete everything?</span>
                  <button onClick={handleDelete} className="px-3 py-1.5 rounded-lg bg-red-500 text-white text-sm">Yes, delete</button>
                  <button onClick={() => setShowDeleteConfirm(false)} className="px-3 py-1.5 rounded-lg border border-foreground/15 text-sm">Cancel</button>
                </div>
              )}
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}

export default function SettingsPage() {
  return (
    <AuthProvider>
      <AuthGuard>
        <SettingsContent />
      </AuthGuard>
    </AuthProvider>
  );
}
