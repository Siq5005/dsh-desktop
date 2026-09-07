# Codex Terra Bash Diagnosis

Date: 2026-08-22
Target session: session-73a2399c-e111-46be-960a-4a6e4d18e32a

## Direct finding

The same model id, gpt-5.6-terra, is routed through different provider protocols:

- ruoli-gpt: openai-completions, https://ruoli.dev/v1
- codex: openai-responses, https://ai.novacode.top/

The target session log shows Codex bash tool calls carrying sandbox_permissions: danger-full-access and a justification. The session effective sandbox mode is already danger-full-access. The call therefore fails before command execution with:

sandbox escalation to danger-full-access is not strictly wider than this call current danger-full-access mode

The same failure was observed for Codex Sol/default paths; Ruoli Terra entered bash successfully.

## Root cause chain

1. Provider/protocol adaptation differs: Codex uses OpenAI Responses, Ruoli uses OpenAI Completions.
2. The Codex route/model emits or preserves a same-mode sandbox escalation field in tool-call arguments.
3. dsh-tool-bash calls approveBashEscalation whenever both escalation fields are present (lib/index.js around line 389).
4. dsh-sandbox rejects any requested mode that is not strictly wider than the effective mode (lib/index.js around line 94).

This is not a missing Terra capability and not a shell execution failure. It is a provider/tool-argument adaptation mismatch exposed by the local strict permission validator.

## Smallest-scope candidate

Prefer a Codex-route/tool-argument fix that removes or ignores sandbox_permissions when it equals the session effective mode, leaving global escalation validation unchanged. Do not change the global sandbox ladder or affect Ruoli. A session-only prompt workaround is lower risk for immediate operation but is not a durable provider fix.

No runtime code or active session was changed during this diagnosis. The running target task was not cancelled, restarted, or reconfigured after the investigation began.

## Fix applied

Updated @deepseek-ai/dsh-sandbox/lib/index.js so a requested sandbox mode equal to the effective mode is treated as an idempotent no-op. Strictly wider modes still require the existing approval path. This is a global semantic fix for same-mode requests, but it does not grant additional access or change the escalation ladder. The DSH process was not restarted; restart is intentionally left for the user.
