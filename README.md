# Apple Vision FFGL Effects

Resolume FFGL effect plugins that use Apple's Vision framework to generate realtime analysis layers from the input clip.

This project is based on the Resolume FFGL SDK and adds:

- `ApplePersonSegmentation`: person segmentation matte generation.
- `AppleContourDetection`: contour line mask generation.

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
cmake --build build/cmake --target AppleContourDetection --config Release
```

The built plugin bundle is written to:

```text
build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle
build/cmake/source/plugins/AppleContourDetection/AppleContourDetection.bundle
```

## Install

Copy the bundle to Resolume's extra effects folder:

```sh
cp -R build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle ~/Documents/Resolume/Extra\ Effects/
cp -R build/cmake/source/plugins/AppleContourDetection/AppleContourDetection.bundle ~/Documents/Resolume/Extra\ Effects/
```

Restart Resolume after copying the bundles. The effects should appear as `Apple Person Segmentation` and `Apple Contour Detection`.

## Apple Person Segmentation Parameters

- `Threshold`: cutoff for the Vision matte.
- `Softness`: edge smoothing around the threshold.
- `Opacity`: strength of the matte applied to output alpha.
- `Invert Mask`: keeps the background instead of the person.
- `Show Mask`: outputs the processed grayscale matte for tuning.
- `Quality`: maps low, mid, and high values to Vision's fast, balanced, and accurate quality levels.
- `Output Mode`: `Premult Alpha` follows FFGL's premultiplied-alpha convention, while `Straight Alpha` keeps RGB unmultiplied and writes the matte to alpha for host paths that otherwise show black fill.

## Apple Contour Detection Parameters

- `Contrast`: Vision contour contrast adjustment. Defaults to `0.604701`.
- `Line Width`: CPU rasterized contour thickness. Defaults to `0.297084`.
- `Opacity`: contour compositing strength. Defaults to `1.0`.
- `Dark Lines`: detects dark lines on light backgrounds. Defaults to off.
- `Invert Mask`: inverts the contour mask before compositing. Defaults to off.
- `Show Mask`: outputs the grayscale contour mask for tuning. Defaults to on.
- `Blend Mode`: add white lines, invert along contours, or output contour alpha. Defaults to `Add White`.
- `Detail`: maximum image dimension used by Vision contour detection. Defaults to `0.5`.

## Notes

The current implementation prioritizes proving the Vision-to-FFGL path. It reads the Resolume OpenGL texture back to CPU and runs Vision synchronously each frame, which is expensive. Future optimization work should move toward asynchronous processing, lower-resolution inference, frame skipping, and GPU-friendly texture transfer.

On macOS versions without Vision person segmentation support, the plugin passes the input through unchanged.

