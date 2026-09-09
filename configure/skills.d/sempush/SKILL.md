---
name: sempush
description: Stage all changes, commit with a conventional commit message, and push to upstream
---

## What I do

1. Stage all changes with `git add -A`
2. Inspect the diff to determine the commit type:
   - `feat`: new feature
   - `fix`: bug fix
   - `docs`: documentation only
   - `style`: formatting, missing semicolons, etc
   - `refactor`: code change that neither fixes a bug nor adds a feature
   - `test`: adding or updating tests
   - `chore`: build process, dependencies, tooling
   - `perf`: performance improvement
3. Write a commit message following [Conventional Commits](https://www.conventionalcommits.org/) format: `<type>(<scope>): <description>`
4. Commit with the message
5. Push to the current branch. If push fails because no upstream is set, run the command git suggests (typically `git push --set-upstream origin <branch>`)

## When to use me

Use this when the user wants to commit and push their changes.

## Rules

- Always confirm the commit message with the user before committing
- Only commit if the user approves the message
- If there are no staged or unstaged changes, do nothing
- Keep the description concise and imperative
