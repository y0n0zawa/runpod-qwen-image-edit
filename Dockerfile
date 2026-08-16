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
FROM runpod/worker-comfyui:5.8.6-base

# 拡散モデル本体。FP8 mixed の量子化版を使う (bf16 のフル版は 53.7 GB あり
# 80GB クラスの GPU が要る。FP8 なら 24GB クラスに載る)。
RUN comfy model download \
      --url https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors \
      --relative-path models/diffusion_models \
      --filename qwen_image_edit_2511_fp8mixed.safetensors

# テキストエンコーダ (Qwen2.5-VL 7B)
RUN comfy model download \
      --url https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors \
      --relative-path models/text_encoders \
      --filename qwen_2.5_vl_7b_fp8_scaled.safetensors

RUN comfy model download \
      --url https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors \
      --relative-path models/vae \
      --filename qwen_image_vae.safetensors

# 4 ステップで生成するための Lightning LoRA。ステップ数を落とすぶん
# 生成時間と GPU 課金が縮む。使うかどうかはワークフロー側で決められる。
RUN comfy model download \
      --url https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors \
      --relative-path models/loras \
      --filename Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors

# handler はベースイメージにも同じものが入っているが、Hub の掲載要件が
# リポジトリ内の handler.py を求めるため、明示的に置いて上書きする。
# 中身は worker-comfyui のものをそのまま使う (どちらも AGPL-3.0)。
COPY handler.py /handler.py
