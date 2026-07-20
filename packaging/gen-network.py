#!/usr/bin/env python3
# Grouped (by-stage sector) agent<->skill network, dark premium — Claude Starter Kit README.
import math, html

CX, CY = 650, 690
R_AGENT = 236
R_SK_A, R_SK_B = 372, 446
BAND_IN, BAND_OUT = 150, 512
R_LABEL = 548

STAGE = {"plan":"#5b8cff","build":"#34d17f","ops":"#26c6e6","audit":"#ff9040",
         "close":"#a874f5","session":"#94a3c8","core":"#c79bff"}
# each AGENT its own distinct colour (shade within its stage hue) so skills+edges are traceable
AGENT_COLOR = {
 "planner-csk":"#5b8cff",                                                     # plan · blue
 "backend-expert-csk":"#35c874","frontend-expert-csk":"#84e6b0","database-expert-csk":"#1e9b57",  # build · green shades
 "devops-expert-csk":"#26c6e6",                                               # ops · cyan
 "security-expert-csk":"#ff8a4d","privacy-agent-csk":"#ffbc8a","test-expert-csk":"#db5f1c",       # audit · orange shades
 "review-agent-csk":"#b07cf6","commit-agent-csk":"#8659ee",                   # close · violet shades
 "session-manager-csk":"#9aa7cc"}                                             # session · slate
STAGE_NAME = {"plan":"PLAN","build":"BUILD","ops":"OPS","audit":"AUDIT","close":"CLOSE","session":"SESSION","core":"MAIN-THREAD"}
ORDER = ["plan","build","ops","audit","close","session","core"]

AGENTS = [("planner-csk","plan"),("backend-expert-csk","build"),("frontend-expert-csk","build"),
    ("database-expert-csk","build"),("devops-expert-csk","ops"),("security-expert-csk","audit"),
    ("privacy-agent-csk","audit"),("test-expert-csk","audit"),("review-agent-csk","close"),
    ("commit-agent-csk","close"),("session-manager-csk","session")]
SHORT = {"planner-csk":"planner","backend-expert-csk":"backend","frontend-expert-csk":"frontend",
    "database-expert-csk":"database","devops-expert-csk":"devops","security-expert-csk":"security",
    "privacy-agent-csk":"privacy","test-expert-csk":"test","review-agent-csk":"review",
    "commit-agent-csk":"commit","session-manager-csk":"session"}
EDGES = {
 "backend-expert-csk":"api-design dependency-audit devarch-module i18n-integrity observability performance sonarqube-check",
 "commit-agent-csk":"commit-message release",
 "database-expert-csk":"db-migration sonarqube-check",
 "devops-expert-csk":"adr ci-pipeline dependency-audit docs-writer incident-runbook observability performance release trace-scan vps-deploy",
 "frontend-expert-csk":"a11y dependency-audit frontend frontend-design frontend-rn-expo i18n-integrity observability performance",
 "planner-csk":"adr brainstorm spec-planning",
 "privacy-agent-csk":"privacy-compliance",
 "review-agent-csk":"code-review docs-writer",
 "security-expert-csk":"red-team security-scan sonarqube-check threat-model",
 "session-manager-csk":"handoff token-budget",
 "test-expert-csk":"testing"}
CORE_SKILLS = ["systematic-debugging","iterate","reflect","worktree","mcp-builder","eval-grader"]
ST_OF = dict(AGENTS)

# deliberate home-stage for each skill (so groups read clean); default = first agent's stage
SKILL_HOME = {
 "api-design":"build","devarch-module":"build","db-migration":"build","frontend":"build",
 "frontend-design":"build","frontend-rn-expo":"build","a11y":"build","i18n-integrity":"build",
 "dependency-audit":"build","observability":"build","performance":"build",
 "ci-pipeline":"ops","vps-deploy":"ops","incident-runbook":"ops","trace-scan":"ops","docs-writer":"ops",
 "adr":"plan","brainstorm":"plan","spec-planning":"plan",
 "security-scan":"audit","red-team":"audit","sonarqube-check":"audit","privacy-compliance":"audit","testing":"audit","threat-model":"audit",
 "code-review":"close","commit-message":"close","release":"close",
 "handoff":"session","token-budget":"session"}

def pol(cx,cy,r,deg):
    a=math.radians(deg); return (cx+r*math.cos(a), cy+r*math.sin(a))
def pt(p): return f"{p[0]:.1f},{p[1]:.1f}"

skill_agents={}
for ag,sk in EDGES.items():
    for s in sk.split(): skill_agents.setdefault(s,[]).append(ag)
def home(s):
    if s in CORE_SKILLS: return "core"
    return SKILL_HOME.get(s, ST_OF[skill_agents[s][0]])

group_ag={st:[a for a,s in AGENTS if s==st] for st in ORDER}
group_sk={st:[] for st in ORDER}
for s in sorted(skill_agents): group_sk[home(s)].append(s)
for s in CORE_SKILLS: group_sk["core"].append(s)

weight={st:max(1,len(group_ag[st])+len(group_sk[st])) for st in ORDER}
GAP=5.0
tot=sum(weight.values()); avail=360-GAP*len(ORDER)
spans={}; start=-90.0
for st in ORDER:
    sp=avail*weight[st]/tot; spans[st]=(start,start+sp); start=start+sp+GAP

# anchor each skill to ONE agent (within its home stage) so skills cluster under their agent
anchor={}
for s in skill_agents:
    hs=home(s); cands=[a for a in skill_agents[s] if ST_OF[a]==hs]
    anchor[s]=cands[0] if cands else skill_agents[s][0]
ag_skills={a:[] for a,_ in AGENTS}
for s in sorted(skill_agents): ag_skills[anchor[s]].append(s)

agent_ang={}; skill_pos={}
for st in ORDER:
    a0,a1=spans[st]; ags=group_ag[st]
    if st=="core":                                   # core skills: no agent, spread across sector
        sks=group_sk["core"]; ns=len(sks)
        for i,s in enumerate(sks):
            f=(i+1)/(ns+1); ang=a0+(a1-a0)*f; r=R_SK_A if i%2==0 else R_SK_B
            skill_pos[s]=pol(CX,CY,r,ang)
        continue
    # subdivide the sector among its agents by (1 + #anchored skills); each agent's skills sit outward from it
    wsum=sum(1+len(ag_skills[a]) for a in ags); cur=a0
    for a in ags:
        w=1+len(ag_skills[a]); sub=(a1-a0)*w/wsum; s0,s1=cur,cur+sub
        agent_ang[a]=(s0+s1)/2
        sk=ag_skills[a]; ns=len(sk)
        for i,s in enumerate(sk):
            f=(i+1)/(ns+1); ang=s0+(s1-s0)*f; r=R_SK_A if i%2==0 else R_SK_B
            skill_pos[s]=pol(CX,CY,r,ang)
        cur=s1

def annular(a0,a1,ri,ro):
    large=1 if (a1-a0)>180 else 0
    p0=pol(CX,CY,ro,a0); p1=pol(CX,CY,ro,a1); p2=pol(CX,CY,ri,a1); p3=pol(CX,CY,ri,a0)
    return (f"M{pt(p0)} A{ro},{ro} 0 {large} 1 {pt(p1)} L{pt(p2)} A{ri},{ri} 0 {large} 0 {pt(p3)} Z")

W,H=1300,1380
def epath(x1,y1,x2,y2):
    mx,my=(x1+x2)/2,(y1+y2)/2; cx=mx+(CX-mx)*0.30; cy=my+(CY-my)*0.30
    return f'M{x1:.1f},{y1:.1f} Q{cx:.1f},{cy:.1f} {x2:.1f},{y2:.1f}'

def build(subtitle):
    P=[]
    P.append(f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" font-family="\'Segoe UI\',system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif" role="img" aria-label="Claude Starter Kit — agent/skill network">')
    P.append('<defs>')
    P.append('<radialGradient id="bg" cx="50%" cy="48%" r="72%"><stop offset="0" stop-color="#101a34"/><stop offset="1" stop-color="#05070f"/></radialGradient>')
    P.append('<filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    P.append('<filter id="eglow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="2.4"/></filter>')
    P.append('<filter id="corehalo" x="-90%" y="-90%" width="280%" height="280%"><feGaussianBlur stdDeviation="13" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    P.append('</defs>')
    P.append(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')
    P.append(f'<text x="{CX}" y="62" text-anchor="middle" font-size="36" font-weight="800" fill="#f3f5ff" letter-spacing="-0.6">Claude Starter Kit</text>')
    P.append(f'<text x="{CX}" y="92" text-anchor="middle" font-size="13" fill="#8b96c6" font-family="ui-monospace,Menlo,monospace" letter-spacing="2">{subtitle}</text>')
    for st in ORDER:
        a0,a1=spans[st]; col=STAGE[st]
        P.append(f'<path d="{annular(a0,a1,BAND_IN,BAND_OUT)}" fill="{col}" fill-opacity="0.07" stroke="{col}" stroke-opacity="0.22" stroke-width="1"/>')
        mid=(a0+a1)/2; lp=pol(CX,CY,R_LABEL,mid)
        P.append(f'<text x="{lp[0]:.1f}" y="{lp[1]:.1f}" text-anchor="middle" font-size="13" font-weight="800" fill="{col}" font-family="ui-monospace,Menlo,monospace" letter-spacing="1.5">{STAGE_NAME[st]}</text>')
    # spokes: center (main thread) -> every agent
    for nm,st in AGENTS:
        ax,ay=pol(CX,CY,R_AGENT,agent_ang[nm])
        P.append(f'<line x1="{CX}" y1="{CY}" x2="{ax:.1f}" y2="{ay:.1f}" stroke="{AGENT_COLOR[nm]}" stroke-opacity="0.30" stroke-width="1.7"/>')
    # agent->skill edges (glow + crisp), colored by agent
    for s,ags in skill_agents.items():
        sx,sy=skill_pos[s]
        for ag in ags:
            ax,ay=pol(CX,CY,R_AGENT,agent_ang[ag]); col=AGENT_COLOR[ag]; d=epath(ax,ay,sx,sy)
            P.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-opacity="0.20" stroke-width="5" filter="url(#eglow)"/>')
            P.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-opacity="0.72" stroke-width="1.7"/>')
    for s in CORE_SKILLS:
        sx,sy=skill_pos[s]; d=epath(CX,CY,sx,sy)
        P.append(f'<path d="{d}" fill="none" stroke="{STAGE["core"]}" stroke-opacity="0.22" stroke-width="5" filter="url(#eglow)"/>')
        P.append(f'<path d="{d}" fill="none" stroke="{STAGE["core"]}" stroke-opacity="0.85" stroke-width="1.8" stroke-dasharray="4 4"/>')
    # skill chips
    for s in sorted(skill_pos):
        x,y=skill_pos[s]; col=(STAGE['core'] if s in CORE_SKILLS else AGENT_COLOR[anchor[s]]); w=len(s)*7.2+24; h=27
        P.append(f'<rect x="{x-w/2:.1f}" y="{y-h/2:.1f}" width="{w:.1f}" height="{h}" rx="13.5" fill="#0f1830" stroke="{col}" stroke-width="1.6" filter="url(#glow)"/>')
        P.append(f'<text x="{x:.1f}" y="{y+4.2:.1f}" text-anchor="middle" font-size="12.5" font-weight="600" fill="#eaf0ff">{html.escape(s)}</text>')
    # agent nodes
    for nm,st in AGENTS:
        x,y=pol(CX,CY,R_AGENT,agent_ang[nm]); col=AGENT_COLOR[nm]
        P.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="35" fill="{col}" filter="url(#glow)"/>')
        P.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="35" fill="none" stroke="#ffffff" stroke-opacity="0.85" stroke-width="2"/>')
        P.append(f'<text x="{x:.1f}" y="{y+4.5:.1f}" text-anchor="middle" font-size="12.5" font-weight="700" fill="#0b1220">{SHORT[nm]}</text>')
    # center: real logo
    P.append(f'<circle cx="{CX}" cy="{CY}" r="64" fill="#0B1020" filter="url(#corehalo)"/>')
    P.append(f'<circle cx="{CX}" cy="{CY}" r="64" fill="none" stroke="#7C3AED" stroke-opacity="0.75" stroke-width="2"/>')
    P.append(f'<g transform="translate({CX-48},{CY-48}) scale(0.48)">')
    P.append('<rect width="200" height="200" rx="46" fill="#0B1020"/><g transform="rotate(20 100 100)">')
    P.append('<rect x="58" y="38" width="22" height="124" rx="11" fill="#E5E7FB"/>')
    P.append('<rect x="88" y="38" width="22" height="124" rx="11" fill="#B9BEF9"/>')
    P.append('<rect x="118" y="32" width="26" height="136" rx="13" fill="#A78BFA"/></g></g>')
    P.append('</svg>')
    return "".join(P)

import sys
ASSETS=sys.argv[1] if len(sys.argv)>1 else "."
SUB_EN='11 AGENTS × 36 SKILLS · GROUPED BY STAGE · EVERY LINE A REAL "applies"'
SUB_TR='11 AJAN × 36 SKILL · AŞAMAYA GÖRE GRUPLU · HER ÇİZGİ GERÇEK BİR "applies"'
open(ASSETS+"/network-en.svg","w").write(build(SUB_EN))
open(ASSETS+"/network-tr.svg","w").write(build(SUB_TR))
# also a local preview copy (TR) for the artifact
open("/private/tmp/claude-501/-Users-barisyerlikaya-Projects-claude-starter-kit/afb28ea5-1f6d-40d9-92a4-6c78911f8ab8/scratchpad/network.svg","w").write(build(SUB_TR))
print("wrote network-en.svg + network-tr.svg to",ASSETS,"| agents",len(AGENTS),"skills",len(skill_pos))
