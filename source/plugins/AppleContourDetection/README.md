# Apple Contour Detection

Resolume FFGL effect plugin that uses Apple's Vision framework to detect image contours from the input clip and composite them as stylized line masks.

## Parameters

- `Contrast`: Vision contour contrast adjustment. Defaults to `0.604701`.
- `Line Width`: CPU rasterized contour thickness. Defaults to `0.297084`.
- `Opacity`: contour compositing strength. Defaults to `1.0`.
- `Dark Lines`: detects dark lines on light backgrounds. Defaults to off.
- `Invert Mask`: inverts the contour mask before compositing. Defaults to off.
- `Show Mask`: outputs the grayscale contour mask for tuning. Defaults to on.
- `Blend Mode`: add white lines, invert along contours, or output contour alpha. Defaults to `Add White`.
- `Detail`: maximum image dimension used by Vision contour detection. Defaults to `0.5`.

## Notes

This first version follows the existing Vision-to-FFGL path in this repository: it reads the OpenGL input texture back to CPU, runs Vision synchronously, rasterizes contours into an 8-bit mask, uploads that mask to OpenGL, and composites it in a shader. It is intended as a testable creative prototype rather than a fully optimized realtime path.
