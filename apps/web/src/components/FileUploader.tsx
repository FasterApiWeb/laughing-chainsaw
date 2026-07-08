"use client";

import { useState, useCallback, type DragEvent } from "react";

interface FileUploaderProps {
  onFile: (file: File) => void;
  accept?: string;
  loading?: boolean;
}

export default function FileUploader({ onFile, accept = ".json,.zip", loading = false }: FileUploaderProps) {
  const [dragOver, setDragOver] = useState(false);

  const handleDrop = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      setDragOver(false);
      const file = e.dataTransfer.files[0];
      if (file) onFile(file);
    },
    [onFile]
  );

  return (
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={handleDrop}
      className={`relative rounded-xl border-2 border-dashed p-12 text-center transition-colors ${
        dragOver ? "border-blue-500 bg-blue-500/5" : "border-foreground/15 hover:border-foreground/25"
      }`}
    >
      {loading ? (
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-foreground/50">Importing data...</p>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3">
          <svg className="w-10 h-10 text-foreground/20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
          </svg>
          <div>
            <p className="text-sm font-medium">Drag & drop your export file here</p>
            <p className="text-xs text-foreground/40 mt-1">LibreRing JSON or Oura export ZIP</p>
          </div>
          <label className="mt-2 cursor-pointer">
            <span className="px-4 py-2 rounded-lg bg-foreground/10 text-sm font-medium hover:bg-foreground/15 transition-colors">
              Browse files
            </span>
            <input
              type="file"
              accept={accept}
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) onFile(file);
              }}
            />
          </label>
        </div>
      )}
    </div>
  );
}
