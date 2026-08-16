# runpod-qwen-image-edit

A RunPod Serverless worker for [Qwen-Image-Edit-2511](https://huggingface.co/Qwen/Qwen-Image-Edit-2511). It is a thin derivative of [runpod-workers/worker-comfyui](https://github.com/runpod-workers/worker-comfyui) that bakes the models into the image — nothing more.

## Why this exists

The RunPod Hub already has a few Qwen-Image-Edit workers, but the ones I tried **cannot control the output dimensions**. Passing `width` / `height` to the API has no effect: the values are silently dropped and the output stays square.

The cause is that the workflow is frozen inside the image. One worker's handler says it outright:

```python
_NODE_WIDTH  = "128"   # not present in the current workflow (applied only if it exists)
if _NODE_WIDTH in prompt and "width" in job_input:   # ← never true
    prompt[_NODE_WIDTH]["inputs"]["value"] = job_input["width"]
```

What actually decided the size was `ImageScaleToTotalPixels` (normalize to 1 megapixel total), so the aspect ratio simply followed the input image. That is unusable when you need 16:9.

This repository avoids the problem by **keeping no workflow inside the image and passing one with every request** instead.

## What's inside

| | |
| --- | --- |
| Base | `runpod/worker-comfyui:5.8.6-base` |
| Diffusion model | `qwen_image_edit_2511_fp8mixed` (19.1 GB) |
| Text encoder | `qwen_2.5_vl_7b_fp8_scaled` (8.7 GB) |
| VAE | `qwen_image_vae` (0.24 GB) |
| LoRA | `Qwen-Image-Edit-2511-Lightning-4steps` (0.79 GB) |
| Models total | **28.9 GB** |
| GPU | `ADA_24` / `ADA_32_PRO` (24 GB / 32 GB) |
| CUDA | 12.8 |

The bf16 full weights are 53.7 GB and need an 80 GB-class GPU, but **the FP8 mixed build fits on a 24 GB card**. That difference lands directly on the hourly rate, so it matters for cost.

Models are baked into the image rather than mounted from a network volume. A volume keeps billing you for capacity ($0.07/GB/month) as long as it exists, and reading weights from it makes cold starts slower.

## Usage

Pass a workflow in [ComfyUI API format](https://github.com/runpod-workers/worker-comfyui#getting-the-workflow-json) as `input.workflow`. Input images go in `input.images` as base64 and are referenced from a `LoadImage` node by `name`.

```jsonc
{
  "input": {
    "workflow": { /* ComfyUI API format */ },
    "images": [{ "name": "reference.png", "image": "<base64>" }]
  }
}
```

### Workflow

`workflow/qwen-image-edit-16x9.json` is a ready-to-use 16:9 example. Substitute these before sending it:

| Node | What to replace |
| --- | --- |
| `11` `ImageScale` | `width` / `height` (output resolution) |
| `21` `TextEncodeQwenImageEditPlus` | `prompt` (positive) |
| `30` `KSampler` | `seed` / `steps` |
| `10` `LoadImage` | `image` (the `name` you passed in `input.images`) |

It defaults to 1360x768 (~1.04 MP, effectively 16:9). Qwen-Image is trained around one megapixel, so pushing the resolution much higher costs quality. Resize to your final dimensions on the caller side.

The one node that matters is `ImageScale`. Its output feeds three places — the latent source and both the positive and negative image conditioning — so it, not the request payload, is what fixes the output aspect ratio.

## About the handler

`handler.py` is taken verbatim from [worker-comfyui](https://github.com/runpod-workers/worker-comfyui) (both are AGPL-3.0). The base image ships the same file, but the Hub requires a `handler.py` in the repository itself, so it is committed here and `COPY`-ed explicitly.

## License

AGPL-3.0, inherited from [worker-comfyui](https://github.com/runpod-workers/worker-comfyui) and, further upstream, [ComfyUI](https://github.com/comfyanonymous/ComfyUI).

Model weights are governed by their respective upstream licenses.
