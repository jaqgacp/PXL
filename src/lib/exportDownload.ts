export function getSnapshotExportText(data: unknown): string | null {
  const payload = data as { export_text?: unknown } | null
  return typeof payload?.export_text === 'string' ? payload.export_text : null
}

export function downloadTextFile(text: string, filename: string, mimeType = 'text/plain;charset=utf-8') {
  const blob = new Blob([text], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function downloadCsvText(csvText: string, filename: string) {
  downloadTextFile(csvText, filename, 'text/csv;charset=utf-8')
}
