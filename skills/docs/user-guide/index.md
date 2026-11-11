```{eval-rst}
.. meta::
   :description: Business-objective prompts that turn a plain-language manufacturing
      quality goal into a running Intel Edge AI application.
```

# Manufacturing Application Builder

<!--hide_directive
<div class="component_card_widget">
  <a class="icon_github" href="https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/.github/skills">
     GitHub
  </a>
  <a class="icon_document" href="https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/README.md">
     Readme
  </a>
</div>
hide_directive-->

The Manufacturing AI Suite **Manufacturing Application Builder** is a collection of
reusable, business-objective prompts. Each prompt turns a plain-language goal into a running
Intel® Edge AI application. An example goal is "I want to be alerted before a pump fails."

Each prompt states only a business outcome. It does not name a framework, model, precision, or
device. The prompt hands off to the `manufacturing-ai-app-builder` orchestrator skill. The
orchestrator asks a few business questions and selects the right delegate skill. It then proposes
a plan. After you confirm the plan, it builds the deliverable on Intel hardware.

---

## How prompt-driven application development works

A prompt is intentionally minimal. It describes *what you want to achieve* and delegates every
technical decision to the orchestrator skill.

1. **State a business objective.** Select the prompt that matches your outcome, for example
   "predict a pump failure" or "catch defective welds". Alternatively, describe your goal in your
   own words.
2. **The orchestrator takes over.** The
   [`manufacturing-ai-app-builder`](https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/.github/skills/manufacturing-ai-app-builder)
   skill runs a short business Q&A. It asks for:
   - the outcome you want
   - what feeds the decision: a camera, a sensor, or both
   - your inputs, such as an RTSP camera, an OPC-UA server, an MQTT broker, or sample data
   - where the application runs and on which Intel hardware
   - how you want to be notified, for example a dashboard, MQTT alerts, or OpenMES issues
   - where to build the application on your host

   If your decision combines camera and sensor signals, the orchestrator also asks which
   deployment you want. The options are `multimodal` (fused alert only), `vllm` (adds
   written explanations from a vision-language model), or `agentic` (adds agent-coordinated
   analysis). The last two options need extra models and an Intel GPU, so the orchestrator asks
   you to opt in.
3. **Skill discovery.** From your answers, the orchestrator selects the delegate skill:

   | What feeds the decision | Delegate skill |
   | --- | --- |
   | A sensor stream only | `manufacturing-app-recipe` in `ts` mode |
   | A camera and sensors, combined into one verdict | `manufacturing-app-recipe` in `multimodal`, `vllm`, or `agentic` mode |
   | A camera only | `metro-ai-app-recipe`, which the orchestrator installs on demand |

4. **Plan and confirm.** The orchestrator presents the deliverable, the skills that build it,
   the technology it inferred, and the requirements. It then waits for your approval. Nothing is
   created before you confirm.
5. **Build by delegation.** After you approve, the orchestrator builds the deliverable by
   delegating to the chosen skills, and then verifies the result against each delegate's
   completion criteria.

---

## Before you begin

The orchestrator is a skill that runs in an AI coding agent. You need:

- An AI agent tool that supports skills, such as GitHub Copilot in Visual Studio Code.
- Node.js 22.20 or later and internet access to install skills with `npx`. After you approve
  the plan, the orchestrator installs any missing delegate skill, including
  `manufacturing-app-recipe`, with `npx skills`. You don't need to clone this repository.
- Docker with Docker Compose v2 on the host where the application runs. The orchestrator lists
  any further requirements, such as free ports and Intel GPU access, in the plan.

---

## Writing your own prompt

You don't need to learn any special format. Describe the outcome you want in plain language and
hand off to the `manufacturing-ai-app-builder` skill. Copy the following template into your AI
agent tool, replace the objective with your own, and run it:

```text
I want to <state the business outcome in one or two sentences>.

Use the manufacturing-ai-app-builder skill to guide this process. Install and
invoke it:

npx skills@1.7.4 add https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/.github/skills/manufacturing-ai-app-builder
```

Keep the prompt business-only. Describe what you want to achieve, not which model, framework,
precision, or device to use. The orchestrator infers those details for you.

---

## Manufacturing Prompt Library

Ready-to-use, business-objective prompts that you can copy and paste into your AI agent tool.
Each tile is built from a prompt file in the `skills/prompts/` directory. Select a tile to view the
full prompt, and then copy it.

```{eval-rst}
.. raw:: html

   <style>

.. raw:: html
   :file: ../prompt-library-files/prompt-catalog.css

.. raw:: html

   </style>
   <div id="prompt-catalog" class="prompt-catalog"
        data-prompts="pump-failure-prediction,weld-defect-detection,pcb-solder-inspection,production-line-early-warning">
     <p class="prompt-catalog-loading">Loading prompts…</p>
   </div>
   <script type="text/plain" data-prompt-slug="pump-failure-prediction">

.. raw:: html
   :file: ../../prompts/pump-failure-prediction.yaml

.. raw:: html

   </script>
   <script type="text/plain" data-prompt-slug="weld-defect-detection">

.. raw:: html
   :file: ../../prompts/weld-defect-detection.yaml

.. raw:: html

   </script>
   <script type="text/plain" data-prompt-slug="pcb-solder-inspection">

.. raw:: html
   :file: ../../prompts/pcb-solder-inspection.yaml

.. raw:: html

   </script>
   <script type="text/plain" data-prompt-slug="production-line-early-warning">

.. raw:: html
   :file: ../../prompts/production-line-early-warning.yaml

.. raw:: html

   </script>
   <script>

.. raw:: html
   :file: ../prompt-library-files/prompt-catalog.js

.. raw:: html

   </script>
```

---

## Available skills

The suite ships these skills. The orchestrator uses the first two. You can also invoke any skill directly.

| Skill | Use it to |
| --- | --- |
| [`manufacturing-ai-app-builder`](https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/.github/skills/manufacturing-ai-app-builder) | Turn a business objective into a plan and delegate the build. |
| [`manufacturing-app-recipe`](https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/.github/skills/manufacturing-app-recipe) | Stand up a vision, time-series, multimodal, VLM, or agentic stack with Docker Compose. |
| [`multimodal-deploy`](https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/industrial-edge-insights-multimodal/.github/skills/multimodal-deploy) | Build, deploy, and test the Multimodal Weld Defect Detection sample application. |
| [`time-series-deploy`](https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/industrial-edge-insights-time-series/.github/skills/time-series-deploy) | Build, deploy, and test the Time Series sample applications, such as wind-turbine anomaly detection. |

To install a skill, pass the URL of its folder to `npx skills`:

```bash
npx skills@1.7.4 add <skill-folder-url>
```
