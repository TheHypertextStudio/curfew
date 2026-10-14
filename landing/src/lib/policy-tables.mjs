// Preserve the archived table and its headings; repeat each column label only
// for the stacked mobile view. The original policy source remains unchanged.
export function labelPolicyTables(content) {
  return content.replace(/<table class="privacy-table">[\s\S]*?<\/table>/g, (table) => {
    const headings = [...table.matchAll(/<th(?:\s[^>]*)?>([\s\S]*?)<\/th>/g)].map(
      (match) => match[1],
    );
    if (!headings.length) return table;
    return table.replace(/<tbody>([\s\S]*?)<\/tbody>/, (_, body) => {
      let column = 0;
      return `<tbody>${body.replace(/<td>/g, () => {
        const label = headings[column++ % headings.length];
        return `<td><span class="cell-label" aria-hidden="true">${label}</span>`;
      })}</tbody>`;
    });
  });
}
