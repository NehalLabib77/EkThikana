"""Turning a phone photo of a prescription into something Tesseract can read.

The single most common failure in this feature is not a bad recogniser -- it
is a bad input. A prescription arrives as a hand-held photo: tilted, unevenly
lit, sometimes upside down, often photographed against a desk lamp so half the
page is blown out and the other half is grey.

No one preprocessing recipe wins on all of those. Aggressive binarisation
rescues a dim photo and destroys a faint one; upscaling rescues a small crop
and blurs a large scan. So this module produces **several** candidate images
and lets the recogniser pick the one Tesseract is actually most confident
about, measured rather than guessed.

Pillow and NumPy only. OpenCV would make the deskew shorter but roughly
doubles the Docker image, and the projection-profile method below is accurate
enough for page skew, which is the only skew a photographed A5 prescription
really has.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

#: Tesseract's accuracy falls off sharply below roughly 300 dpi equivalent.
#: For a typical A5 prescription that is about 2200 px on the long edge.
TARGET_LONG_EDGE = 2200

#: Never upscale beyond this: interpolation invents no detail, and past 2x it
#: only costs recognition time.
MAX_UPSCALE = 2.0

#: Skew is searched over this range in degrees. A page held by hand is rarely
#: more than a few degrees off; anything beyond this is a rotated page, which
#: is handled by orientation rather than by deskew.
SKEW_LIMIT_DEG = 8.0
SKEW_COARSE_STEP = 1.0
SKEW_FINE_STEP = 0.25


@dataclass(frozen=True)
class Variant:
    """One candidate rendering of the page, with a name for the logs.

    The name matters: when a prescription reads badly, knowing that the
    winning variant was ``otsu`` rather than ``contrast`` is the difference
    between debugging and guessing.
    """

    name: str
    image: Image.Image


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------


def normalise(image: Image.Image) -> Image.Image:
    """EXIF-correct, upscale to a readable size, and convert to greyscale.

    ``exif_transpose`` first, always: phone cameras record orientation in
    metadata rather than in pixels, so skipping it feeds Tesseract a sideways
    page that every later step then faithfully preserves.
    """
    img = ImageOps.exif_transpose(image)
    if img.mode not in ("L", "RGB"):
        img = img.convert("RGB")

    long_edge = max(img.size)
    if long_edge and long_edge < TARGET_LONG_EDGE:
        scale = min(MAX_UPSCALE, TARGET_LONG_EDGE / long_edge)
        img = img.resize(
            (max(1, int(img.width * scale)), max(1, int(img.height * scale))),
            Image.Resampling.LANCZOS,
        )

    return ImageOps.grayscale(img)


def otsu_threshold(image: Image.Image) -> int:
    """Otsu's threshold for a greyscale image.

    The same binarisation the supplied BanglaWriting reference used on its
    word crops. It picks the cut that best separates ink from paper for *this*
    image rather than applying a fixed 128, which is what makes it survive a
    photo taken under a yellow desk lamp.
    """
    histogram = np.asarray(image.convert("L").histogram()[:256], dtype=np.float64)
    total = histogram.sum()
    if total <= 0:
        return 128

    levels = np.arange(256, dtype=np.float64)
    weight_bg = np.cumsum(histogram)
    weight_fg = total - weight_bg

    sum_total = float((levels * histogram).sum())
    sum_bg = np.cumsum(levels * histogram)

    # Thresholds that put everything on one side separate nothing.
    valid = (weight_bg > 0) & (weight_fg > 0)
    if not valid.any():
        return 128

    mean_bg = np.divide(sum_bg, weight_bg, out=np.zeros_like(sum_bg), where=weight_bg > 0)
    mean_fg = np.divide(
        sum_total - sum_bg, weight_fg, out=np.zeros_like(sum_bg), where=weight_fg > 0
    )
    variance = weight_bg * weight_fg * (mean_bg - mean_fg) ** 2
    variance[~valid] = -1.0

    # Crisp text leaves a wide plateau of equally-good thresholds -- every cut
    # between the ink peak and the paper peak separates them identically.
    # ``argmax`` would take the lowest, landing the threshold exactly on the
    # ink value, where anti-aliased stroke edges fall on the paper side and
    # the text thins out. The middle of the plateau keeps those edges.
    best = variance.max()
    plateau = np.flatnonzero(variance >= best)
    return int((plateau[0] + plateau[-1]) // 2)


def binarise(image: Image.Image) -> Image.Image:
    threshold = otsu_threshold(image)
    return image.point(lambda value: 255 if value > threshold else 0, mode="L")


def _skew_score(binary: np.ndarray, angle: float) -> float:
    """How well-separated the text rows are at this rotation.

    Rotating the page and summing ink per row gives a projection profile. When
    the page is straight, that profile is spiky -- dense rows of text between
    empty gaps. When it is tilted, every row catches part of several text
    lines and the profile flattens. Maximising the variance of the profile
    therefore finds the angle that makes the lines horizontal.
    """
    if abs(angle) > 0.01:
        rotated = np.asarray(
            Image.fromarray(binary).rotate(
                angle, resample=Image.Resampling.BILINEAR, fillcolor=0
            )
        )
    else:
        rotated = binary
    profile = rotated.sum(axis=1, dtype=np.float64)
    return float(profile.var())


def estimate_skew(image: Image.Image) -> float:
    """The rotation, in degrees, that would straighten this page.

    This is the *correction* to apply, not the tilt itself, so it can be
    passed straight to ``Image.rotate``: a page leaning one way returns the
    angle that leans it back. ``deskew`` relies on that.

    Searched coarsely then refined, on a downscaled copy -- the profile is a
    row sum, so a 600 px wide image finds the same angle as a 2200 px one for
    a fraction of the work.
    """
    working = image.copy()
    working.thumbnail((600, 600), Image.Resampling.BILINEAR)

    threshold = otsu_threshold(working)
    # Ink as 1, paper as 0, so the profile measures text rather than page.
    binary = (np.asarray(working.convert("L")) <= threshold).astype(np.uint8) * 255

    if binary.sum() == 0:
        return 0.0

    def best_over(candidates: list[float]) -> float:
        return max(candidates, key=lambda a: _skew_score(binary, a))

    coarse = best_over(
        [
            step * SKEW_COARSE_STEP
            for step in range(
                int(-SKEW_LIMIT_DEG / SKEW_COARSE_STEP),
                int(SKEW_LIMIT_DEG / SKEW_COARSE_STEP) + 1,
            )
        ]
    )
    fine = best_over(
        [
            round(coarse + offset * SKEW_FINE_STEP, 2)
            for offset in range(-3, 4)
            if abs(coarse + offset * SKEW_FINE_STEP) <= SKEW_LIMIT_DEG
        ]
    )
    return fine


def deskew(image: Image.Image, *, angle: float | None = None) -> Image.Image:
    """Straighten the page, or return it untouched when it is already straight.

    Rotation resamples every pixel, so a quarter-degree correction costs
    sharpness it cannot repay. Below the fine search step there is nothing
    real to correct.
    """
    found = estimate_skew(image) if angle is None else angle
    if abs(found) < SKEW_FINE_STEP:
        return image
    return image.rotate(
        found,
        resample=Image.Resampling.BICUBIC,
        expand=True,
        fillcolor=255,
    )


# ---------------------------------------------------------------------------
# The variants
# ---------------------------------------------------------------------------


def variants(image: Image.Image, *, include_deskew: bool = True) -> list[Variant]:
    """Candidate renderings, cheapest and most conservative first.

    Order matters. The recogniser stops early when a variant reads
    convincingly, so a clean scan should not pay for binarisation and
    deskewing it does not need.
    """
    base = normalise(image)
    out: list[Variant] = [Variant("normalised", base)]

    # Autocontrast rescues the common case: a page photographed slightly
    # under-exposed, where the ink is present but low in contrast.
    contrast = ImageOps.autocontrast(base, cutoff=1)
    contrast = ImageEnhance.Contrast(contrast).enhance(1.35)
    out.append(Variant("contrast", contrast.filter(ImageFilter.SHARPEN)))

    # Otsu handles uneven lighting far better than any fixed threshold, and
    # is what finally reads a photo taken under a desk lamp.
    out.append(Variant("otsu", binarise(contrast)))

    # A median filter before thresholding removes camera-sensor speckle that
    # would otherwise survive binarisation as scattered false ink.
    denoised = base.filter(ImageFilter.MedianFilter(size=3))
    out.append(Variant("denoised_otsu", binarise(ImageOps.autocontrast(denoised, cutoff=1))))

    if include_deskew:
        angle = estimate_skew(base)
        if abs(angle) >= SKEW_FINE_STEP:
            straight = deskew(base, angle=angle)
            out.append(Variant(f"deskew_{angle:+.2f}", ImageOps.autocontrast(straight, cutoff=1)))
            out.append(Variant(f"deskew_{angle:+.2f}_otsu", binarise(straight)))

    return out


def orientations(image: Image.Image) -> list[Variant]:
    """The four right-angle rotations, for a page photographed sideways.

    Tried only when the upright read fails badly. Each one costs a full
    Tesseract pass, and a prescription is upright the overwhelming majority of
    the time.
    """
    return [
        Variant("rotate_90", image.rotate(90, expand=True, fillcolor=255)),
        Variant("rotate_180", image.rotate(180, expand=True, fillcolor=255)),
        Variant("rotate_270", image.rotate(270, expand=True, fillcolor=255)),
    ]


__all__ = [
    "MAX_UPSCALE",
    "SKEW_LIMIT_DEG",
    "TARGET_LONG_EDGE",
    "Variant",
    "binarise",
    "deskew",
    "estimate_skew",
    "normalise",
    "orientations",
    "otsu_threshold",
    "variants",
]
