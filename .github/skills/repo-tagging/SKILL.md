---
name: repo-tagging
description: "Create a repo tag or release tag for this project. Use when the user says create a repo tag, cut a release tag, publish a new version tag, or trigger the GitHub Actions release workflow."
argument-hint: "Requested version tag or bump type"
---

# Repo Tagging

Use this skill when the user wants a new repository tag that should trigger the release workflow.

## Workflow Trigger
- The release workflow is in `.github/workflows/release-windows.yml`.
- It runs on `push` for tags matching `v*`.
- Creating a local tag is not enough. The tag must be pushed to `origin` to trigger GitHub Actions.

## Project Conventions
- Use `v`-prefixed semantic version tags, like `v0.1.5`.
- Prefer annotated tags.
- Tag the current `HEAD` unless the user explicitly asks for a different commit.

## Procedure
1. Check that the repository is on the intended branch/commit.
2. Check whether the worktree is clean.
3. List existing tags and identify the latest `v*` tag.
4. If the user did not specify a version, default to the next patch version from the latest `v*` tag.
5. Create an annotated tag: `git tag -a <tag> -m "Release <tag>"`.
6. Push the tag: `git push origin <tag>`.
7. Report the tag name and the commit it was created from.

## Safety Notes
- If there are uncommitted changes, warn that the tag will point only to committed `HEAD` content.
- If the requested tag already exists, stop and report it instead of force-moving it.
- Do not create lightweight tags for release workflow usage unless the user explicitly asks.

## Verification
1. Confirm the tag exists locally with `git tag --list <tag>`.
2. Confirm the push succeeded.
3. Mention that the pushed tag matches the workflow trigger pattern `v*`.