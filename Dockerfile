# syntax=docker/dockerfile:1
#
# Qwen-Image-Edit-2511 を RunPod Serverless で動かすためのワーカー。
#
# 公式の worker-comfyui にモデルを焼き込むだけの薄い派生で、handler も
# entrypoint も持たない。公式側の実装がそのまま動く。
#
# ワークフローは API の input.workflow で毎回渡す設計にしてある。出力サイズ・
# ステップ数・LoRA の差し替えを、イメージの再ビルドなしで変えられる。
# 既成ワーカーの多くはワークフローをイメージ内に固定しており、出力が正方形から
# 変えられない (指定した width/height が黙って捨てられる) 問題があった。
#
# モデルはネットワークボリュームではなくイメージに焼き込む。ボリューム経由は
# 存在するだけで容量課金が続くうえ、コールドスタートも読み出しの分だけ遅い。
FROM runpod/worker-comfyui:5.8.6-base AS base

# モデルはステージを分けて取得する。BuildKit は依存関係のないステージを
# 並列に実行するため、逐次で 22 分かかっていたダウンロードが、最も大きい
# 1 本ぶんの時間に近づく。RunPod Hub のビルドは 30 分で打ち切られ、
# イメージの書き出しと転送だけで 8 分を使うので、ここを詰めないと
# 完走しない (逐次版は書き出しの途中で時間切れになった)。
#
# 取得先は base に必ず入っている wget で固定する。comfy model download は
# 配置先が comfy-cli の既定ワークスペース設定に依存するため、
# 絶対パスへ直接落として最終ステージで所定の位置に COPY する。

# 拡散モデル本体。FP8 mixed の量子化版を使う (bf16 のフル版は 53.7GB あり
# 80GB クラスの GPU が要る。FP8 なら 24GB クラスに載る)。
FROM base AS diffusion
RUN mkdir -p /models/diffusion_models \
 && wget -q --tries=3 -O /models/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors \
      https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors

# テキストエンコーダ (Qwen2.5-VL 7B)
FROM base AS text-encoder
RUN mkdir -p /models/text_encoders \
 && wget -q --tries=3 -O /models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors \
      https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors

FROM base AS vae
RUN mkdir -p /models/vae \
 && wget -q --tries=3 -O /models/vae/qwen_image_vae.safetensors \
      https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors

# 4 ステップで生成するための Lightning LoRA。ステップ数を落とすぶん
# 生成時間と GPU 課金が縮む。使うかどうかはワークフロー側で決められる。
FROM base AS lora
RUN mkdir -p /models/loras \
 && wget -q --tries=3 -O /models/loras/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors \
      https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors

FROM base

# モデルごとに COPY を分けてレイヤーを 4 つに保つ。1 つにまとめると
# 29GB 弱の単一レイヤーになり、書き出しと転送がさらに遅くなる。
COPY --from=diffusion /models/diffusion_models/ /comfyui/models/diffusion_models/
COPY --from=text-encoder /models/text_encoders/ /comfyui/models/text_encoders/
COPY --from=vae /models/vae/ /comfyui/models/vae/
COPY --from=lora /models/loras/ /comfyui/models/loras/

# handler はベースイメージにも同じものが入っているが、Hub の掲載要件が
# リポジトリ内の handler.py を求めるため、明示的に置いて上書きする。
# 中身は worker-comfyui のものをそのまま使う (どちらも AGPL-3.0)。
COPY handler.py /handler.py
