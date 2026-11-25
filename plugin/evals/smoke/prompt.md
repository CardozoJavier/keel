---
name: smoke
description: Harness smoke check; the eval runner loads the keel plugin and grades a reply.
runs: 1
max_turns: 2
allowed_tools: [Read]
tags: [smoke]
---

Reply with exactly the word KEEL-SMOKE-OK and nothing else.
