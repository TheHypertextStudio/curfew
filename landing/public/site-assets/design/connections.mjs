const laptop = `<path d="M-27-22h54v36h-54z"/><path d="M-36 22h72l-9-8h-54z"/>`;
const devices = `<rect x="-30" y="-24" width="48" height="33" rx="3"/><path d="M-6 10v10m-12 0H6"/><rect x="15" y="-10" width="18" height="34" rx="3"/>`;
const assistant = `<path d="M0-29c4 19 10 25 29 29C10 4 4 10 0 29-4 10-10 4-29 0-10-4-4-10 0-29Z"/><path d="M28-30v12m-6-6h12"/>`;
function node(x, y, icon, name, detail = "") {
  return `<g transform="translate(${x} ${y})"><g class="connection-icon">${icon}</g><text y="57" class="connection-label">${name}</text>${detail ? `<text y="80" class="connection-detail">${detail}</text>` : ""}</g>`;
}
function map(mobile) {
  const id = mobile ? "compact" : "wide";
  const center = mobile ? [90, 205] : [480, 140];
  return `<svg class="connection-map connection-map-${id}" viewBox="0 0 ${mobile ? "360 280" : "960 325"}" role="img" aria-labelledby="connections-${id}-title" aria-describedby="connections-${id}-desc"><title id="connections-${id}-title">How Curfew connects</title><desc id="connections-${id}-desc">Macs connect to Curfew. Other devices will join through Curfew Plus, coming soon. An AI assistant connects over MCP; changes require your approval.</desc><g class="connection-paths">${mobile ? '<path d="M70 108C70 140 90 138 90 162"/><path class="connection-future" d="M290 128C290 158 170 140 120 177"/><path d="M133 205h112"/>' : '<path d="M170 75C290 75 300 140 415 140"/><path class="connection-future" d="M170 230C290 230 300 140 415 140"/><path d="M545 140h240"/>'}</g>${mobile ? node(70, 38, laptop, "Mac") + node(290, 38, devices, "Other devices", "Plus · coming soon") + node(278, 205, assistant, "AI assistant") : node(110, 65, laptop, "Mac") + node(110, 220, devices, "Other devices", "Plus · coming soon") + node(850, 140, assistant, "AI assistant")}<g transform="translate(${center.join(" ")})"><circle class="connection-hub" r="${mobile ? 39 : 51}"/><svg x="-26" y="-26" width="52" height="43" viewBox="0 0 48 36" aria-hidden="true"><use href="#horizon"/></svg><text y="${mobile ? 62 : 83}" class="connection-brand">Curfew</text></g><text x="${mobile ? 188 : 665}" y="${mobile ? 189 : 122}" class="connection-detail">MCP</text></svg>`;
}
export const connectionDiagram = `<figure class="connection-diagram">${map(false)}${map(true)}</figure>`;
