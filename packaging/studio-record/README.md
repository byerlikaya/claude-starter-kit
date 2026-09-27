# Studio recordings

Re-records the two Studio pictures in `assets/` after a change to the panel:

| File | Where it is shown | What it shows |
|:--|:--|:--|
| `studio-panels.gif` | the Studio page | a session opened from the project list, an agent's report and tool timeline, the jump to the failure, the conversation behind it |
| `studio-graph.png` | the Studio page | the finished graph: twelve agents and a workflow |

```bash
bash packaging/studio-record/record.sh
```

The file names stay the same, so the site picks up a new recording without an edit.

## What it does

1. `fixture.mjs` writes a synthetic transcript tree: four demo projects, their sessions, twelve agents and a
   workflow. Every project, path, session id and sentence is invented. The projects themselves are created under
   `/Users/Shared/dev`, because the panel reads each project's `.claude/VERSION` from its working directory and shows
   a path under `/Users/<name>` as `~/…`. The script deletes only directories it marked itself.
2. The panel runs from `kit/studio/` in isolation: its own projects root, runtime directory and token, and a
   version feed given as a `data:` URL, so it reads nothing from the network and no real session can appear.
3. `grow.mjs` replays the hero session step by step while `shoot.mjs` films it. `shoot.mjs` drives a headless
   Chrome with a throwaway profile over the DevTools protocol (`cdp.mjs`), so no automation banner and no other
   window can reach a frame. The two sidebar sections that describe the machine running the panel stay folded.
4. `tour.mjs` clicks through the panels on the finished fixture.
5. The last frame of the replay is kept as the graph still, and ffmpeg encodes the panels GIF at 1600 px wide,
   10 fps and 128 colours.

The version shown on the demo projects and in the header is the repository's `VERSION`. Set `VERSION_SHOWN` to
record another one.

## Requirements

macOS, Node 22, ffmpeg and Google Chrome. No model session is started and no tokens are spent. Working files go to
`$TMPDIR/crewforth-studio-record` (`CREW_RECORD_TMP` moves them). The panel listens on port 7802
(`CREW_RECORD_PORT`).

This directory is not part of the npm package or the plugin.
