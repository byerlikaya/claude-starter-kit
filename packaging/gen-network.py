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
 "security-expert-csk":"#ff8a4d","privacy-agent-csk":"#ffbc8a","test-expert-csk":"#db5f1c","performance-expert-csk":"#f2a65a",       # audit · orange shades
 "review-agent-csk":"#b07cf6","commit-agent-csk":"#8659ee",                   # close · violet shades
 "session-manager-csk":"#9aa7cc"}                                             # session · slate
STAGE_NAME = {"plan":"PLAN","build":"BUILD","ops":"OPS","audit":"AUDIT","close":"CLOSE","session":"SESSION","core":"MAIN-THREAD"}
ORDER = ["plan","build","ops","audit","close","session","core"]

AGENTS = [("planner-csk","plan"),("backend-expert-csk","build"),("frontend-expert-csk","build"),
    ("database-expert-csk","build"),("devops-expert-csk","ops"),("security-expert-csk","audit"),
    ("privacy-agent-csk","audit"),("test-expert-csk","audit"),("performance-expert-csk","audit"),("review-agent-csk","close"),
    ("commit-agent-csk","close"),("session-manager-csk","session")]
SHORT = {"planner-csk":"planner","backend-expert-csk":"backend","frontend-expert-csk":"frontend",
    "database-expert-csk":"database","devops-expert-csk":"devops","security-expert-csk":"security",
    "privacy-agent-csk":"privacy","performance-expert-csk":"perf","test-expert-csk":"test","review-agent-csk":"review",
    "commit-agent-csk":"commit","session-manager-csk":"session"}
EDGES = {
 "backend-expert-csk":"api-design confidence-check dependency-audit devarch-module i18n-integrity observability performance sonarqube-check",
 "commit-agent-csk":"commit-message release",
 "database-expert-csk":"confidence-check db-migration sonarqube-check",
 "devops-expert-csk":"adr ci-pipeline dependency-audit dependency-upgrade docs-writer incident-runbook observability performance release trace-scan vps-deploy",
 "frontend-expert-csk":"a11y confidence-check dependency-audit frontend frontend-design frontend-rn-expo i18n-integrity observability performance",
 "planner-csk":"adr brainstorm spec-planning",
 "privacy-agent-csk":"privacy-compliance",
 "review-agent-csk":"code-review docs-writer",
 "security-expert-csk":"red-team security-scan sonarqube-check threat-model",
 "session-manager-csk":"handoff token-budget",
 "test-expert-csk":"testing",
 "performance-expert-csk":"performance"}
CORE_SKILLS = ["systematic-debugging","iterate","reflect","worktree","mcp-builder","eval-grader"]
ST_OF = dict(AGENTS)

# deliberate home-stage for each skill (so groups read clean); default = first agent's stage
SKILL_HOME = {
 "api-design":"build","devarch-module":"build","db-migration":"build","frontend":"build",
 "frontend-design":"build","frontend-rn-expo":"build","a11y":"build","i18n-integrity":"build",
 "dependency-audit":"build","dependency-upgrade":"build","observability":"build","performance":"build",
 "ci-pipeline":"ops","vps-deploy":"ops","incident-runbook":"ops","trace-scan":"ops","docs-writer":"ops",
 "adr":"plan","brainstorm":"plan","spec-planning":"plan","confidence-check":"plan",
 "security-scan":"audit","red-team":"audit","sonarqube-check":"audit","privacy-compliance":"audit","testing":"audit","threat-model":"audit",
 "code-review":"close","commit-message":"close","release":"close",
 "handoff":"session","token-budget":"session"}

def pol(cx,cy,r,deg):
    a=math.radians(deg); return (cx+r*math.cos(a), cy+r*math.sin(a))
def pt(p): return f"{p[0]:.1f},{p[1]:.1f}"

# The brand mark — ONE copy in this file, drawn wherever it is needed. assets/icon.svg is the source of truth;
# packaging/check-gh-pages.sh reads the rect literals below and compares them against it and against the site's
# inlined favicon. Three hand-kept copies already drift, which is why this is a function and not a second paste:
# every place the mark appears in a generated diagram renders these exact rects.
MARK_BOX = 200                                   # the mark's own coordinate system
def mark(tx, ty, scale):
    P=[f'<g transform="translate({tx:.1f},{ty:.1f}) scale({scale})" aria-hidden="true">']
    P.append('<rect width="200" height="200" rx="46" fill="#0B1020"/><g transform="rotate(20 100 100)">')
    P.append('<rect x="58" y="38" width="22" height="124" rx="11" fill="#E5E7FB"/>')
    P.append('<rect x="88" y="38" width="22" height="124" rx="11" fill="#B9BEF9"/>')
    P.append('<rect x="118" y="32" width="26" height="136" rx="13" fill="#A78BFA"/></g></g>')
    return "".join(P)

# Wordmark: the icon sits to the LEFT of the title, and the pair is centred as one block. The text width is
# estimated from the glyph count because there is no font metric available here; a few pixels of asymmetry in a
# title is invisible, whereas a hard-coded x would break the moment the font size changes.
TITLE = "Claude Starter Kit"
def wordmark(cx, y, fs, icon=42, gap=16):
    tw = len(TITLE.replace(" ","")) * fs*0.555 + TITLE.count(" ") * fs*0.28 - len(TITLE)*0.6
    dx = (icon+gap)/2.0
    out = mark(cx+dx-tw/2-gap-icon, y-fs*0.36-icon/2.0, icon/float(MARK_BOX))
    out += (f'<text x="{cx+dx:.1f}" y="{y}" text-anchor="middle" font-size="{fs}" font-weight="800" '
            f'fill="#f3f5ff" letter-spacing="-0.6">{TITLE}</text>')
    return out

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
    P.append(wordmark(CX, 62, 36))
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
    # The node LABEL is the short name — twelve full "-csk" names would not fit inside a 35px circle. The full
    # name goes in a <title>, which a screen reader announces on the node and a gate can grep for. Without it the
    # picture never contains the string it is a picture of, so nothing downstream can check it is complete.
    for nm,st in AGENTS:
        x,y=pol(CX,CY,R_AGENT,agent_ang[nm]); col=AGENT_COLOR[nm]
        P.append(f'<g><title>{html.escape(nm)}</title>')
        P.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="35" fill="{col}" filter="url(#glow)"/>')
        P.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="35" fill="none" stroke="#ffffff" stroke-opacity="0.85" stroke-width="2"/>')
        P.append(f'<text x="{x:.1f}" y="{y+4.5:.1f}" text-anchor="middle" font-size="12.5" font-weight="700" fill="#0b1220">{SHORT[nm]}</text>')
        P.append('</g>')
    # center: real logo. SOURCE OF TRUTH IS assets/icon.svg — the three rects below are a hand-copy of it, and
    # the gh-pages favicon (an inline data: URI in index.html) is a second hand-copy of the same artwork. None
    # of the three can see the others, so `packaging/check-gh-pages.sh` compares them; if you change the mark,
    # change assets/icon.svg first and let that gate tell you what else drifted.
    P.append(f'<circle cx="{CX}" cy="{CY}" r="64" fill="#0B1020" filter="url(#corehalo)"/>')
    P.append(f'<circle cx="{CX}" cy="{CY}" r="64" fill="none" stroke="#7C3AED" stroke-opacity="0.75" stroke-width="2"/>')
    P.append(mark(CX-48, CY-48, 0.48))
    P.append('</svg>')
    return "".join(P)

# ---------------------------------------------------------------------------------------------------------
# Pipeline diagram (orchestration-*.svg) — the SEQUENCE the network diagram cannot show at a glance.
# It lives in this file, not its own, because both pictures must draw from ONE agent list and ONE colour map:
# an agent that is green in the network and orange in the pipeline is two pictures of two different kits. The
# hand-drawn version this replaces had eleven agents in it — performance-expert-csk was simply never added, and
# nothing compared the picture to the payload. Now the columns ARE the agent list.
PIPE = [
 ("1","UNDERSTAND","ANLA",    "#5b8cff", ["planner-csk"],
  "ambiguous scope → a plan", "belirsiz kapsam → plan"),
 ("2","PRODUCE","ÜRET",       "#34d17f", ["backend-expert-csk","database-expert-csk","frontend-expert-csk","devops-expert-csk"],
  "the domain owner builds", "alanın sahibi üretir"),
 ("3","AUDIT","DENETLE",      "#ff9040", ["security-expert-csk","privacy-agent-csk","test-expert-csk","performance-expert-csk"],
  "security review is mandatory", "güvenlik incelemesi zorunlu"),
 ("4","CLOSE","KAPAT",        "#a874f5", ["review-agent-csk","commit-agent-csk"],
  "DoD gate · waits for your approval", "Bitti kapısı · onayınızı bekler"),
 ("5","HAND OFF","DEVRET",    "#94a3c8", ["session-manager-csk"],
  "context fills → hand off, /clear", "bağlam doldu → devret, /clear"),
]
# Fail loudly rather than draw a wrong picture: a new agent must be placed in a stage, not silently dropped.
_pipe_agents = [a for _,_,_,_,ags,_,_ in PIPE for a in ags]
_known = [a for a,_ in AGENTS]
assert sorted(_pipe_agents) == sorted(_known), \
    "PIPE does not cover every agent: missing %s, unknown %s" % (
        sorted(set(_known)-set(_pipe_agents)), sorted(set(_pipe_agents)-set(_known)))

# Canvas sized for how it is actually VIEWED. The README embeds this at width="820"; a 1300-wide canvas is then
# scaled to 63% and 12.5px label text lands at 7.9px on screen — legible in the file, unreadable on the page.
# At 900 the same embed scales to 91%, so the sizes below are close to what the reader gets. Labels use the SHORT
# agent name for the same reason the network diagram does — the full name goes in <title>, where a screen reader
# announces it and the smoke-test gate greps for it.
PW, PH = 900, 424
def build_pipeline(subtitle, tr=False):
    cols=len(PIPE); m=40; usable=PW-2*m; cw=usable/cols
    P=[]
    P.append(f'<svg viewBox="0 0 {PW} {PH}" xmlns="http://www.w3.org/2000/svg" font-family="\'Segoe UI\',system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif" role="img" aria-label="Claude Starter Kit — five stages">')
    P.append('<defs>')
    P.append('<radialGradient id="bg" cx="50%" cy="42%" r="78%"><stop offset="0" stop-color="#101a34"/><stop offset="1" stop-color="#05070f"/></radialGradient>')
    P.append('<filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    P.append('</defs>')
    P.append(f'<rect width="{PW}" height="{PH}" fill="url(#bg)"/>')
    P.append(wordmark(PW/2, 54, 30, icon=36, gap=13))
    P.append(f'<text x="{PW/2}" y="80" text-anchor="middle" font-size="12" fill="#8b96c6" font-family="ui-monospace,Menlo,monospace" letter-spacing="1.4">{subtitle}</text>')
    HEAD_Y, FIRST_Y, CHIP_H, GAP = 126, 186, 42, 11
    for i,(num,en,trn,col,ags,cap_en,cap_tr) in enumerate(PIPE):
        cx=m+cw*i+cw/2; name=trn if tr else en; cap=cap_tr if tr else cap_en
        # stage column: a tinted band so the group reads as one unit, exactly as the network's sectors do
        P.append(f'<rect x="{cx-cw/2+6:.1f}" y="{HEAD_Y-26}" width="{cw-12:.1f}" height="{PH-HEAD_Y-2}" rx="14" fill="{col}" fill-opacity="0.06" stroke="{col}" stroke-opacity="0.22" stroke-width="1"/>')
        P.append(f'<text x="{cx:.1f}" y="{HEAD_Y}" text-anchor="middle" font-size="14.5" font-weight="800" fill="{col}" font-family="ui-monospace,Menlo,monospace" letter-spacing="1.2">{num} · {html.escape(name)}</text>')
        P.append(f'<text x="{cx:.1f}" y="{HEAD_Y+21}" text-anchor="middle" font-size="11.5" fill="#94a0cc">{html.escape(cap)}</text>')
        for j,ag in enumerate(ags):
            y=FIRST_Y+j*(CHIP_H+GAP); acol=AGENT_COLOR[ag]; w=cw-24
            P.append(f'<g><title>{html.escape(ag)}</title>')
            P.append(f'<rect x="{cx-w/2:.1f}" y="{y:.1f}" width="{w:.1f}" height="{CHIP_H}" rx="11" fill="#0f1830" stroke="{acol}" stroke-width="1.8" filter="url(#glow)"/>')
            P.append(f'<circle cx="{cx-w/2+16:.1f}" cy="{y+CHIP_H/2:.1f}" r="5.5" fill="{acol}"/>')
            P.append(f'<text x="{cx+8:.1f}" y="{y+CHIP_H/2+5:.1f}" text-anchor="middle" font-size="14.5" font-weight="600" fill="#eaf0ff">{html.escape(SHORT[ag])}</text>')
            P.append('</g>')
        if i < cols-1:                                   # chevron into the next stage
            ax=m+cw*(i+1); ay=FIRST_Y+CHIP_H/2
            P.append(f'<path d="M{ax-8:.1f},{ay-7:.1f} L{ax+1:.1f},{ay:.1f} L{ax-8:.1f},{ay+7:.1f}" fill="none" stroke="#94a0cc" stroke-opacity="0.8" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')
    P.append('</svg>')
    return "".join(P)

# ---------------------------------------------------------------------------------------------------------
# Handover strip (handover-*.svg) — what `adopt.sh` does, in order. Generated here for the same two reasons the
# pipeline is: one visual language across every diagram in the README, and no hand-kept copy to drift. The stage
# hues are reused from STAGE so a reader who has learned the colours on one picture keeps reading them here.
HANDOVER = [
 ("Detect",     "Tespit",   "",              "",             "#5b8cff"),
 ("Propose",    "Öneri",    "7 decisions",   "7 karar",      "#5b8cff"),
 ("Handover",   "Dal aç",   "branch",        "devir",        "#a874f5"),
 ("Coexist",    "Birlikte", "-csk agents",   "-csk ajan",    "#34d17f"),
 ("Discipline", "Disiplin", "+ settings",    "+ ayarlar",    "#34d17f"),
 ("Proof",      "Kanıt",    "gates ready",   "kapılar hazır","#ff9040"),
 ("HANDOVER.md","HANDOVER.md","+ ADR",       "+ ADR",        "#26c6e6"),
]
# Same sizing rule as the pipeline: the README embeds this at width="900", so a 1000-wide canvas renders at 90%
# and the type below is close to what the reader actually sees.
HW, HH = 1000, 132
def build_handover(tr=False):
    n=len(HANDOVER); m=20; gap=12
    bw=(HW-2*m-gap*(n-1))/n
    P=[]
    P.append(f'<svg viewBox="0 0 {HW} {HH}" xmlns="http://www.w3.org/2000/svg" font-family="\'Segoe UI\',system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif" role="img" aria-label="Claude Starter Kit — handover steps">')
    P.append('<defs>')
    P.append('<linearGradient id="hbg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#101a34"/><stop offset="1" stop-color="#070b18"/></linearGradient>')
    P.append('<filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    P.append('</defs>')
    P.append(f'<rect width="{HW}" height="{HH}" fill="url(#hbg)"/>')
    BY, BH = 30, 72
    for i,(en,trn,sen,strn,col) in enumerate(HANDOVER):
        x=m+i*(bw+gap); title=trn if tr else en; sub=strn if tr else sen
        P.append(f'<rect x="{x:.1f}" y="{BY}" width="{bw:.1f}" height="{BH}" rx="13" fill="#0f1830" stroke="{col}" stroke-width="1.8" filter="url(#glow)"/>')
        P.append(f'<circle cx="{x+16:.1f}" cy="{BY+15:.1f}" r="8.5" fill="{col}" fill-opacity="0.18" stroke="{col}" stroke-width="1.4"/>')
        P.append(f'<text x="{x+16:.1f}" y="{BY+18.6:.1f}" text-anchor="middle" font-size="9.5" font-weight="800" fill="{col}" font-family="ui-monospace,Menlo,monospace">{i+1}</text>')
        ty=BY+42 if sub else BY+42
        P.append(f'<text x="{x+bw/2:.1f}" y="{ty}" text-anchor="middle" font-size="15" font-weight="700" fill="#eaf0ff">{html.escape(title)}</text>')
        if sub:
            P.append(f'<text x="{x+bw/2:.1f}" y="{ty+19}" text-anchor="middle" font-size="11.5" fill="#94a0cc" font-family="ui-monospace,Menlo,monospace">{html.escape(sub)}</text>')
        if i < n-1:
            ax=x+bw+gap/2
            P.append(f'<path d="M{ax-4:.1f},{BY+BH/2-6:.1f} L{ax+4:.1f},{BY+BH/2:.1f} L{ax-4:.1f},{BY+BH/2+6:.1f}" fill="none" stroke="#94a0cc" stroke-opacity="0.8" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    foot_en="every change lands on a branch, staged and uncommitted — main is never touched"
    foot_tr="her değişiklik ayrı bir dala commit'lenmeden düşer — main'e hiç dokunulmaz"
    P.append(f'<text x="{HW/2}" y="{BY+BH+26}" text-anchor="middle" font-size="12" fill="#8b96c6">{html.escape(foot_tr if tr else foot_en)}</text>')
    P.append('</svg>')
    return "".join(P)

# ---------------------------------------------------------------------------------------------------------
# Command flow (workflow-*.svg) — the same five stages, but named by the slash command you actually type. It
# replaces an ASCII block that could not be aligned in both languages at once: Turkish wraps longer, so the
# columns drifted apart in one README while looking right in the other.
FLOW = [
 # (tr_cmd, en_cmd, colour, tr_line1, en_line1, tr_line2, en_line2)
 # Both the command label AND both body lines are per-language: an earlier version shared one label field, and
 # the English diagram shipped reading "uzman ajanlar". Lines are kept short enough to fit the box at the width
 # below — a label that overflows its box is worse than no label, because it renders on top of the border.
 ("/plan-csk",     "/plan-csk",     "#5b8cff", "belirsiz kapsam", "ambiguous scope",   "planlamaya gider",  "goes to planning"),
 ("uzman ajanlar", "expert agents", "#34d17f", "alanın sahibi",   "the domain owner",  "işi yapar",         "does the work"),
 ("/review-csk",   "/review-csk",   "#ff9040", "güvenlik · kalite","security · quality","· test denetimi",  "· test audit"),
 ("/ship-csk",     "/ship-csk",     "#a874f5", "Bitti Tanımı",    "Definition of Done","onayınızı bekler",  "waits for approval"),
 ("/handoff-csk",  "/handoff-csk",  "#94a3c8", "bağlam doldu",    "context is full",   "devret, /clear",    "hand off, /clear"),
]
FW, FH = 960, 232
def build_flow(tr=False):
    n=len(FLOW); m=26; gap=10; bw=(FW-2*m-gap*(n-1))/n
    P=[f'<svg viewBox="0 0 {FW} {FH}" xmlns="http://www.w3.org/2000/svg" font-family="\'Segoe UI\',system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif" role="img" aria-label="Claude Starter Kit — command flow">']
    P.append('<defs><linearGradient id="fbg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#101a34"/><stop offset="1" stop-color="#070b18"/></linearGradient>')
    P.append('<filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>')
    P.append(f'<rect width="{FW}" height="{FH}" fill="url(#fbg)"/>')
    BY,BH = 40, 112
    for i,(cmd_tr,cmd_en,col,t1,e1,t2,e2) in enumerate(FLOW):
        x=m+i*(bw+gap); cmd=cmd_tr if tr else cmd_en; l1=t1 if tr else e1; l2=t2 if tr else e2
        # No accent bar across the top: a full-width r=2 strip on an r=13 box pokes out past the rounded corners
        # and reads as a rendering fault. The coloured stroke already identifies the stage.
        P.append(f'<rect x="{x:.1f}" y="{BY}" width="{bw:.1f}" height="{BH}" rx="13" fill="#0f1830" stroke="{col}" stroke-width="1.8" filter="url(#glow)"/>')
        P.append(f'<text x="{x+bw/2:.1f}" y="{BY+34:.1f}" text-anchor="middle" font-size="13.5" font-weight="700" fill="{col}" font-family="ui-monospace,Menlo,monospace">{html.escape(cmd)}</text>')
        P.append(f'<text x="{x+bw/2:.1f}" y="{BY+66:.1f}" text-anchor="middle" font-size="12.5" fill="#eaf0ff">{html.escape(l1)}</text>')
        P.append(f'<text x="{x+bw/2:.1f}" y="{BY+87:.1f}" text-anchor="middle" font-size="12.5" fill="#94a0cc">{html.escape(l2)}</text>')
        if i<n-1:
            ax=x+bw+gap/2
            P.append(f'<path d="M{ax-4:.1f},{BY+BH/2-7:.1f} L{ax+4:.1f},{BY+BH/2:.1f} L{ax-4:.1f},{BY+BH/2+7:.1f}" fill="none" stroke="#94a0cc" stroke-opacity="0.85" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    foot = "her adım bir öncekini doğrular; commit en sonda, onayınızla" if tr else "each step verifies the one before it; the commit comes last, with your approval"
    P.append(f'<text x="{FW/2}" y="{BY+BH+40}" text-anchor="middle" font-size="12.5" fill="#8b96c6">{html.escape(foot)}</text>')
    P.append('</svg>')
    return "".join(P)

import sys
ASSETS=sys.argv[1] if len(sys.argv)>1 else "."
# The subtitle is DERIVED, never typed. It was hand-written once and then drifted the way every hand-written
# count in this repo has drifted: the diagram itself was regenerated with 12 agents and 38 skills while the line
# above it still announced 11 and 36 — the one part of the picture a reader takes at face value, because nobody
# counts 38 nodes to check. Anything the picture claims about itself now comes from the data that drew it.
NAG, NSK = len(AGENTS), len(skill_pos)
SUB_EN=f'{NAG} AGENTS × {NSK} SKILLS · GROUPED BY STAGE · EVERY LINE A REAL "applies"'
SUB_TR=f'{NAG} AJAN × {NSK} SKILL · AŞAMAYA GÖRE GRUPLU · HER ÇİZGİ GERÇEK BİR "applies"'
open(ASSETS+"/network-en.svg","w").write(build(SUB_EN))
open(ASSETS+"/network-tr.svg","w").write(build(SUB_TR))
PSUB_EN=f'{NAG} AGENTS · FIVE STAGES · QUALITY ESCALATES BEFORE ANYTHING IS COMMITTED'
PSUB_TR=f'{NAG} AJAN · BEŞ AŞAMA · HİÇBİR ŞEY COMMIT EDİLMEDEN KALİTE YÜKSELİR'
open(ASSETS+"/orchestration-en.svg","w").write(build_pipeline(PSUB_EN))
open(ASSETS+"/orchestration-tr.svg","w").write(build_pipeline(PSUB_TR, tr=True))
open(ASSETS+"/handover-en.svg","w").write(build_handover())
open(ASSETS+"/handover-tr.svg","w").write(build_handover(tr=True))
open(ASSETS+"/workflow-en.svg","w").write(build_flow())
open(ASSETS+"/workflow-tr.svg","w").write(build_flow(tr=True))
print("wrote network-{en,tr} + orchestration-{en,tr} + handover-{en,tr}.svg to",ASSETS,"| agents",NAG,"skills",NSK)
