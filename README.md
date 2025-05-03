# Fast Sun Shafts
Sun shafts post effect based on dithering dispersion of screen coordinates.
Compability: URP 17 (Unity 6), Build Platform - Android.
This effect is implemented on new perfomant Render Graph API. It doesn't use the depth buffer, and the UV of the alpha mask image are scattered => You need to write custom skybox shader returning 0 to alpha channel. The implementation uses dual kawase blur and pre-downsampling pass to hide the dither-noise. 
Pros: -fast for mobile platforms, doesn't use depth buffer
      -is flexibly customisable
Cons: -artifacts because of the clamp-samling (=> you can try mirror-wrapping)
      -dither-noise is still visible (=> you can increase blur steps)
      -the whole sky casts shafts in this example (you can try alpha cubemaps for skybox)
