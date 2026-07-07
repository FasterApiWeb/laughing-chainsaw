"use client";

import { useEffect, useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import { useAuth } from "@/components/AuthProvider";
import { deleteAccount } from "@/lib/auth";
import { exportAllData, clearAllData, getTotalRecordCount, getImportHistory } from "@/lib/queries";
import type { ImportRecord } from "@/lib/db";

function SettingsContent() {
  const { email } = useAuth();
  const [recordCount, setRecordCount] = useState(0);
  const [imports, setImports] = useState<ImportRecord[]>([]);
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

  const handleClear = async () => {
    await clearAllData();
    setRecordCount(0);
    setImports([]);
    setShowClearConfirm(false);
  };

  const handleDelete = () => {
    clearAllData();
    deleteAccount();
    window.location.href = "/signup";
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
            </div>
          </section>

          <section className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
            <h3 className="text-sm font-medium mb-3">Data Export</h3>
            <p className="text-xs text-foreground/40 mb-3">Download all your health data as a JSON file. This file is compatible with LibreRing Desktop for re-import.</p>
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
