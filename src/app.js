import {
  createTelemetrySnapshot,
  formatMbps,
  getTopActiveHost,
  normalizeCpuTemperature,
} from "./telemetry.js";
import {
  buildAgentDirectory,
  getReachableAgents,
  sampleAgentHosts,
  serializeAgentDirectory,
} from "./agents.js";

const meshCanvas = document.querySelector("#meshCanvas");
const meshCtx = meshCanvas.getContext("2d");
const spotlightChart = document.querySelector("#spotlightChart").getContext("2d");
const throughputChart = document.querySelector("#throughputChart").getContext("2d");
const directory = buildAgentDirectory(sampleAgentHosts);
const reachableAgents = getReachableAgents(directory);
const agentJson = serializeAgentDirectory(directory);

document.querySelector("#tailops-agent-directory").textContent = agentJson;
window.tailopsAgentDirectory = JSON.parse(agentJson);
window.tailopsReachableAgents = reachableAgents;

const links = [
  ["homelab-router", "nas-vault"],
  ["homelab-router", "nuc-lab"],
  ["homelab-router", "pi-dns"],
  ["homelab-router", "atlas-win11"],
  ["homelab-router", "media-mac"],
  ["homelab-router", "work-laptop"],
  ["nas-vault", "nuc-lab"],
  ["nas-vault", "media-mac"],
  ["nuc-lab", "atlas-win11"],
];

function resizeCanvas(canvas, ctx) {
  const ratio = Math.max(1, window.devicePixelRatio || 1);
  const rect = canvas.getBoundingClientRect();
  canvas.width = Math.round(rect.width * ratio);
  canvas.height = Math.round(rect.height * ratio);
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
}

function pointFor(host, width, height) {
  return {
    x: host.x * width,
    y: host.y * height,
  };
}

function colorForHost(host) {
  const temp = normalizeCpuTemperature(host.cpuTempC);
  if (host.status === "warning" || temp.level === "hot") return "#ffae3d";
  if (host.status === "offline") return "#ff5b75";
  if (temp.level === "warm") return "#37d7ff";
  return "#3ee88a";
}

function drawRing(ctx, x, y, radius, pct, color, start = -Math.PI / 2) {
  ctx.beginPath();
  ctx.strokeStyle = "rgba(130, 146, 173, 0.18)";
  ctx.lineWidth = 3;
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.strokeStyle = color;
  ctx.lineWidth = 3;
  ctx.lineCap = "round";
  ctx.arc(x, y, radius, start, start + Math.PI * 2 * pct);
  ctx.stroke();
}

function drawFlows(ctx, hosts, topHost, time, width, height) {
  const map = new Map(hosts.map((host) => [host.id, { host, ...pointFor(host, width, height) }]));
  for (const [fromId, toId] of links) {
    const from = map.get(fromId);
    const to = map.get(toId);
    if (!from || !to) continue;
    const traffic = ((from.host.networkInMbps + from.host.networkOutMbps + to.host.networkInMbps + to.host.networkOutMbps) / 2000);
    const intensity = Math.min(1, 0.18 + traffic * 0.14);
    const isTop = fromId === topHost.id || toId === topHost.id;
    const pulse = (Math.sin(time / 420 + from.x * 0.01) + 1) / 2;

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    const midX = (from.x + to.x) / 2 + Math.sin(time / 1400 + from.y) * 22;
    const midY = (from.y + to.y) / 2 + Math.cos(time / 1600 + to.x) * 18;
    ctx.quadraticCurveTo(midX, midY, to.x, to.y);
    ctx.strokeStyle = isTop ? `rgba(55, 215, 255, ${0.32 + pulse * 0.38})` : `rgba(80, 118, 164, ${intensity})`;
    ctx.lineWidth = isTop ? 2.4 + pulse * 1.8 : 1.1 + intensity * 1.8;
    ctx.shadowColor = isTop ? "rgba(55, 215, 255, 0.75)" : "transparent";
    ctx.shadowBlur = isTop ? 12 : 0;
    ctx.stroke();
    ctx.shadowBlur = 0;
  }
}

function drawNode(ctx, host, topHost, time, width, height) {
  const { x, y } = pointFor(host, width, height);
  const isTop = host.id === topHost.id;
  const color = colorForHost(host);
  const thermal = normalizeCpuTemperature(host.cpuTempC);
  const pulse = (Math.sin(time / 520) + 1) / 2;
  const radius = isTop ? 35 : 19;

  if (isTop) {
    for (let i = 0; i < 3; i += 1) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(255, 174, 61, ${0.16 - i * 0.04})`;
      ctx.lineWidth = 2;
      ctx.arc(x, y, radius + 18 + i * 18 + pulse * 9, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  ctx.beginPath();
  ctx.fillStyle = isTop ? "rgba(9, 20, 43, 0.96)" : "rgba(10, 18, 36, 0.86)";
  ctx.strokeStyle = isTop ? "rgba(255, 174, 61, 0.85)" : "rgba(130, 146, 173, 0.5)";
  ctx.lineWidth = isTop ? 2 : 1;
  ctx.shadowColor = isTop ? "rgba(255, 174, 61, 0.55)" : "rgba(55, 215, 255, 0.22)";
  ctx.shadowBlur = isTop ? 28 : 12;
  ctx.roundRect(x - radius, y - radius, radius * 2, radius * 2, 8);
  ctx.fill();
  ctx.stroke();
  ctx.shadowBlur = 0;

  drawRing(ctx, x, y, radius + 7, host.cpu / 100, "#4188ff");
  drawRing(ctx, x, y, radius + 12, host.memory / 100, "#37d7ff", -Math.PI / 2 + 0.4);
  drawRing(ctx, x, y, radius + 17, thermal.normalized / 100, color, -Math.PI / 2 + 0.8);

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x + radius - 6, y - radius + 6, isTop ? 5 : 4, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = isTop ? "#ffffff" : "rgba(220, 232, 255, 0.82)";
  ctx.font = isTop ? "700 13px Inter, sans-serif" : "600 11px Inter, sans-serif";
  ctx.textAlign = "center";
  ctx.fillText(host.name, x, y + radius + 32);
  ctx.fillStyle = "rgba(130, 146, 173, 0.86)";
  ctx.font = "10px Inter, sans-serif";
  ctx.fillText(`${host.cpuTempC}C CPU temp`, x, y + radius + 47);
}

function drawChart(ctx, values, color, fill, width, height) {
  ctx.clearRect(0, 0, width, height);
  ctx.strokeStyle = "rgba(130,146,173,0.18)";
  ctx.lineWidth = 1;
  for (let i = 1; i < 4; i += 1) {
    const y = (height / 4) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }
  ctx.beginPath();
  values.forEach((value, index) => {
    const x = (index / (values.length - 1)) * width;
    const y = height - value * height;
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.lineTo(width, height);
  ctx.lineTo(0, height);
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
}

function updateDom(hosts, topHost, time) {
  const agentText = reachableAgents.map((agent) => `${agent.type} on ${agent.host}`).join(" • ");
  const netTotal = topHost.networkInMbps + topHost.networkOutMbps;
  document.querySelector("#clock").textContent = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date());
  document.querySelector("#agentCount").textContent = `${reachableAgents.length} agents reachable`;
  document.querySelector("#topHostName").textContent = topHost.name;
  document.querySelector("#topScore").textContent = topHost.score;
  document.querySelector("#topReason").textContent = topHost.reason;
  document.querySelector("#metricCpu").textContent = `${topHost.cpu}%`;
  document.querySelector("#metricMemory").textContent = `${topHost.memory}%`;
  document.querySelector("#metricTemp").textContent = `${topHost.cpuTempC}C`;
  document.querySelector("#metricLatency").textContent = `${topHost.latencyMs}ms`;
  document.querySelector("#metricDiskIo").textContent = formatMbps(topHost.diskIoMbps);
  document.querySelector("#metricNet").textContent = formatMbps(netTotal);
  document.querySelector("#globalThroughput").textContent = formatMbps(hosts.reduce((sum, host) => sum + host.networkInMbps + host.networkOutMbps, 0));
  document.querySelector("#meshLatency").textContent = `${(hosts.reduce((sum, host) => sum + host.latencyMs, 0) / hosts.length).toFixed(1)} ms avg`;
  document.querySelector("#agentStrip").innerHTML = `<strong>Agent phonebook:</strong> ${agentText}. JSON available at window.tailopsAgentDirectory.`;

  const heatmap = document.querySelector("#healthHeatmap");
  heatmap.replaceChildren(...hosts.map((host) => {
    const temp = normalizeCpuTemperature(host.cpuTempC);
    const cell = document.createElement("div");
    cell.className = "heat-cell";
    cell.dataset.host = host.name;
    cell.style.background = `linear-gradient(180deg, ${colorForHost(host)}, rgba(65,136,255,0.18))`;
    cell.style.opacity = String(0.45 + temp.normalized / 180);
    return cell;
  }));
}

function render(time) {
  resizeCanvas(meshCanvas, meshCtx);
  resizeCanvas(document.querySelector("#spotlightChart"), spotlightChart);
  resizeCanvas(document.querySelector("#throughputChart"), throughputChart);
  const width = meshCanvas.clientWidth;
  const height = meshCanvas.clientHeight;
  const hosts = createTelemetrySnapshot(time);
  const topHost = getTopActiveHost(hosts);

  meshCtx.clearRect(0, 0, width, height);
  drawFlows(meshCtx, hosts, topHost, time, width, height);
  hosts.forEach((host) => drawNode(meshCtx, host, topHost, time, width, height));

  const wave = Array.from({ length: 48 }, (_, index) => 0.36 + Math.sin(time / 520 + index * 0.34) * 0.19 + Math.sin(time / 980 + index * 0.8) * 0.1);
  const disk = Array.from({ length: 48 }, (_, index) => 0.28 + Math.sin(time / 700 + index * 0.5) * 0.14);
  drawChart(spotlightChart, wave.map((v, i) => Math.max(0.08, Math.min(0.94, v + disk[i]))), "#ffae3d", "rgba(255,174,61,0.16)", spotlightChart.canvas.clientWidth, spotlightChart.canvas.clientHeight);
  drawChart(throughputChart, wave.map((v) => Math.max(0.08, Math.min(0.92, v + 0.2))), "#37d7ff", "rgba(55,215,255,0.15)", throughputChart.canvas.clientWidth, throughputChart.canvas.clientHeight);
  updateDom(hosts, topHost, time);

  requestAnimationFrame(render);
}

requestAnimationFrame(render);
