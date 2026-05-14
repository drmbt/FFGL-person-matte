# Apple Monocular Depth

FFGL effect plugin that uses Vision's Core ML request pipeline to generate a monocular depth map from the input texture. The plugin supports two embedded Core ML depth models and exposes a `Model` selector for switching between fast and quality inference.

## Recommended Models

- `Fast`: [Apple's Depth Anything V2 Small Core ML model](https://huggingface.co/apple/coreml-depth-anything-v2-small), such as `DepthAnythingV2SmallF16.mlpackage` or a compiled `.mlmodelc`. This is the lower-resource choice for live playback.
- `Quality`: a Depth Anything V2 Large Core ML model, such as one from [Core ML Depth Anything V2 model releases](https://huggingface.co/mrgnw/depth-anything-v2-coreml), as a large F16 `.mlpackage` or compiled `.mlmodelc`. This is intended for beefier machines where quality matters more than frame rate.

The small model is the best default for realtime Resolume use. Large models are much heavier and may not be licensed for all commercial uses depending on the source model.

## Build

```sh
cmake -S . -B build/cmake -DFFGL_BUILD_EXAMPLE_PLUGINS=ON \
  -DAPPLE_MONOCULAR_DEPTH_FAST_MODEL=/path/to/DepthAnythingV2SmallF16.mlpackage \
  -DAPPLE_MONOCULAR_DEPTH_QUALITY_MODEL=/path/to/DepthAnythingV2LargeF16.mlpackage
cmake --build build/cmake --target AppleMonocularDepth --config Release
```

The built bundle is written to:

```text
build/cmake/source/plugins/AppleMonocularDepth/AppleMonocularDepth.bundle
```

Copy the bundle to `~/Documents/Resolume/Extra Effects` and restart Resolume.

If you do not pass model paths to CMake, copy models into `AppleMonocularDepth.bundle/Contents/Resources` before loading the plugin. Use these names for deterministic selection:

```text
DepthAnythingFast.mlmodelc
DepthAnythingQuality.mlmodelc
```

`.mlpackage` and `.mlmodel` inputs are also supported and compiled by Core ML at runtime.

## Parameters

- `Opacity`: blends from the original input at `0.0` to the depth map at `1.0`.
- `Model`: selects `Fast` or `Quality`.
- `Low`: lower normalized depth threshold. Values below this are returned with alpha `0`.
- `High`: upper normalized depth threshold. Values above this are returned with alpha `0`.
- `Mask Mode`: outputs the original input multiplied by the alpha mask for the depth band between `Low` and `High`.
- `Output Mask`: outputs only the thresholded depth band as white, with alpha `0` outside the `Low` to `High` range.

The default output is a grayscale depth map from the affected input clip. `Low` and `High` default to the full `0.0` to `1.0` range, so no depth values are masked until you narrow the band.
