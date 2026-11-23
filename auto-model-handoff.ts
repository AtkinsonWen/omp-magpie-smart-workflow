import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { homedir } from "node:os";
import { join } from "node:path";

const ROUTER = "magpie/group/smart-workflow";
const ROUTING_GROUP = ROUTER.slice("magpie/".length);
const TOOL = "handoff_to_implementation";
const ENTRY = "atkin.auto-model-handoff";
const ROUTING_DIR = join(homedir(), ".config", "magpie", "routing");
const ROUTING_TAIL_BYTES = 1024 * 1024;
const ROUTING_FLUSH_GRACE_MS = 100;
const PLANNERS: Record<string, true> = {
	"muze/gpt-6.2-sol": true,
	"micu/claude-opus-5-5": true,
	"4router/claude-opus-5-5": true,
};
const GUIDANCE = `
## Automatic planning handoff
For a complex workspace change, investigate before editing. At the point where you would start implementing, choose one path:
- The approach is known, remaining edits are bounded and low risk, and the verification is concrete: call ${TOOL} alone with action "handoff" before editing. Pass the exact files, decisions, constraints, and checks. The next model will implement; do not do the work yourself first.
- Implementation still needs substantial judgment (unresolved concurrency, important invariants, security boundaries, or risky migration): call ${TOOL} alone with action "keep" and explain why. Continue on the routing group; this does not pin a backend.
Simple tasks and read-only work never need this tool. If it is unavailable or rejected, continue without automatic handoff under the existing approval policy. Do not change any approval or safety rules.`;

function selector(model: { provider: string; id: string } | undefined) {
	return model ? `${model.provider}/${model.id}` : undefined;
}

function routingDate(time: number) {
	const date = new Date(time);
	return new Date(time - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
}

async function isStrongPlanner(session: string, responseId: string, timestamp: number) {
	const today = routingDate(Date.now());
	const started = routingDate(timestamp);
	const responseKey = `"responseId":${JSON.stringify(responseId)}`;
	for (const date of today === started ? [today] : [today, started]) {
		const file = Bun.file(join(ROUTING_DIR, `${date}.jsonl`));
		let tail: string;
		try {
			tail = await file.slice(Math.max(0, file.size - ROUTING_TAIL_BYTES)).text();
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") continue;
			throw error;
		}
		for (const line of tail.trimEnd().split(/\r?\n/).reverse()) {
			if (!line.startsWith("{") || !line.endsWith("}") || !line.includes(responseKey)) continue;
			const route = JSON.parse(line);
			if (route.session !== session || route.model !== ROUTING_GROUP || route.responseId !== responseId || !route.done) continue;
			const served = route.tries?.findLast((attempt: { status: number; served?: string }) => attempt.status === 200 && attempt.served);
			return !!(route.status === 200 && served && Object.hasOwn(PLANNERS, `${served.id}/${served.served}`));
		}
	}
}

function nativeWorkflowSelected(ctx: ExtensionContext) {
	const plan = ctx.sessionModes?.getState().plan;
	return (plan !== undefined && plan !== "inactive") || process.argv.some(arg =>
		arg === "--plan-yolo" || arg === "--prewalk" || arg === "--prewalk-into" || arg.startsWith("--prewalk-into="));
}

export default function autoModelHandoff(pi: ExtensionAPI) {
	let running = false;
	let blockedWrites: string[] = [];
	let permittedCall: string | undefined;
	let decision: "pending" | "nudged" | "keep" = "pending";

	const resetTask = () => {
		running = false;
		permittedCall = undefined;
		decision = "pending";
		blockedWrites = [];
	};
	pi.on("agent_start", (_event, ctx) => { if (ctx.agent.kind === "main") running = true; });
	pi.on("agent_end", (event, ctx) => { if (ctx.agent.kind === "main" && !event.willContinue) resetTask(); });
	pi.on("session_switch", resetTask);
	pi.on("session_clear", resetTask);

	pi.on("before_agent_start", async (event, ctx) => {
		if (ctx.agent.kind !== "main" || event.reason !== "prompt" || nativeWorkflowSelected(ctx)) return;
		if (!running) resetTask();
		const current = selector(ctx.models.current());
		// Steering and queued follow-ups share this hook; don't restore during either.
		if (!running && current && current !== ROUTER) {
			const lastChoice = ctx.sessionManager.getBranch().findLast(entry =>
				(entry.type === "custom" && entry.customType === ENTRY) ||
				entry.type === "model_change" || entry.type === "thinking_level_change" || entry.type === "mode_change");
			if (lastChoice?.type === "custom" && lastChoice.data === current) {
				const router = ctx.models.resolve(ROUTER);
				if (!router || !(await pi.setModel(router))) {
					throw new Error("Automatic handoff: could not restore smart-workflow.");
				}
			}
		}
		if (selector(ctx.models.current()) === ROUTER && decision !== "keep" && pi.getActiveTools().includes(TOOL)) {
			return { systemPrompt: [...event.systemPrompt, GUIDANCE] };
		}
	});

	pi.on("assistant_message", async ({ message }, ctx) => {
		if (ctx.agent.kind !== "main") return;
		permittedCall = undefined;
		blockedWrites = [];
		if (selector({ provider: message.provider, id: message.model }) !== ROUTER || !message.responseId ||
			selector(ctx.models.current()) !== ROUTER || nativeWorkflowSelected(ctx) || decision === "keep" ||
			!pi.getActiveTools().includes(TOOL)) return;
		const calls = message.content.filter(block => block.type === "toolCall");
		const handoff = calls.length === 1 && calls[0]?.name === TOOL ? calls[0] : undefined;
		const writes = decision === "pending" ? calls.filter(call => call.name === "edit" || call.name === "write" || call.name === "apply_patch") : [];
		if (!handoff && writes.length === 0) return;
		const session = ctx.sessionManager.getSessionId();
		let planner = await isStrongPlanner(session, message.responseId, message.timestamp);
		// The stream can finish before Magpie has appended its final routing record.
		if (planner === undefined) {
			await Bun.sleep(ROUTING_FLUSH_GRACE_MS);
			planner = await isStrongPlanner(session, message.responseId, message.timestamp);
		}
		if (!planner) return;
		if (handoff) permittedCall = handoff.id;
		if (writes.length > 0) {
			// Decide for the whole assistant batch, then let later batches proceed.
			decision = "nudged";
			blockedWrites = writes.map(call => call.id);
		}
	});

	pi.on("tool_call", (event, ctx) => {
		if (ctx.agent.kind !== "main" || !blockedWrites.includes(event.toolCallId)) return;
		return { block: true, reason: `Before editing, call ${TOOL} alone. Use action "handoff" with the concrete plan if the rest is bounded and low risk; use "keep" with the reason if it still requires strong judgment.` };
	});

	pi.registerTool({
		name: TOOL,
		label: "交接给执行模型",
		description: "Select the implementation model on smart-workflow after investigating a complex workspace change. Use action handoff with a concrete plan when remaining work is bounded; use keep to stay on the routing group when difficult judgment remains. Call alone, before editing.",
		loadMode: "essential",
		approval: "write",
		parameters: pi.zod.object({ action: pi.zod.enum(["handoff", "keep"]), plan: pi.zod.string().trim().min(1).max(6000) }),
		async execute(id, { action, plan }, signal, _onUpdate, ctx) {
			if (ctx.agent.kind !== "main" || nativeWorkflowSelected(ctx) || selector(ctx.models.current()) !== ROUTER || permittedCall !== id) {
				throw new Error("Handoff is only available as a standalone call by an eligible planner on smart-workflow.");
			}
			permittedCall = undefined;
			if (action === "keep") {
				decision = "keep";
				return { content: [{ type: "text", text: "No handoff for this task. Continue on smart-workflow with the existing approval policy." }] };
			}
			const target = ctx.models.resolve("@smol");
			if (!target || selector(target) === ROUTER) throw new Error("Handoff requires a separate @smol model.");
			signal?.throwIfAborted();
			if (!(await pi.setModel(target))) throw new Error("Handoff could not switch to @smol.");
			pi.appendEntry(ENTRY, selector(target));
			return { content: [{ type: "text", text: `Switched to ${selector(target)}. Execute this plan and verify it without changing any approval policy:\n${plan}` }] };
		},
	});
}
