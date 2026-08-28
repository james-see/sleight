#!/usr/bin/env python
"""Generate the Sleight app icon via Gemini image generation on Vertex AI.

Usage: python scripts/make_icon.py [output.png]
Requires gcloud application-default credentials on project vala-466919.
"""
import base64
import pathlib
import sys

from google import genai

PROJECT = "vala-466919"
LOCATION = "us-central1"
MODEL = "gemini-2.5-flash-image"

PROMPT = (
    "Minimalist geometric macOS app icon, monochromatic blue (#0A84FF) on a "
    "near-black rounded-square background: a pinch gesture abstracted into two "
    "converging arcs meeting at a small filled circle, hovering above a thin "
    "horizontal waveform line. Flat vector style, no gradients, no text, "
    "centered composition, generous padding, crisp edges."
)


def main() -> None:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "icon.png")
    client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION)
    resp = client.models.generate_content(
        model=MODEL,
        contents=[PROMPT],
        config={"response_modalities": ["IMAGE"]},
    )
    candidates = resp.candidates or []
    if not candidates or candidates[0].content is None or candidates[0].content.parts is None:
        raise SystemExit(f"no image returned: {resp.model_dump_json()[:500]}")
    part = next((p for p in candidates[0].content.parts if p.inline_data is not None), None)
    if part is None or part.inline_data is None or part.inline_data.data is None:
        raise SystemExit("response contained no image part")
    out.write_bytes(base64.b64decode(part.inline_data.data))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()