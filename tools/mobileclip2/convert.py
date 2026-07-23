#!/usr/bin/env python3
"""Convert MobileCLIP2-S0 (apple/MobileCLIP2-S0) to Core ML.

Exports:
  - MobileCLIP2S0ImageEncoder.mlpackage  (1x3x256x256 RGB image -> 512-d L2-normalized Float32)
  - MobileCLIP2S0TextEncoder.mlpackage   (1x77 int32 CLIP BPE tokens -> 512-d L2-normalized Float32)
  - clip-tokenizer.json                  (vocab + merges for the Swift tokenizer port)
  - tokenizer-fixtures.json              (text -> expected token ids, for Swift parity tests)

Preprocessing (verified against open_clip's pretrained registry `_mccfg` for
MobileCLIP2-S0 and timm/MobileCLIP2-S0-OpenCLIP open_clip_config.json):
  mean=(0,0,0) std=(1,1,1), i.e. RGB scaled to [0,1]; bilinear resize of the
  shortest side to 256 then center crop to 256x256. NOT the OpenAI CLIP norms.
The [0,1] scaling is baked into the Core ML image input (scale=1/255) so Swift
feeds a plain 256x256 RGB CVPixelBuffer.

Usage:
  python convert.py --checkpoint mobileclip2_s0.pt --output-dir out
"""

import argparse
import gzip
import html
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import open_clip
import torch
import torch.nn.functional as F
from timm.utils.model import reparameterize_model

MODEL_NAME = "MobileCLIP2-S0"
MODEL_VERSION = "mobileclip2-s0-v1"
IMAGE_SIZE = 256
CONTEXT_LENGTH = 77


class ImageEncoder(torch.nn.Module):
    def __init__(self, clip_model):
        super().__init__()
        self.model = clip_model

    def forward(self, image):
        features = self.model.encode_image(image)
        return F.normalize(features, dim=-1)


class TextEncoder(torch.nn.Module):
    def __init__(self, clip_model):
        super().__init__()
        self.model = clip_model

    def forward(self, tokens):
        features = self.model.encode_text(tokens.to(torch.int64))
        return F.normalize(features, dim=-1)


def load_model(checkpoint: str):
    model, _, _ = open_clip.create_model_and_transforms(
        MODEL_NAME, pretrained=checkpoint
    )
    model.eval()
    before = sum(p.numel() for p in model.visual.parameters())
    model.visual = reparameterize_model(model.visual)
    after = sum(p.numel() for p in model.visual.parameters())
    print(f"reparameterized visual tower: {before / 1e6:.2f}M -> {after / 1e6:.2f}M params")
    return model


def convert_image_encoder(model, output_dir: Path):
    # torch.jit.trace fails in the coremltools torchscript frontend on this
    # tower (an aten::Int over a non-scalar); the torch.export path converts.
    wrapper = ImageEncoder(model).eval()
    example = (torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE),)
    exported = torch.export.export(wrapper, example).run_decompositions({})

    mlmodel = ct.convert(
        exported,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, IMAGE_SIZE, IMAGE_SIZE),
                scale=1.0 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.user_defined_metadata["model_version"] = MODEL_VERSION
    mlmodel.user_defined_metadata["embedding_dimension"] = "512"
    mlmodel.user_defined_metadata["source"] = "apple/MobileCLIP2-S0 (apple-amlr license)"
    mlmodel.short_description = "MobileCLIP2-S0 image encoder, L2-normalized 512-d output"
    path = output_dir / "MobileCLIP2S0ImageEncoder.mlpackage"
    mlmodel.save(str(path))
    print(f"saved {path}")
    return path


def convert_text_encoder(model, output_dir: Path):
    wrapper = TextEncoder(model).eval()
    example = (torch.randint(0, 49408, (1, CONTEXT_LENGTH), dtype=torch.int32),)
    exported = torch.export.export(wrapper, example).run_decompositions({})

    mlmodel = ct.convert(
        exported,
        inputs=[
            ct.TensorType(name="text", shape=(1, CONTEXT_LENGTH), dtype=np.int32)
        ],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.user_defined_metadata["model_version"] = MODEL_VERSION
    mlmodel.user_defined_metadata["embedding_dimension"] = "512"
    mlmodel.user_defined_metadata["source"] = "apple/MobileCLIP2-S0 (apple-amlr license)"
    mlmodel.short_description = "MobileCLIP2-S0 text encoder, L2-normalized 512-d output"
    path = output_dir / "MobileCLIP2S0TextEncoder.mlpackage"
    mlmodel.save(str(path))
    print(f"saved {path}")
    return path


def export_tokenizer_assets(output_dir: Path):
    """Export the CLIP BPE vocab/merges and token-id fixtures for the Swift port."""
    from open_clip.tokenizer import default_bpe

    with gzip.open(default_bpe(), "rt", encoding="utf-8") as f:
        merges = f.read().split("\n")
    # Same slice the reference SimpleTokenizer uses.
    merges = merges[1 : 49152 - 256 - 2 + 1]

    tokenizer = open_clip.get_tokenizer(MODEL_NAME)

    payload = {
        "context_length": CONTEXT_LENGTH,
        "vocab_size": 49408,
        "sot_token": tokenizer.sot_token_id,
        "eot_token": tokenizer.eot_token_id,
        "merges": merges,
    }
    tok_path = output_dir / "clip-tokenizer.json"
    tok_path.write_text(json.dumps(payload))
    print(f"saved {tok_path} ({tok_path.stat().st_size / 1e6:.1f} MB)")

    fixtures = [
        "a photo of a coffee receipt",
        "receipt from a coffee shop, total $22.50",
        "screenshot of a concert ticket for Saturday night",
        "a cat sleeping on a windowsill",
        "sunset over the ocean with palm trees",
        "Kyoto pour-over coffee menu",
        "invoice #2048 North Star Market",
        "a hand-written note about groceries",
        "IKEA order confirmation email",
        "don't forget the meeting at 3pm!",
        "café löffel — überraschung",
        "MIXED case With   extra Spaces",
    ]
    fixture_rows = []
    for text in fixtures:
        ids = tokenizer([text])[0].tolist()
        fixture_rows.append({"text": text, "ids": ids})
    fix_path = output_dir / "tokenizer-fixtures.json"
    fix_path.write_text(json.dumps(fixture_rows, ensure_ascii=False, indent=1))
    print(f"saved {fix_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--output-dir", default="out")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model = load_model(args.checkpoint)
    with torch.no_grad():
        convert_image_encoder(model, output_dir)
        convert_text_encoder(model, output_dir)
    export_tokenizer_assets(output_dir)


if __name__ == "__main__":
    main()
