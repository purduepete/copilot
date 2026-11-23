---
name: vscode-extension
description: >-
  Create, update, or publish a VS Code extension for @jimb. Use the lerxst
  Marketplace publisher and jimlertech GitHub URLs, and keep the Marketplace
  token out of chat and commands. WHEN: "create a VS Code extension", "update an
  extension", "publish the extension", "prepare a Marketplace release".
argument-hint: Extension repo and requested change or release
---

# VS Code extensions

- Set `"publisher": "lerxst"` in the extension's `package.json`.
- Extension repositories belong to the `jimlertech` GitHub organization.
  Set `repository`, `bugs`, and `homepage` URLs to
  `github.com/jimlertech/<repo>`.
- Publish with `npx @vscode/vsce login lerxst`, then `npx @vscode/vsce publish`.
- The Marketplace PAT comes from Azure DevOps with **All accessible
  organizations** and **Marketplace > Manage**. Never ask @jimb to paste the
  token into chat or put it in a command. He enters it at the `vsce login`
  prompt.
