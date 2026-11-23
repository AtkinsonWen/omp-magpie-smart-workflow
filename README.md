# OMP + Magpie Smart Workflow

**Route by task difficulty, then hand bounded implementation to a smaller model without starting a new conversation.** Magpie chooses the model for the turn; the OMP extension handles the optional switch after planning.

## 中文介绍：工作流架构

这套工作流不要求用户事先选模型，也不把每个复杂任务都转交给更轻的模型。**Magpie 决定这一轮由谁开始，OMP 决定规划完成后要不要换模型继续。** 交接留在同一会话，不用重新解释问题或复制上下文。

```mermaid
flowchart TB
    A[用户向 OMP 提交新任务] --> R{Magpie 路由组判断任务类型}
    R -->|明确小任务| F[DeepSeek Flash 优先]
    R -->|常规任务或未匹配| T[Terra 优先]
    R -->|复杂任务| S[Sol 优先，Opus 后备]
    F --> D[完成本轮]
    T --> D
    S --> P[强模型调查、定位并制定方案]
    P --> H{OMP 核对实际模型和交接决定}
    H -->|方案明确、实施低风险且可验证| I[切换到 @smol，按方案实施并验证]
    H -->|仍需判断或无法核对实际模型| K[留在路由组，不自动交接]
    I --> D
    K --> D
```

**例子：修复任务调度器偶发的重复执行。** Sol 先追踪重试和并发路径。如果已经定位到同一个任务能被两名 worker 同时认领，并明确了修复点、要保持的不变量和回归用例，就可以把这些实施细节交给 `@smol`（示例配置里是 Terra）。如果还不能判断锁和事务的边界，就选择 `keep`，留在路由组继续调查。

- **路由是优先顺序，不是固定分配。** 模型失败时 Magpie 可以选后备；OMP 扩展按当前会话与响应 ID 核对已完成的路由记录，不凭模型选择器里显示的组名判断。
- **想让下一条消息重新路由，等当前任务结束再发。** 排队的 follow-up 可能沿用 `@smol`；手动切换模型、思考级别或模式后，扩展不会擅自切回。
- **交接不改变工具审批。** 它不是权限或写入防护；使用原生 Prewalk 时请关闭本扩展，避免两套机制同时接管。

想复现这套配置：先按 [Magpie 路由示例](examples/magpie-routing.md) 建组，再合并 [OMP 模型角色配置](examples/omp-config.yml)，安装扩展并重启 OMP。模型可以替换成你自己有权限使用的版本，细节见下方 [Install](#install)。

## Routing reference

| Task | Preferred model in this example |
| --- | --- |
| Short factual question, one specified command, or one mechanical edit | DeepSeek Flash at low effort |
| Routine work or no intent match | GPT-6.1 Terra |
| Architecture, migration, unclear root cause, or difficult invariants | GPT-6.2 Sol; Claude Opus as fallback |
| Compaction | Terra, then Flash if needed |
| Bounded implementation after planning | The OMP `@smol` role, Terra in this example |

On a complex change, the planner investigates first. It can hand off a concrete plan covering files, decisions, constraints, and verification, or decide to keep working on the routing group when implementation still needs judgment. The extension verifies the actual planner against Magpie's completed routing record for that response and session. It prompts once at the first eligible `edit`, `write`, or `apply_patch` batch if the planner has not decided yet. An explicit `keep` closes the handoff for that task. A new prompt submitted after the task settles restores the routing group unless the user has since selected a model, thinking level, or mode.

## Install

1. Use [OMP](https://github.com/can1357/oh-my-pi) and a **local** Magpie gateway with providers you can access. The reference environment is Windows, OMP `19.1.0`, and Magpie `0.1.4573`. Other versions and OSes have not been verified. You do not need the author's provider accounts; substitute your own exact model IDs.
2. Follow [the Magpie routing example](examples/magpie-routing.md). Make `group/smart-workflow` available to OMP in Magpie's Agents view or with `magpie omp group/smart-workflow`. If OMP is already connected to Magpie, you can keep its provider setup.
3. Merge the [`modelRoles` example](examples/omp-config.yml) into your active OMP `config.yml` (default `~/.omp/agent/config.yml`). Do not replace the whole config. Point `@smol` at a tool-capable execution model, not the routing group. If you use different planners, edit `PLANNERS` in the extension to match their **served** provider/model names.
4. Copy `auto-model-handoff.ts` into the active agent directory's `extensions/` and restart OMP. Check `/extensions` for `auto-model-handoff`. The extension expects routing logs at `~/.config/magpie/routing`. If you moved Magpie's data, set `ROUTING_DIR` in the extension to the actual log directory.

## Verify

- Run `magpie group smart-workflow` and confirm the member order, classifier, and rule priorities. Start OMP without a model override. Ask a short factual question, then a complex workspace question. The OMP model picker may show only `magpie/group/smart-workflow`; use the matched completed Magpie routing records to see which model actually served each request. Intent classification and failover mean the preferred model is not guaranteed.
- In a disposable workspace, ask for a change that needs investigation but has bounded edits once the design is known. Check for a successful `handoff_to_implementation` result, the switch to `@smol`, and the real file change and verification. Wait for completion, send a fresh prompt, and check that the routing group is active again.

## Boundaries

- This is model selection, **not a write guard or approval system**. It gives one planning reminder for the named file tools. Shell, nested tools and other mutation paths are not intercepted. OMP's existing approvals still apply.
- OMP 19.1.0 does not expose the dequeue type to `before_agent_start`. In-run steering deliberately keeps the current task, and a queued follow-up may also continue on `@smol`. For guaranteed fresh routing, wait for the task to settle before sending the next prompt.
- Use native Plan Mode or Prewalk **instead of** this extension when you want those workflows. The extension defers to visible Plan Mode and explicit startup `--plan-yolo` / `--prewalk` flags; it cannot observe all ways Prewalk is armed after startup. Disable the extension when using automatic or manually armed Prewalk with this group.
- If the Magpie route record is unavailable or cannot be matched, the extension does not guess the backend or switch models. Routing without automatic handoff still works.
- To disable handoff, turn off `auto-model-handoff` in `/extensions`. To stop using this workflow entirely, also select your previous default model. Leave other OMP settings and credentials untouched.

The repository contains only the extension and example configuration. It does not include provider credentials, routing logs, or session history.
