# TailOps Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free ambient mesh dashboard for Tailscale host monitoring with CPU temperature and an under-the-hood agent directory.

**Architecture:** Use static HTML/CSS and browser JavaScript modules. Keep telemetry scoring and agent directory logic in pure modules with Node tests, and keep rendering in a separate app module that consumes those data APIs.

**Tech Stack:** HTML, CSS, JavaScript modules, Canvas 2D, Node built-in test runner.

---

### Task 1: Data Model Tests

**Files:**
- Create: `tests/telemetry.test.js`
- Create: `tests/agents.test.js`
- Create: `package.json`

- [x] **Step 1: Write failing tests for activity scoring, CPU temperature, and agent directory.**
- [ ] **Step 2: Run `npm test` and confirm module-not-found failures.**

### Task 2: Pure Data Modules

**Files:**
- Create: `src/telemetry.js`
- Create: `src/agents.js`

- [ ] **Step 1: Implement activity scoring and top host selection.**
- [ ] **Step 2: Implement CPU temperature normalization.**
- [ ] **Step 3: Implement agent directory serialization.**
- [ ] **Step 4: Run `npm test` and confirm all tests pass.**

### Task 3: Ambient Dashboard Surface

**Files:**
- Create: `index.html`
- Create: `src/styles.css`
- Create: `src/app.js`

- [ ] **Step 1: Build the full-screen mesh canvas and overlay panels.**
- [ ] **Step 2: Render hosts, traffic flows, health rings, CPU temperature markers, and active-host spotlight.**
- [ ] **Step 3: Add ambient animation and chart updates using simulated data.**
- [ ] **Step 4: Expose the agent directory from the browser console and downloadable JSON script tag.**

### Task 4: Documentation And Publishing Prep

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `data/agents.sample.json`

- [ ] **Step 1: Document the Stitch project link, design screenshot, local usage, and future integration points.**
- [ ] **Step 2: Initialize git, run tests, and prepare for a public GitHub repo under `stonehub`.**
