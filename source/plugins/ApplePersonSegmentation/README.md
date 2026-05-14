# Apple Person Segmentation

FFGL effect plugin that uses Apple's Vision framework to generate a person matte from the input texture and applies that matte to the plugin output alpha.

## Build

```sh
cmake -S . -B build/cmake -DFFGL_BUILD_EXAMPLE_PLUGINS=ON
cmake --build build/cmake --target ApplePersonSegmentation --config Release
```

The built bundle is written to:

```text
build/cmake/source/plugins/ApplePersonSegmentation/ApplePersonSegmentation.bundle
```

Copy the bundle to `~/Documents/Resolume/Extra Effects` and restart Resolume.

## Parameters

- `Threshold`: cutoff for the Vision matte.
- `Softness`: edge smoothing around the threshold.
- `Shrink / Grow`: normalized mask size control. `0.5` is neutral, lower values shrink the person matte, and higher values grow it.
- `Feather`: smooths the processed matte edge after shrink/grow.
- `Opacity`: strength of the matte applied to output alpha.
- `Invert Mask`: keeps the background instead of the person.
- `Show Mask`: outputs the raw processed matte for tuning.
- `Quality`: maps low, mid, and high values to Vision's fast, balanced, and accurate quality levels.
- `Output Mode`: `Premult Alpha` follows FFGL's premultiplied-alpha convention, while `Straight Alpha` keeps RGB unmultiplied and only writes the matte to alpha for hosts or clip paths that otherwise show a black fill.

The Vision request requires macOS 12 or newer at runtime. On older macOS versions, the plugin passes the input through unchanged.
