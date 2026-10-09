#!/usr/bin/env node
/**
 * render_sotu.mjs — Mission Control State of the Union renderer.
 *
 * Reads state.json (+ journal.md if present) from its own directory and writes
 * state-of-the-union.html next to them. Dependency-free, Node >= 18.
 *
 * Usage:  node ops/mission/render-sotu.mjs [--enhanced]
 * The HTML is GENERATED — never hand-edit it. Change state.json and re-render.
 *
 * The renderer degrades gracefully on missing fields (it does NOT validate the
 * schema — the model maintaining state.json is the validator) and warns on
 * stderr when it defaults something important.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const statePath = join(here, "state.json");
const journalPath = join(here, "journal.md");
const outPath = join(here, "state-of-the-union.html");
const enhanced = process.argv.includes("--enhanced");

if (!existsSync(statePath)) {
  console.error(`No state.json found at ${statePath}`);
  process.exit(1);
}

let state;
try {
  // Strip a UTF-8 BOM if present — PowerShell 5.1's `-Encoding utf8` writes one,
  // and JSON.parse rejects it. Windows sessions hit this constantly.
  state = JSON.parse(readFileSync(statePath, "utf8").replace(/^﻿/, ""));
} catch (e) {
  console.error(`state.json is not valid JSON: ${e.message}`);
  process.exit(1);
}

// ---------- helpers ----------
const esc = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// Only http(s) URLs become links; anything else renders as text.
const safeUrl = (u) => (/^https?:\/\//i.test(String(u ?? "")) ? esc(u) : null);

const warn = (msg) => console.error(`[render-sotu] warning: ${msg}`);

const m = state.mission ?? {};
const phases = Array.isArray(state.phases) ? state.phases : [];
const metrics = Array.isArray(state.metrics) ? state.metrics : [];
const risks = Array.isArray(state.risks) ? state.risks : [];
const prLog = Array.isArray(state.prLog) ? state.prLog : [];
const resume = state.resume ?? {};
const policies = state.policies ?? {};

for (const p of phases) {
  if (!p.status) warn(`phase ${p.id ?? "?"} has no status — defaulting to "pending"`);
}

const allTasks = phases.flatMap((p) => p.tasks ?? []);
const doneTasks = allTasks.filter((t) => t.status === "done").length;
const allGates = phases.flatMap((p) => p.gates ?? []);
const passedGates = allGates.filter((g) => g.status === "passed").length;
const pct = allTasks.length ? Math.round((doneTasks / allTasks.length) * 100) : 0;

const phaseTone = { pending: "", in_progress: "amber", blocked: "red", done: "green" };
const gateTone = { pending: "", passed: "green", failed: "red", waived: "amber" };
const taskMark = { pending: "&#9675;", in_progress: "&#9689;", blocked: "&#9888;", done: "&#9679;" };
const sevTone = { high: "red", critical: "red", medium: "amber", low: "blue" };

function journalTail(n = 12) {
  if (!existsSync(journalPath)) return [];
  const entries = readFileSync(journalPath, "utf8")
    .split(/^## /m)
    .filter((s) => s.trim())
    .map((s) => "## " + s.trim());
  return entries.slice(-n).reverse();
}

// ---------- resume prompt generation ----------
function coldStartChecklist() {
  return [
    `Read ops/mission/state.json FIRST — it is the source of truth, not this prompt.`,
    `Verify reality matches state: git log --oneline -5, and re-run the active phase's gate commands.`,
    `Follow the loop: pick next unblocked task -> branch ${policies.branchPrefix ?? "mission/"}<phase>-<slug> -> implement -> run gates -> PR -> merge per policy '${policies.merge ?? "review"}' -> update state.json -> node ops/mission/render-sotu.mjs -> commit state+journal+html.`,
    `Never hand-edit state-of-the-union.html. Never merge without fresh gate evidence in ops/mission/evidence/.`,
    `End of session: update resume.nextActions for a stranger, append journal entry, render, commit.`,
  ];
}

// Sections are null when skipped; empty strings are intentional blank-line spacers.
function joinPrompt(lines) {
  return lines.filter((l) => l !== null).join("\n");
}

function conventionLines() {
  const conv = Array.isArray(resume.conventions) ? resume.conventions : [];
  if (!conv.length) return null;
  return `Mission conventions:\n${conv.map((c) => `  - ${c}`).join("\n")}`;
}

function resumePromptFor(phase) {
  const gatesTodo = (phase.gates ?? [])
    .filter((g) => g.status !== "passed")
    .map((g) => `  - [${g.status ?? "pending"}] ${g.title ?? g.id ?? "?"}  ->  ${g.command ?? "(no command recorded)"}`);
  const tasksTodo = (phase.tasks ?? [])
    .filter((t) => t.status !== "done")
    .map((t) => `  - [${t.status ?? "pending"}] ${t.id ?? "?"}: ${t.title ?? ""}${t.notes ? ` (${t.notes})` : ""}`);
  const isActive = resume.activePhase === phase.id;
  const next = (isActive ? resume.nextActions ?? [] : []).map((a) => `  - ${a}`);
  const blockers = (isActive ? resume.blockers ?? [] : []).map((b) => `  - ${b}`);

  return joinPrompt([
    `You are resuming the "${m.name ?? "mission"}" mission at phase ${phase.id ?? "?"}: ${phase.title ?? ""}.`,
    ``,
    `Mission: ${m.tagline ?? ""}`,
    `North star: ${m.northStar ?? ""}`,
    `Repo: ${m.repo ?? "?"} (local: ${m.repoPath ?? "?"}), default branch: ${m.defaultBranch ?? "main"}.`,
    `Governing plan: ${m.planDoc ?? "?"}`,
    ``,
    `Phase goal: ${phase.goal ?? ""}`,
    tasksTodo.length ? `Remaining tasks:\n${tasksTodo.join("\n")}` : `All tasks in this phase are done.`,
    gatesTodo.length ? `Gates not yet passed:\n${gatesTodo.join("\n")}` : `All gates passed — close the phase and advance.`,
    next.length ? `Next actions (from last session):\n${next.join("\n")}` : null,
    blockers.length ? `Known blockers:\n${blockers.join("\n")}` : null,
    conventionLines(),
    ``,
    `Operating procedure:`,
    ...coldStartChecklist().map((c) => `  ${c}`),
  ]);
}

const globalPrompt = joinPrompt([
  `You are cold-starting the "${m.name ?? "mission"}" mission with zero prior context.`,
  ``,
  `Local repo: ${m.repoPath ?? "?"}  (${m.repo ?? "?"}, default branch ${m.defaultBranch ?? "main"})`,
  `Governing plan: ${m.planDoc ?? "?"}`,
  `Mission status: ${m.status ?? "?"} — active phase: ${resume.activePhase ?? "?"}`,
  ``,
  conventionLines(),
  conventionLines() ? `` : null,
  `Operating procedure:`,
  ...coldStartChecklist().map((c) => `  ${c}`),
]);

// ---------- component renderers ----------
const chip = (text, tone = "") => `<span class="chip ${tone}">${esc(text)}</span>`;

/**
 * Metric coloring honors metrics[].direction ("up"|"down" = which way is improvement):
 *   green = target reached; blue = moved toward target; amber = unchanged from baseline;
 *   red = moved AWAY from target (a regression must never look like progress).
 * Non-numeric values fall back to: green at target, amber otherwise.
 */
function metricTone(x) {
  const num = (v) => {
    const n = parseFloat(String(v).replace(/[^0-9.eE+-]/g, ""));
    return Number.isFinite(n) ? n : null;
  };
  const b = num(x.baseline), c = num(x.current), t = num(x.target);
  if (c === null || b === null || t === null) {
    return String(x.current) === String(x.target) ? "green" : "amber";
  }
  if (c === t || (x.direction === "down" && c < t) || (x.direction === "up" && c > t)) return "green";
  if (c === b) return "amber";
  const improving = x.direction === "down" ? c < b : x.direction === "up" ? c > b : Math.abs(c - t) < Math.abs(b - t);
  return improving ? "blue" : "red";
}

function metricsTable() {
  if (!metrics.length) return "";
  const rows = metrics
    .map(
      (x) =>
        `<tr><td><b>${esc(x.label)}</b></td><td>${esc(x.baseline)}</td><td><span class="chip ${metricTone(x)}">${esc(x.current)}</span></td><td>${esc(x.target)}</td></tr>`
    )
    .join("");
  return `<section aria-labelledby="metrics"><h2 id="metrics">Scoreboard: Baseline &rarr; Current &rarr; Target</h2>
  <div class="table-wrap"><table><thead><tr><th>Metric</th><th>Baseline</th><th>Current</th><th>Target</th></tr></thead><tbody>${rows}</tbody></table></div>
  <p class="small muted" style="margin-top:6px">green = at/past target &middot; blue = moving toward target &middot; amber = unchanged &middot; red = moving away</p></section>`;
}

function gateRows(gates) {
  return (gates ?? [])
    .map((g) => {
      const status = g.status ?? "pending";
      const notes = g.notes ? `<br><span class="small">${esc(g.notes)}</span>` : "";
      return `<tr>
      <td><span class="chip ${gateTone[status] ?? ""}">${esc(status)}</span></td>
      <td><b>${esc(g.title ?? g.id ?? "?")}</b>${notes}</td>
      <td>${g.command ? `<code>${esc(g.command)}</code>` : "&mdash;"}</td>
      <td>${g.evidence ? esc(g.evidence) : "&mdash;"}</td>
      <td>${g.lastRun ? esc(g.lastRun) : "&mdash;"}</td></tr>`;
    })
    .join("");
}

function taskList(tasks) {
  return (tasks ?? [])
    .map((t) => {
      const status = t.status ?? "pending";
      const url = safeUrl(t.pr?.url);
      const prLabel = t.pr?.number != null ? `PR #${esc(t.pr.number)}` : null;
      const pr = prLabel
        ? ` &mdash; ${url ? `<a href="${url}">${prLabel}</a>` : prLabel}${t.pr.mergedAt ? ` merged ${esc(t.pr.mergedAt)}` : ""}`
        : "";
      return `<li class="task-${esc(status)}"><span class="mark">${taskMark[status] ?? "&#9675;"}</span> <b>${esc(t.id ?? "?")}</b> ${esc(t.title ?? "")}${pr}${t.notes ? `<br><span class="muted small">${esc(t.notes)}</span>` : ""}</li>`;
    })
    .join("");
}

function phaseCards() {
  return phases
    .map((p) => {
      const status = p.status ?? "pending";
      const tasks = p.tasks ?? [];
      const done = tasks.filter((t) => t.status === "done").length;
      const ppct = tasks.length ? Math.round((done / tasks.length) * 100) : status === "done" ? 100 : 0;
      const active = resume.activePhase === p.id ? " active" : "";
      return `<article class="phase${active}">
      <header>
        <span class="chip ${phaseTone[status] ?? ""}">${esc(String(status).replace("_", " "))}</span>
        <h3>${esc(p.id ?? "?")} &middot; ${esc(p.title ?? "")}</h3>
        ${p.sessionsEstimate ? `<span class="muted small">est. sessions: ${esc(p.sessionsEstimate)}</span>` : ""}
      </header>
      <p class="muted">${esc(p.goal ?? "")}</p>
      <div class="bar"><div class="fill" style="width:${ppct}%"></div></div>
      <p class="small muted">${done}/${tasks.length} tasks &middot; ${ppct}%</p>
      ${tasks.length ? `<ul class="tasks">${taskList(tasks)}</ul>` : ""}
      ${(p.gates ?? []).length ? `<div class="table-wrap"><table><thead><tr><th>Gate</th><th>Check</th><th>Command</th><th>Evidence</th><th>Last run</th></tr></thead><tbody>${gateRows(p.gates)}</tbody></table></div>` : ""}
      <details class="resume"><summary>Resume prompt for ${esc(p.id ?? "?")} (copy into a fresh session)</summary>
        <div class="prompt-box"><button class="copy" type="button">Copy</button><pre>${esc(resumePromptFor(p))}</pre></div>
      </details>
    </article>`;
    })
    .join("");
}

function risksPanel() {
  const blockers = (resume.blockers ?? []).map((b) => `<li><span class="chip red">blocker</span> ${esc(b)}</li>`).join("");
  const riskItems = risks
    .map((r) => `<li><span class="chip ${sevTone[r.severity] ?? ""}">${esc(r.severity ?? "?")}</span> <b>${esc(r.title)}</b>${r.note ? ` &mdash; <span class="muted">${esc(r.note)}</span>` : ""}</li>`)
    .join("");
  if (!blockers && !riskItems) return "";
  return `<section aria-labelledby="risks"><h2 id="risks">Risks &amp; Blockers</h2><div class="panel"><ul class="bare">${blockers}${riskItems}</ul></div></section>`;
}

function prTimeline() {
  if (!prLog.length) return "";
  const rows = [...prLog]
    .reverse()
    .map((p) => {
      const url = safeUrl(p.url);
      return `<article class="tl-item"><time>#${esc(p.number ?? "?")}</time><p><b>${esc(p.title ?? "")}</b> &mdash; ${esc(p.phase ?? "?")}${p.mergedAt ? `, merged ${esc(p.mergedAt)}` : ""} ${url ? `&middot; <a href="${url}">view</a>` : ""}</p></article>`;
    })
    .join("");
  return `<section aria-labelledby="prs"><h2 id="prs">Merged Work (${prLog.length} PRs)</h2><div class="timeline">${rows}</div></section>`;
}

function journalSection() {
  const tail = journalTail();
  if (!tail.length) return "";
  const items = tail
    .map((e) => {
      const [head, ...rest] = e.replace(/^## /, "").split("\n");
      return `<article class="tl-item"><time>&#9998;</time><p><b>${esc(head)}</b><br>${rest.map((l) => esc(l)).join("<br>")}</p></article>`;
    })
    .join("");
  return `<section aria-labelledby="journal"><h2 id="journal">Journal (latest first)</h2><div class="timeline">${items}</div></section>`;
}

// ---------- page ----------
const statusTone = m.status === "complete" ? "green" : m.status === "paused" ? "amber" : "blue";
const gatesChipTone = !allGates.length ? "" : passedGates === allGates.length ? "green" : "amber";
const enhancedCss = enhanced ? `
#mission-story{position:fixed;z-index:0;inset:0;overflow:hidden;contain:strict;pointer-events:none}
#mission-story canvas{position:absolute;inset:-4%;width:108%;height:108%;opacity:.6;transform:translate3d(0,var(--mission-drift,0),0) scale(1.015);will-change:transform}
#mission-story .glow{position:absolute;width:min(54vw,720px);aspect-ratio:1;border-radius:50%;filter:blur(76px);opacity:.11}
#mission-story .a{top:-20%;right:-14%;background:radial-gradient(circle,rgba(88,215,179,.9),transparent 68%);transform:translate3d(calc(var(--mission-scroll,0) * -8vw),calc(var(--mission-scroll,0) * 18vh),0)}
#mission-story .b{bottom:-28%;left:-18%;background:radial-gradient(circle,rgba(255,209,102,.7),transparent 68%);transform:translate3d(calc(var(--mission-scroll,0) * 12vw),calc(var(--mission-scroll,0) * -14vh),0)}
#mission-story-label{position:absolute;right:max(22px,calc((100vw - 1180px)/2));bottom:22px;color:rgba(169,189,211,.4);font:800 .62rem ui-monospace,Menlo,Consolas,monospace;letter-spacing:.14em;text-transform:uppercase}
#mission-motion{position:fixed;z-index:4;right:18px;top:18px;border:1px solid var(--line);border-radius:999px;background:rgba(7,15,28,.72);color:var(--muted);padding:7px 11px;cursor:pointer;backdrop-filter:blur(12px)}
body.enhanced main{position:relative;z-index:1}
body.enhanced :is(.panel,.phase,.tl-item){background:linear-gradient(145deg,rgba(16,36,59,.76),rgba(7,15,28,.6));box-shadow:inset 0 1px rgba(255,255,255,.045),0 24px 70px rgba(0,0,0,.12);backdrop-filter:blur(16px) saturate(118%)}
body.enhanced :is(.table-wrap,.prompt-box pre){background:rgba(7,15,28,.94)}
body.motion-paused #mission-story canvas{opacity:.12}
@media(prefers-reduced-motion:reduce){#mission-story canvas,#mission-story .glow{display:none}body.enhanced :is(.panel,.phase,.tl-item){backdrop-filter:none}}
@media(max-width:760px){#mission-story-label{display:none}body.enhanced :is(.panel,.phase,.tl-item){backdrop-filter:blur(10px)}}
@media print{#mission-story,#mission-motion{display:none!important}body.enhanced :is(.panel,.phase,.tl-item){background:#fff;box-shadow:none;backdrop-filter:none}}
` : "";

const enhancedBackdrop = enhanced ? `<div id="mission-story" aria-hidden="true"><canvas></canvas><div class="glow a"></div><div class="glow b"></div><span id="mission-story-label">01 &middot; Mission</span></div><button id="mission-motion" type="button" aria-pressed="false">Pause motion</button>` : "";

const enhancedScript = enhanced ? `<script>
(() => {
  const root=document.documentElement,body=document.body,canvas=document.querySelector("#mission-story canvas"),ctx=canvas.getContext("2d"),label=document.getElementById("mission-story-label"),button=document.getElementById("mission-motion");
  const sections=[document.querySelector(".hero"),...document.querySelectorAll("main>section,article.phase")].filter(Boolean);
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const state={target:0,current:0,velocity:0,max:1,width:1,height:1,anchors:[],frame:0,last:performance.now(),active:-1,paused:matchMedia("(prefers-reduced-motion: reduce)").matches};
  const measure=()=>{const rect=canvas.getBoundingClientRect(),dpr=Math.min(devicePixelRatio||1,1.5);state.width=rect.width;state.height=rect.height;canvas.width=Math.max(1,Math.floor(rect.width*dpr));canvas.height=Math.max(1,Math.floor(rect.height*dpr));ctx.setTransform(dpr,0,0,dpr,0,0);state.max=Math.max(1,document.documentElement.scrollHeight-innerHeight);state.anchors=sections.map((el,index)=>({top:el.getBoundingClientRect().top+scrollY,label:el.querySelector("h1,h2,h3")?.textContent||("Chapter "+(index+1))}));state.target=clamp(scrollY,0,state.max)};
  const draw=(index,alpha,time,progress)=>{if(alpha<.002)return;const w=state.width,h=state.height,c=["#58d7b3","#77b7ff","#ffd166","#ff8f8f"][index%4],cx=w*(.74-progress*.12),cy=h*(.3+Math.sin(progress*Math.PI)*.2);ctx.save();ctx.globalAlpha=alpha*.22;ctx.strokeStyle=c;ctx.lineWidth=1;ctx.lineCap="round";if(index%3===0){for(let r=1;r<=7;r++){ctx.beginPath();ctx.arc(cx,cy,r*Math.min(w,h)*.045+Math.sin(time*.00008+r)*4,0,Math.PI*2);ctx.stroke()}}else if(index%3===1){for(let lane=0;lane<7;lane++){const y=h*(.14+lane*.115);ctx.beginPath();ctx.moveTo(w*.04,y);ctx.bezierCurveTo(w*.34,y,w*.54,cy+(lane-3)*28,w*.96,cy+(lane-3)*58);ctx.stroke()}}else{for(let row=0;row<11;row++){const y=h*.1+row*h*.07;ctx.beginPath();ctx.moveTo(w*.08,y);ctx.lineTo(w*.92,y+Math.sin(row+time*.00008)*7);ctx.stroke()}}ctx.restore()};
  const render=(time=performance.now())=>{state.frame=0;const dt=clamp((time-state.last)/16.667,.25,2);state.last=time;if(state.paused){state.current=state.target;state.velocity=0}else{state.velocity+=(state.target-state.current)*.066*dt;state.velocity*=Math.pow(.8,dt);state.current=clamp(state.current+state.velocity*dt,0,state.max)}const progress=clamp(state.current/state.max,0,1),witness=state.current+innerHeight*.48;let index=0;for(let i=1;i<state.anchors.length;i++)if(state.anchors[i].top<=witness)index=i;const next=state.anchors[index+1],blend=next?clamp((witness-(next.top-260))/520,0,1):0;ctx.clearRect(0,0,state.width,state.height);draw(index,1-blend,time,progress);if(next)draw(index+1,blend,time,progress);const visible=blend>.56&&next?index+1:index;if(visible!==state.active){state.active=visible;label.textContent=String(visible+1).padStart(2,"0")+" · "+state.anchors[visible].label}root.style.setProperty("--mission-scroll",progress.toFixed(4));root.style.setProperty("--mission-drift",clamp(state.velocity*.018,-12,12).toFixed(2)+"px");if(!state.paused&&!document.hidden)state.frame=requestAnimationFrame(render)};
  const schedule=()=>{if(!state.frame)state.frame=requestAnimationFrame(render)};
  addEventListener("scroll",()=>{state.target=clamp(scrollY,0,state.max);schedule()},{passive:true});addEventListener("resize",()=>{measure();schedule()},{passive:true});
  button.addEventListener("click",()=>{state.paused=!state.paused;body.classList.toggle("motion-paused",state.paused);button.setAttribute("aria-pressed",String(state.paused));button.textContent=state.paused?"Resume motion":"Pause motion";cancelAnimationFrame(state.frame);state.frame=0;schedule()});
  document.addEventListener("visibilitychange",()=>{cancelAnimationFrame(state.frame);state.frame=0;if(!document.hidden){state.last=performance.now();schedule()}});
  measure();state.current=state.target;body.classList.toggle("motion-paused",state.paused);button.textContent=state.paused?"Resume motion":"Pause motion";schedule();
})();
</script>` : "";
const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(m.name ?? "Mission")} — State of the Union</title>
<style>
:root{color-scheme:dark;--bg:#070f1c;--paper:#0d1b2f;--paper-2:#10243b;--ink:#eef6ff;--muted:#a9bdd3;--line:rgba(169,189,211,.18);--accent:#58d7b3;--blue:#77b7ff;--amber:#ffd166;--red:#ff8f8f;--good:#8ef2c0}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(circle at top left,rgba(88,215,179,.15),transparent 30rem),radial-gradient(circle at top right,rgba(119,183,255,.13),transparent 32rem),var(--bg);color:var(--ink);font-family:Inter,ui-sans-serif,system-ui,"Segoe UI",sans-serif;line-height:1.55}
main{width:min(1180px,calc(100% - 32px));margin:0 auto;padding:40px 0 60px}
h1,h2,h3{margin:0;line-height:1.12}
h1{font-size:clamp(2rem,5vw,3.8rem);letter-spacing:-.04em;max-width:900px;margin-top:10px}
h2{margin-bottom:14px;font-size:clamp(1.4rem,2.6vw,2rem)}
h3{font-size:1.02rem;color:#fff}
p{margin:0}
a{color:var(--blue)}
code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.85em;color:#dff7ef;overflow-wrap:anywhere}
.eyebrow{color:var(--accent);font-size:.78rem;font-weight:800;letter-spacing:.14em;text-transform:uppercase}
.muted{color:var(--muted)}
.small{font-size:.85rem}
section{padding-top:34px}
.hero{padding:20px 0 26px;border-bottom:1px solid var(--line)}
.hero .tagline{max-width:760px;margin-top:14px;color:var(--muted);font-size:1.06rem}
.chip{display:inline-flex;align-items:center;border:1px solid var(--line);border-radius:999px;padding:3px 10px;margin:2px 6px 2px 0;background:rgba(255,255,255,.05);color:var(--muted);font-size:.78rem;font-weight:800}
.chip.green{color:var(--good);border-color:rgba(142,242,192,.4)}
.chip.amber{color:var(--amber);border-color:rgba(255,209,102,.4)}
.chip.red{color:var(--red);border-color:rgba(255,143,143,.4)}
.chip.blue{color:var(--blue);border-color:rgba(119,183,255,.4)}
.panel,.phase{border:1px solid var(--line);border-radius:16px;background:linear-gradient(180deg,rgba(16,36,59,.95),rgba(13,27,47,.95));box-shadow:0 18px 46px rgba(0,0,0,.25);padding:20px}
.phase{margin-top:14px}
.phase.active{border-color:rgba(88,215,179,.45)}
.phase header{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin-bottom:8px}
.bar{height:10px;border-radius:999px;background:rgba(255,255,255,.07);margin-top:12px;overflow:hidden}
.bar .fill{height:100%;border-radius:999px;background:linear-gradient(90deg,var(--accent),var(--blue))}
.bar.big{height:16px}
ul.tasks,ul.bare{list-style:none;margin:12px 0 0;padding:0}
ul.tasks li,ul.bare li{padding:8px 0;border-top:1px solid var(--line);color:var(--muted)}
ul.tasks li:first-child,ul.bare li:first-child{border-top:0}
ul.tasks .mark{margin-right:6px;color:var(--accent)}
li.task-done{opacity:.75}
li.task-blocked .mark{color:var(--red)}
table{width:100%;border-collapse:collapse;margin-top:12px;font-size:.9rem}
th,td{border:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}
th{background:rgba(255,255,255,.05);color:#fff;font-size:.76rem;letter-spacing:.06em;text-transform:uppercase}
td{color:var(--muted)}
td b{color:#fff}
.table-wrap{overflow-x:auto;border-radius:12px}
.timeline{display:grid;gap:10px}
.tl-item{display:grid;grid-template-columns:72px 1fr;gap:14px;border:1px solid var(--line);border-radius:12px;padding:12px 14px;background:rgba(255,255,255,.035)}
.tl-item time{color:var(--accent);font-size:.8rem;font-weight:900}
.tl-item p{color:var(--muted)}
details.resume{margin-top:14px;border:1px dashed rgba(88,215,179,.4);border-radius:12px;padding:10px 14px}
details.resume summary{cursor:pointer;color:var(--accent);font-weight:800}
.prompt-box{position:relative;margin-top:10px}
.prompt-box pre{margin:0;border:1px solid var(--line);border-radius:10px;background:#081120;color:#dff7ef;padding:14px;font-size:.82rem;white-space:pre-wrap;overflow-wrap:anywhere;max-height:420px;overflow:auto}
button.copy{position:absolute;top:8px;right:8px;border:1px solid var(--line);border-radius:8px;background:rgba(255,255,255,.08);color:var(--ink);font-weight:700;padding:4px 12px;cursor:pointer}
button.copy:hover{background:rgba(88,215,179,.2)}
.footer{margin-top:40px;border-top:1px solid var(--line);padding-top:16px;color:var(--muted);font-size:.9rem}
@media(max-width:900px){main{width:min(100% - 24px,760px)}.tl-item{grid-template-columns:56px 1fr}}
${enhancedCss}
</style>
</head>
<body${enhanced ? ' class="enhanced"' : ""}>
${enhancedBackdrop}
<main>
  <header class="hero">
    <p class="eyebrow">Mission Control &middot; State of the Union &middot; generated ${esc(new Date().toISOString().slice(0, 16).replace("T", " "))}Z</p>
    <h1>${esc(m.name ?? "Mission")}</h1>
    <p class="tagline">${esc(m.tagline ?? "")}</p>
    <div style="margin-top:14px">
      ${chip(`mission: ${m.status ?? "?"}`, statusTone)}
      ${chip(`active phase: ${resume.activePhase ?? "?"}`, "green")}
      ${chip(`${doneTasks}/${allTasks.length} tasks`, "blue")}
      ${chip(`${passedGates}/${allGates.length} gates passed`, gatesChipTone)}
      ${chip(`${prLog.length} PRs merged`)}
      ${chip(`sessions: ${m.sessionCount ?? 1}`)}
      ${chip(`updated: ${m.updated ?? "?"}`)}
    </div>
    <div class="bar big" role="img" aria-label="Overall progress ${pct}%"><div class="fill" style="width:${pct}%"></div></div>
    <p class="small muted" style="margin-top:6px">Overall: ${pct}% of tasks complete &middot; repo ${esc(m.repo ?? "?")} &middot; plan: ${esc(m.planDoc ?? "?")}</p>
  </header>

  <section aria-labelledby="coldstart">
    <h2 id="coldstart">Cold-Start Prompt (any new session, zero context)</h2>
    <div class="panel">
      <div class="prompt-box"><button class="copy" type="button">Copy</button><pre>${esc(globalPrompt)}</pre></div>
    </div>
  </section>

  ${metricsTable()}
  ${risksPanel()}

  <section aria-labelledby="phases">
    <h2 id="phases">Phases</h2>
    ${phaseCards()}
  </section>

  ${prTimeline()}
  ${journalSection()}

  <p class="footer">GENERATED by ops/mission/render-sotu.mjs from state.json — do not hand-edit.
  To update: edit state.json, run <code>node ops/mission/render-sotu.mjs</code>, commit both.</p>
</main>
<script>
document.querySelectorAll("button.copy").forEach((b) => {
  b.addEventListener("click", async () => {
    const text = b.parentElement.querySelector("pre").innerText;
    try { await navigator.clipboard.writeText(text); b.textContent = "Copied!"; }
    catch { const r = document.createRange(); r.selectNodeContents(b.parentElement.querySelector("pre")); const s = getSelection(); s.removeAllRanges(); s.addRange(r); b.textContent = "Select+Ctrl C"; }
    setTimeout(() => (b.textContent = "Copy"), 1600);
  });
});
</script>
${enhancedScript}
</body>
</html>
`;

writeFileSync(outPath, html);
console.log(`Rendered ${outPath}`);
console.log(`  presentation: ${enhanced ? "enhanced" : "standard"}`);
console.log(`  phases: ${phases.length}, tasks: ${doneTasks}/${allTasks.length}, gates passed: ${passedGates}/${allGates.length}, PRs: ${prLog.length}`);
