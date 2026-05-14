# Apple Contour Detection

Resolume FFGL effect plugin that uses Apple's Vision framework to detect image contours from the input clip and output them as stylized colored line layers over alpha.

## Parameters

- `Contrast`: Vision contour contrast adjustment. Defaults to `0.604701`.
- `Line Width`: CPU rasterized contour thickness. Defaults to `0.297084`.
- `Color 1`: Resolume's native HSBA color picker for the contour lines. Defaults to white.
- `Opacity`: line strength, including when composited over the input. Defaults to `1.0`.
- `Comp Over Input`: composites the colored lines over the original clip instead of outputting lines over alpha. Defaults to off.

## Notes

This first version follows the existing Vision-to-FFGL path in this repository: it reads the OpenGL input texture back to CPU, runs Vision synchronously, rasterizes contours into an 8-bit mask, uploads that mask to OpenGL, and composites it in a shader. It is intended as a testable creative prototype rather than a fully optimized realtime path.
