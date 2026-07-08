"use client";

import { useState } from "react";
import { AuthProvider } from "@/components/AuthProvider";
import { AuthGuard } from "@/components/AuthGuard";
import NavSidebar from "@/components/NavSidebar";
import FileUploader from "@/components/FileUploader";
import { ingestLibreRingJSON, type IngestResult } from "@/lib/ingest";
import { ingestOuraZip } from "@/lib/ingest-oura";

function UploadContent() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<IngestResult | null>(null);

  const handleFile = async (file: File) => {
    setLoading(true);
    setResult(null);

    try {
      let res: IngestResult;

      if (file.name.endsWith(".zip")) {
        res = await ingestOuraZip(file);
      } else if (file.name.endsWith(".json")) {
        const text = await file.text();
        res = await ingestLibreRingJSON(text, file.name);
      } else {
        res = { inserted: 0, skipped: 0, source: "unknown", error: "Unsupported file format. Use .json or .zip" };
      }

      setResult(res);
    } catch (err) {
      setResult({ inserted: 0, skipped: 0, source: "unknown", error: `Import failed: ${err}` });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen">
      <NavSidebar />
      <main className="flex-1 p-8 overflow-auto">
        <h2 className="text-xl font-semibold mb-6">Upload Data</h2>

        <div className="max-w-xl mx-auto">
          <FileUploader onFile={handleFile} loading={loading} />

          {result && (
            <div className={`mt-6 rounded-xl border p-5 ${result.error ? "border-red-500/30 bg-red-500/5" : "border-green-500/30 bg-green-500/5"}`}>
              {result.error ? (
                <div>
                  <p className="text-sm font-medium text-red-500">Import failed</p>
                  <p className="text-sm text-red-400 mt-1">{result.error}</p>
                </div>
              ) : (
                <div>
                  <p className="text-sm font-medium text-green-600 dark:text-green-400">Import successful</p>
                  <div className="mt-2 text-sm text-foreground/60 space-y-0.5">
                    <p>Source: {result.source === "librering" ? "LibreRing" : "Oura"}</p>
                    <p>Records imported: {result.inserted.toLocaleString()}</p>
                    {result.skipped > 0 && <p>Duplicates skipped: {result.skipped.toLocaleString()}</p>}
                  </div>
                </div>
              )}
            </div>
          )}

          <div className="mt-8 space-y-4">
            <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
              <h3 className="text-sm font-medium mb-2">LibreRing Export (.json)</h3>
              <p className="text-xs text-foreground/40 leading-relaxed">
                Export from the LibreRing iOS app: Settings &rarr; Data Export &rarr; Export as JSON. Transfer the file to this device via AirDrop, email, or any file sharing method.
              </p>
            </div>
            <div className="rounded-xl border border-foreground/10 bg-foreground/[0.02] p-5">
              <h3 className="text-sm font-medium mb-2">Oura Export (.zip)</h3>
              <p className="text-xs text-foreground/40 leading-relaxed">
                Download your data from <span className="font-mono">membership.ouraring.com</span> &rarr; Data Export. The ZIP file contains your complete Oura health history.
              </p>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default function UploadPage() {
  return (
    <AuthProvider>
      <AuthGuard>
        <UploadContent />
      </AuthGuard>
    </AuthProvider>
  );
}
