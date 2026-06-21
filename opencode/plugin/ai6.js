/**
 * ai6 OpenCode plugin — the OpenCode end of the bidirectional ai6 review loop.
 *
 * Gives the Builder a first-class `ai6_review` tool. When the agent finishes a work
 * unit it calls the tool with a short context note and the changed files; the tool
 * hands the work to the Claude (Opus) Reviewer via the ask-claude.sh bridge and
 * returns Claude's review, which ends in a `VERDICT: APPROVE|REVISE|BLOCK` line.
 *
 * The tool delegates to the bridge script (default ~/.ai6/ask-claude.sh, override
 * with AI6_BRIDGE) so the review logic — request building, reviewer contract,
 * exchange logging — has a single source of truth and cannot drift.
 */
import { tool } from "@opencode-ai/plugin";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const BRIDGE = process.env.AI6_BRIDGE || join(homedir(), ".ai6", "ask-claude.sh");

/**
 * OpenCode plugin factory: registers the `ai6_review` tool.
 * @param {object} ctx - OpenCode plugin context.
 * @param {Function} ctx.$ - Bun's shell tag function. Typed as Function because the
 *   @opencode-ai/plugin SDK does not export Bun's `$` shape.
 * @param {string} ctx.directory - the session's project directory.
 * @returns {Promise<{ tool: { ai6_review: object } }>} the plugin's hooks.
 */
export const Ai6Plugin = async ({ $, directory }) => {
  return {
    tool: {
      ai6_review: tool({
        description:
          "Hand the just-completed work unit to the Claude (Opus) Reviewer for an " +
          "independent review against AGENTS.md. Call this after finishing a coherent " +
          "work unit (feature, fix, module, refactor). Returns the review; then act on " +
          "the final 'VERDICT: APPROVE|REVISE|BLOCK' line — address every finding on " +
          "REVISE/BLOCK and call again, up to 3 rounds.",
        args: {
          context: tool.schema
            .string()
            .describe("Concise description of what you did and why."),
          files: tool.schema
            .array(tool.schema.string())
            .describe("Paths of every file you created or modified in this work unit."),
        },
        // impure: checks bridge existence on disk and spawns a bash subprocess.
        /**
         * @param {{ context: string, files: string[] }} args - validated tool args.
         * @param {{ directory?: string }} context - OpenCode tool-execution context.
         */
        async execute(args, context) {
          // Prefer the per-call directory; fall back to the session directory
          // OpenCode booted the plugin with if the tool context omits it.
          const dir = context.directory || directory;

          if (!existsSync(BRIDGE)) {
            return (
              `ai6: reviewer bridge not found at ${BRIDGE}. ` +
              "Run the ai6 installer, or set AI6_BRIDGE to your ask-claude.sh path."
            );
          }

          // Backstop that only catches a wedged subprocess — the bridge's own
          // graceful "VERDICT: ERROR" normally wins first. Honors OpenCode's cancel
          // signal so a review can never freeze the whole session.
          //
          // Finite-number parse keeps an explicit 0 as 0 (|| would coerce it to the
          // default and diverge from the bridge, which treats 0 literally).
          const num = (v, d) => {
            // Treat empty string as "unset" to match bash `${VAR:-default}` semantics
            // (Number("") is 0, which would diverge from the bridge).
            if (v === undefined || v === "") return d;
            const n = Number(v);
            return Number.isFinite(n) ? n : d;
          };
          const perAttempt = num(process.env.AI6_TIMEOUT, 300);
          const attempts = num(process.env.AI6_RETRIES, 1) + 1;
          const retryDelay = num(process.env.AI6_RETRY_DELAY, 3);
          // The bridge's worst case is, per attempt, up to AI6_LOCK_TIMEOUT waiting
          // for the lock plus AI6_TIMEOUT running, plus the inter-attempt delays.
          // Mirror that here or the backstop could kill a legitimately-queued review.
          // Mirror the bridge's exact test (enabled only for the literal "1").
          const serialize = (process.env.AI6_SERIALIZE ?? "1") === "1";
          const lockWait = serialize ? num(process.env.AI6_LOCK_TIMEOUT, 900) : 0;
          const override = num(process.env.AI6_PLUGIN_TIMEOUT_MS, 0);
          const maxMs =
            override > 0
              ? override
              : ((perAttempt + lockWait) * attempts + retryDelay * (attempts - 1) + 60) * 1000;

          let timer;
          let abortHandler;
          const guard = new Promise((_, reject) => {
            timer = setTimeout(
              () => reject(new Error(`timed out after ${Math.round(maxMs / 1000)}s`)),
              maxMs,
            );
            abortHandler = () => reject(new Error("review cancelled"));
            context.abort?.addEventListener?.("abort", abortHandler, { once: true });
          });

          // Keep the ShellPromise (not just .text()) so we can kill the subprocess if
          // the backstop or a cancel wins — otherwise it keeps burning the reviewer
          // model and holding the serialization lock in the background.
          // Bun's $ escapes every interpolation; the array spreads into separate
          // quoted args. Runs in the session's project dir so git diff/AGENTS.md resolve.
          const proc = $`bash ${BRIDGE} ${args.context} ${args.files}`.cwd(dir);
          try {
            return await Promise.race([proc.text(), guard]);
          } catch (err) {
            // Best effort: the bridge's own `timeout` is the authoritative bound if
            // this signal doesn't reach the reviewer grandchild under bash.
            try { proc.kill?.(); } catch { /* best effort */ }
            const stdout = err?.stdout?.toString?.() ?? "";
            const stderr = err?.stderr?.toString?.() ?? "";
            return `ai6: review invocation failed (${err?.message ?? err}). The work was NOT reviewed — do not treat it as approved.\n${stdout}\n${stderr}`;
          } finally {
            clearTimeout(timer);
            // Avoid accumulating listeners on a long-lived session AbortSignal.
            if (abortHandler) context.abort?.removeEventListener?.("abort", abortHandler);
          }
        },
      }),
    },
  };
};
