// Desktop database access belongs to persistence; providers and widgets consume
// ViewerDataRepository rather than opening their own connections.
export function databaseImportViolations(relativePath, source) {
  const path = relativePath.replaceAll('\\', '/');
  if (!path.startsWith('lib/') || path.startsWith('lib/persistence/')) return [];
  return [...source.matchAll(/^\s*(?:import|export)\s+['"](package:(?:sqlite3|sqlite_async)\/[^'"]+)['"]/gm)]
    .map(match => `${path}: database import ${match[1]} belongs in lib/persistence/`);
}
