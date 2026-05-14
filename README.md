# FFGL Person Matte

Resolume FFGL effect plugin that uses Apple's Vision framework to generate a person segmentation matte from the input clip. The matte can be previewed, softened, inverted, and applied as alpha so people can be isolated from the background inside Resolume.

This project is based on the Resolume FFGL SDK and adds the `ApplePersonSegmentation` plugin under `source/plugins/ApplePersonSegmentation`.

## Requirements

- macOS 12 or newer for `VNGeneratePersonSegmentationRequest`
- Apple Silicon or Intel Mac supported by your Resolume build
- Resolume 7.3.1 or newer
- Xcode command line tools
- CMake 3.15 or newer

For Apple Silicon Resolume builds, use an arm64 or universal plugin build. An x86_64-only plugin will not load in native Apple Silicon Resolume.

## Build

```sh
cmake -S . -B build/cmake -DFFGL_BUILD_EXAMPLE_PLUGINS=ON
cmake --build build/cmake --target ApplePersonSegmentation --config Release
```

The built plugin bundle is written to:

```text
build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle
```

## Install

Copy the bundle to Resolume's extra effects folder:

```sh
cp -R build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle ~/Documents/Resolume/Extra\ Effects/
```

Restart Resolume after copying the bundle. The effect should appear as `Apple Person Segmentation`.

## Parameters

- `Threshold`: cutoff for the Vision matte.
- `Softness`: edge smoothing around the threshold.
- `Opacity`: strength of the matte applied to output alpha.
- `Invert Mask`: keeps the background instead of the person.
- `Show Mask`: outputs the processed grayscale matte for tuning.
- `Quality`: maps low, mid, and high values to Vision's fast, balanced, and accurate quality levels.
- `Output Mode`: `Premult Alpha` follows FFGL's premultiplied-alpha convention, while `Straight Alpha` keeps RGB unmultiplied and writes the matte to alpha for host paths that otherwise show black fill.

## Notes

The current implementation prioritizes proving the Vision-to-FFGL path. It reads the Resolume OpenGL texture back to CPU and runs Vision synchronously each frame, which is expensive. Future optimization work should move toward asynchronous processing, lower-resolution inference, frame skipping, and GPU-friendly texture transfer.

On macOS versions without Vision person segmentation support, the plugin passes the input through unchanged.

