# runpod-qwen-image-edit

[Qwen-Image-Edit-2511](https://huggingface.co/Qwen/Qwen-Image-Edit-2511) を RunPod Serverless で動かすワーカーです。[runpod-workers/worker-comfyui](https://github.com/runpod-workers/worker-comfyui) にモデルを焼き込んだだけの薄い派生で、handler も entrypoint も持ちません。

## なぜ作ったか

RunPod Hub には既に Qwen-Image-Edit のワーカーがいくつかありますが、試した範囲では **出力サイズを指定できません** でした。API に `width` / `height` を渡しても黙って捨てられ、出力は正方形に固定されます。

原因はワークフローがイメージ内に固定されていることでした。あるワーカーの handler にはこう書かれています。

```python
_NODE_WIDTH  = "128"   # 現在のワークフローには無い(選択適用)
if _NODE_WIDTH in prompt and "width" in job_input:   # ← 条件が成立しない
    prompt[_NODE_WIDTH]["inputs"]["value"] = job_input["width"]
```

サイズを決めていたのは `ImageScaleToTotalPixels` (合計 1 メガピクセルへ正規化) で、出力の縦横比は入力画像の比率で決まっていました。16:9 が要る用途では使えません。

このリポジトリは **ワークフローをイメージに持たせず、API から毎回渡す** 構成にしてこれを避けています。

## 構成

| | |
| --- | --- |
| ベース | `runpod/worker-comfyui:5.8.6-base` |
| 拡散モデル | `qwen_image_edit_2511_fp8mixed` (19.1 GB) |
| テキストエンコーダ | `qwen_2.5_vl_7b_fp8_scaled` (8.7 GB) |
| VAE | `qwen_image_vae` (0.24 GB) |
| LoRA | `Qwen-Image-Edit-2511-Lightning-4steps` (0.79 GB) |
| モデル合計 | **28.9 GB** |
| GPU | `ADA_24` / `ADA_32_PRO` (24GB / 32GB) |
| CUDA | 12.8 |

bf16 のフル版は 53.7 GB あり 80GB クラスの GPU が要りますが、**FP8 mixed なら 24GB クラスに載ります**。GPU 単価が変わるため、コストに直結します。

モデルはネットワークボリュームではなく **イメージに焼き込んでいます**。ボリュームは存在するだけで容量課金 ($0.07/GB/月) が続き、コールドスタートも読み出しの分だけ遅くなるためです。

## 使い方

ワークフローは [ComfyUI の API 形式](https://github.com/runpod-workers/worker-comfyui#getting-the-workflow-json) で `input.workflow` に渡します。入力画像は `input.images` に base64 で渡し、ワークフロー内の `LoadImage` ノードから `name` で参照します。

```jsonc
{
  "input": {
    "workflow": { /* ComfyUI API 形式のワークフロー */ },
    "images": [{ "name": "ref.png", "image": "<base64>" }]
  }
}
```

出力サイズはワークフロー側で決めます。`ImageScaleToTotalPixels` ではなく `ImageScale` を使えば、幅と高さを直接指定できます。

## ライセンス

AGPL-3.0。ベースにした [worker-comfyui](https://github.com/runpod-workers/worker-comfyui) が AGPL-3.0 であり、その先の [ComfyUI](https://github.com/comfyanonymous/ComfyUI) も GPL 系のため、派生物として継承しています。

モデルの重みはそれぞれの配布元のライセンスに従います。
