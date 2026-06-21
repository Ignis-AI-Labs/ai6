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

          try {
            // Bun's $ escapes every interpolation; the array spreads into separate
            // quoted args. Runs in the session's project directory so the bridge's
            // git diff and AGENTS.md resolve against the right repo.
            return await $`bash ${BRIDGE} ${args.context} ${args.files}`
              .cwd(dir)
              .text();
          } catch (err) {
            const stdout = err?.stdout?.toString?.() ?? "";
            const stderr = err?.stderr?.toString?.() ?? "";
            return `ai6: review invocation failed.\n${stdout}\n${stderr}\n${err?.message ?? err}`;
          }
        },
      }),
    },
  };
};
