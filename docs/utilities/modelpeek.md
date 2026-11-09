# ModelPeek

**Question:** Which local LLMs are loaded, and how much memory and GPU are they using?

## What it shows
One card per runner that is running, with the models it has loaded and what its processes use:

| Runner | Recognised by | Loaded models from |
|---|---|---|
| **Ollama** | `ollama` (`serve`, `runner`), `ollama_llama_server`, Ollama.app | `GET http://127.0.0.1:11434/api/ps`: name, size, how much is on the GPU ("100% GPU", "48% GPU / 52% CPU"), context length, quantization, when it unloads |
| **LM Studio** | processes inside `LM Studio.app`, `~/.lmstudio` engines, `lms` | `GET http://127.0.0.1:1234/api/v0/models` (models with `state: loaded`), when LM Studio's local server is on |
| **MLX** | Python running `mlx_lm` / `mlx_vlm` (`-m mlx_lm.server`…) | the `--model` argument |
| **llama.cpp** | `llama-server`, `llama-cli`, `llama-run` and the other llama.cpp tools | the `-m` / `--model` / `--hf-repo` argument |
| **llamafile** | `*.llamafile`, `llamafile` | the `-m` argument, when given |

For each runner: total memory footprint (libproc), CPU (sampled, percent of one core) and GPU share (from the GPU's
per-process time, as in GPUPeek), and its processes with their roles.

## How it works
- `ps -axo pid=,ppid=,comm=` lists executables only. Command lines are then read (`ps -ww -o pid=,args= -p …`) only for
  processes that could be runners by their executable (Ollama, LM Studio, llama.cpp tools, llamafile, and Python for MLX).
  Of a runner's command line only the model argument is kept; the rest (which can contain API keys, as
  `llama-server --api-key` does) is never stored, shown or logged.
- Ollama's and LM Studio's APIs are asked only while their processes are running, only on `127.0.0.1`, with a 2-second
  timeout and no proxy. Nothing leaves the Mac.
- Reads every *refresh interval* (at least 3 s) only while the screen is open.

## Fact versus inference
Model names and sizes from an API are the runner's own. A model name from a command line is what the runner was started
with (a path is shortened to its file name). Which process belongs to which runner is inferred from names and paths. A
runner with a different port (OLLAMA_HOST, a non-default LM Studio port) shows "did not answer".

## Verified against
**Not yet verified on a Mac.** Fixtures in `Tests/ModelPeekKitTests/Fixtures/` were written from the runners' documented
API output. `scripts/capture-fixtures.sh` captures the real runner process names and API answers.
