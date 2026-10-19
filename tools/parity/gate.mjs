export function contractRegressions(report) {
  return report.plugins.flatMap((plugin) => {
    const failures = []
    if (plugin.status === 'missing') failures.push(`${plugin.id}: missing plugin`)
    for (const [category, result] of Object.entries(plugin.categories)) {
      for (const id of result.missing) failures.push(`${plugin.id}.${category}: missing ${id}`)
    }
    if (plugin.ui.status === 'partial' || plugin.ui.status === 'missing') failures.push(`${plugin.id}: missing UI contribution`)
    return failures
  })
}
