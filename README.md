# Apple Vision FFGL Effects

Resolume FFGL effect plugins that use Apple's Vision framework to generate realtime analysis layers from the input clip.

This project is based on the Resolume FFGL SDK and adds:

- `ApplePersonSegmentation`: person segmentation matte generation.
- `AppleContourDetection`: colored contour line generation over alpha.
- `AppleMonocularDepth`: monocular depth map and depth-band matte generation from an embedded Core ML model.

## Requirements

- macOS 12 or newer for `VNGeneratePersonSegmentationRequest`
- Vision-compatible Core ML depth models, such as Depth Anything V2 Small for `Fast` mode and Depth Anything V2 Large for `Quality` mode, for `AppleMonocularDepth`
- Apple Silicon or Intel Mac supported by your Resolume build
- Resolume 7.3.1 or newer
- Xcode command line tools
- CMake 3.15 or newer

For Apple Silicon Resolume builds, use an arm64 or universal plugin build. An x86_64-only plugin will not load in native Apple Silicon Resolume.

## Build

```sh
cmake -S . -B build/cmake -DFFGL_BUILD_EXAMPLE_PLUGINS=ON
cmake --build build/cmake --target ApplePersonSegmentation --config Release
cmake --build build/cmake --target AppleContourDetection --config Release
cmake --build build/cmake --target AppleMonocularDepth --config Release
```

The built plugin bundle is written to:

```text
build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle
build/cmake/source/plugins/AppleContourDetection/AppleContourDetection.bundle
build/cmake/source/plugins/AppleMonocularDepth/AppleMonocularDepth.bundle
```

To embed depth models at build time, configure with:

```sh
cmake -S . -B build/cmake -DFFGL_BUILD_EXAMPLE_PLUGINS=ON \
  -DAPPLE_MONOCULAR_DEPTH_FAST_MODEL=/path/to/DepthAnythingV2SmallF16.mlpackage \
  -DAPPLE_MONOCULAR_DEPTH_QUALITY_MODEL=/path/to/DepthAnythingV2LargeF16.mlpackage
```

## Install

Copy the bundle to Resolume's extra effects folder:

```sh
cp -R build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle ~/Documents/Resolume/Extra\ Effects/
cp -R build/cmake/source/plugins/AppleContourDetection/AppleContourDetection.bundle ~/Documents/Resolume/Extra\ Effects/
cp -R build/cmake/source/plugins/AppleMonocularDepth/AppleMonocularDepth.bundle ~/Documents/Resolume/Extra\ Effects/
```

Restart Resolume after copying the bundles. The effects should appear as `Apple Person Segmentation`, `Apple Contour Detection`, and `Apple Monocular Depth`.

## Apple Person Segmentation Parameters

- `Threshold`: cutoff for the Vision matte.
- `Softness`: edge smoothing around the threshold.
- `Shrink / Grow`: normalized mask size control. `0.5` is neutral, lower values shrink the matte, and higher values grow it with an expanded maximum grow range.
- `Feather`: smooths the matte edge after shrink/grow with a weighted multi-step blur.
- `Opacity`: strength of the matte applied to output alpha.
- `Invert Mask`: keeps the background instead of the person.
- `Show Mask`: outputs the processed grayscale matte for tuning.
- `Quality`: maps low, mid, and high values to Vision's fast, balanced, and accurate quality levels.
- `Output Mode`: `Premult Alpha` follows FFGL's premultiplied-alpha convention, while `Straight Alpha` keeps RGB unmultiplied and writes the matte to alpha for host paths that otherwise show black fill.

## Apple Contour Detection Parameters

- `Contrast`: Vision contour contrast adjustment. Defaults to `0.604701`.
- `Line Width`: CPU rasterized contour thickness. Defaults to `0.297084`.
- `Color 1`: Resolume's native HSBA color picker for the contour lines. Defaults to white.
- `Opacity`: line strength, including when composited over the input. Defaults to `1.0`.
- `Comp Over Input`: composites the colored lines over the original clip instead of outputting lines over alpha. Defaults to off.

## Apple Monocular Depth Parameters

- `Opacity`: blends from the original input at `0.0` to the generated depth map at `1.0`. Defaults to `1.0`.
- `Model`: selects `Fast` for lower-resource live playback or `Quality` for a heavier depth model on faster machines.
- `Low`: lower normalized depth threshold. Depth values below this output alpha `0`.
- `High`: upper normalized depth threshold. Depth values above this output alpha `0`.
- `Mask Mode`: multiplies the original input by the alpha mask for the depth band between `Low` and `High`.
- `Output Mask`: outputs only the thresholded depth band as white, with alpha `0` outside the `Low` to `High` range.

## Notes

The current implementation prioritizes proving the Vision-to-FFGL path. It reads the Resolume OpenGL texture back to CPU and runs Vision synchronously each frame, which is expensive. Future optimization work should move toward asynchronous processing, lower-resolution inference, frame skipping, and GPU-friendly texture transfer.

On macOS versions without Vision person segmentation support, the plugin passes the input through unchanged.

`AppleMonocularDepth` passes the input through unchanged until a `.mlmodelc`, `.mlpackage`, or `.mlmodel` is present in the plugin bundle resources. For deterministic model selection, embed fast models as `DepthAnythingFast` and quality models as `DepthAnythingQuality`. Model outputs are normalized per frame before thresholding.

