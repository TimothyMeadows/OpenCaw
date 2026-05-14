# Playwright Package Scripts

Suggested host `package.json` scripts:

```json
{
  "scripts": {
    "test": "playwright test",
    "test:ci": "playwright test --project=chromium-ci",
    "test:report": "./.codex/commands/playwright-evidence-report.sh"
  },
  "devDependencies": {
    "@playwright/test": "^1.58.0",
    "typescript": "^5.0.0"
  }
}
```
