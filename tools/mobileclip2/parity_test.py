#!/usr/bin/env python3
"""Parity test: PyTorch reference MobileCLIP2-S0 vs the converted Core ML models.

Feeds identical fixed inputs through both stacks and asserts cosine similarity
>= 0.99 per pair. Also runs a small text->image retrieval sanity check.

Usage:
  python parity_test.py --checkpoint mobileclip2_s0.pt --models-dir out
"""

import argparse
import io
import urllib.request
from pathlib import Path

import coremltools as ct
import numpy as np
import open_clip
import torch
import torch.nn.functional as F
from PIL import Image
from timm.utils.model import reparameterize_model

MODEL_NAME = "MobileCLIP2-S0"
IMAGE_SIZE = 256
CONTEXT_LENGTH = 77
PARITY_THRESHOLD = 0.99

TEXTS = [
    "a photo of a coffee receipt",
    "screenshot of a concert ticket",
    "a cat sleeping on a windowsill",
    "sunset over the ocean",
    "a hand-written grocery list",
    "invoice total $22.50 North Star Market",
    "map of the Kyoto subway",
    "a birthday party invitation",
]

# Small stable test photos; retrieval sanity is skipped if fetch fails.
RETRIEVAL_IMAGES = {
    "a cat": "https://raw.githubusercontent.com/EliSchwartz/imagenet-sample-images/master/n02123045_tabby.JPEG",
    "a dog": "https://raw.githubusercontent.com/pytorch/hub/master/images/dog.jpg",
    "a beach by the ocean": "https://raw.githubusercontent.com/EliSchwartz/imagenet-sample-images/master/n09428293_seashore.JPEG",
    "a pizza": "https://raw.githubusercontent.com/EliSchwartz/imagenet-sample-images/master/n07873807_pizza.JPEG",
}


def fixed_images() -> list[np.ndarray]:
    """Deterministic synthetic RGB images, uint8 HWC."""
    rng = np.random.default_rng(7)
    images = [rng.integers(0, 256, (IMAGE_SIZE, IMAGE_SIZE, 3), dtype=np.uint8) for _ in range(4)]
    ramp = np.linspace(0, 255, IMAGE_SIZE, dtype=np.uint8)
    images.append(np.stack([np.tile(ramp, (IMAGE_SIZE, 1))] * 3, axis=-1))
    checker = ((np.indices((IMAGE_SIZE, IMAGE_SIZE)).sum(axis=0) // 32) % 2 * 255).astype(np.uint8)
    images.append(np.stack([checker] * 3, axis=-1))
    solid = np.zeros((IMAGE_SIZE, IMAGE_SIZE, 3), dtype=np.uint8)
    solid[..., 0] = 200
    solid[..., 2] = 90
    images.append(solid)
    return images


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    a = a.flatten().astype(np.float64)
    b = b.flatten().astype(np.float64)
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--models-dir", default="out")
    args = parser.parse_args()
    models_dir = Path(args.models_dir)

    model, _, _ = open_clip.create_model_and_transforms(MODEL_NAME, pretrained=args.checkpoint)
    model.eval()
    model.visual = reparameterize_model(model.visual)
    tokenizer = open_clip.get_tokenizer(MODEL_NAME)

    ml_image = ct.models.MLModel(
        str(models_dir / "MobileCLIP2S0ImageEncoder.mlpackage"),
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    ml_text = ct.models.MLModel(
        str(models_dir / "MobileCLIP2S0TextEncoder.mlpackage"),
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )

    print("== image encoder parity ==")
    image_sims = []
    for i, arr in enumerate(fixed_images()):
        tensor = torch.from_numpy(arr).permute(2, 0, 1).float().unsqueeze(0) / 255.0
        with torch.no_grad():
            ref = F.normalize(model.encode_image(tensor), dim=-1).numpy()
        out = ml_image.predict({"image": Image.fromarray(arr)})["embedding"]
        sim = cosine(ref, out)
        image_sims.append(sim)
        norm = float(np.linalg.norm(out))
        print(f"  image[{i}] cosine={sim:.6f} coreml_norm={norm:.6f}")

    print("== text encoder parity ==")
    text_sims = []
    for text in TEXTS:
        tokens = tokenizer([text])
        with torch.no_grad():
            ref = F.normalize(model.encode_text(tokens), dim=-1).numpy()
        out = ml_text.predict({"text": tokens.numpy().astype(np.int32)})["embedding"]
        sim = cosine(ref, out)
        text_sims.append(sim)
        norm = float(np.linalg.norm(out))
        print(f"  '{text[:40]}' cosine={sim:.6f} coreml_norm={norm:.6f}")

    print("== retrieval sanity (Core ML text x Core ML image) ==")
    try:
        captions = list(RETRIEVAL_IMAGES.keys())
        image_embs = []
        for caption, url in RETRIEVAL_IMAGES.items():
            req = urllib.request.Request(url, headers={"User-Agent": "cove-parity-test"})
            data = urllib.request.urlopen(req, timeout=20).read()
            img = Image.open(io.BytesIO(data)).convert("RGB")
            side = min(img.size)
            img = img.resize(
                (round(img.width * IMAGE_SIZE / side), round(img.height * IMAGE_SIZE / side)),
                Image.BILINEAR,
            )
            left = (img.width - IMAGE_SIZE) // 2
            top = (img.height - IMAGE_SIZE) // 2
            img = img.crop((left, top, left + IMAGE_SIZE, top + IMAGE_SIZE))
            image_embs.append(ml_image.predict({"image": img})["embedding"].flatten())
        ok = True
        for i, caption in enumerate(captions):
            tokens = tokenizer([f"a photo of {caption}"]).numpy().astype(np.int32)
            temb = ml_text.predict({"text": tokens})["embedding"].flatten()
            scores = [float(temb @ iemb) for iemb in image_embs]
            best = int(np.argmax(scores))
            status = "OK" if best == i else "MISMATCH"
            ok = ok and best == i
            print(f"  '{caption}' -> best image {best} ({captions[best]}) {status} scores={[f'{s:.3f}' for s in scores]}")
        if not ok:
            raise SystemExit("retrieval sanity FAILED")
    except SystemExit:
        raise
    except Exception as exc:  # network optional
        print(f"  skipped (fetch failed: {exc})")

    min_image, min_text = min(image_sims), min(text_sims)
    print(f"min image cosine: {min_image:.6f}  min text cosine: {min_text:.6f}")
    if min_image < PARITY_THRESHOLD or min_text < PARITY_THRESHOLD:
        raise SystemExit(f"PARITY FAILED (threshold {PARITY_THRESHOLD})")
    print("PARITY PASSED")


if __name__ == "__main__":
    main()
