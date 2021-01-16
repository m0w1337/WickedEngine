#pragma once

// Common blendmodes used across multiple systems
enum BLENDMODE
{
	BLENDMODE_OPAQUE,
	BLENDMODE_ALPHA,
	BLENDMODE_PREMULTIPLIED,
	BLENDMODE_ADDITIVE,
	BLENDMODE_COUNT
};

enum GBUFFER
{
	GBUFFER_COLOR_ROUGHNESS,
	GBUFFER_NORMAL_VELOCITY,
	GBUFFER_COUNT
};

// Do not alter order or value because it is bound to lua manually!
enum RENDERTYPE
{
	RENDERTYPE_VOID			= 0,
	RENDERTYPE_OPAQUE		= 1 << 0,
	RENDERTYPE_TRANSPARENT	= 1 << 1,
	RENDERTYPE_WATER		= 1 << 2,
	RENDERTYPE_ALL = RENDERTYPE_OPAQUE | RENDERTYPE_TRANSPARENT | RENDERTYPE_WATER
};

enum RENDERPASS
{
	RENDERPASS_TEXTURE,
	RENDERPASS_MAIN,
	RENDERPASS_DEPTHONLY,
	RENDERPASS_ENVMAPCAPTURE,
	RENDERPASS_SHADOW,
	RENDERPASS_SHADOWCUBE, 
	RENDERPASS_VOXELIZE,
	RENDERPASS_COUNT
};

// There are two different kinds of stencil refs:
//	ENGINE	: managed by the engine systems (STENCILREF enum values between 0-15)
//	USER	: managed by the user (raw numbers between 0-15)
enum STENCILREF_MASK
{
	STENCILREF_MASK_ENGINE = 0x0F,
	STENCILREF_MASK_USER = 0xF0,
	STENCILREF_MASK_ALL = STENCILREF_MASK_ENGINE | STENCILREF_MASK_USER,
};

// engine stencil reference values. These can be in range of [0, 15].
// Do not alter order or value because it is bound to lua manually!
enum STENCILREF 
{
	STENCILREF_EMPTY = 0,
	STENCILREF_DEFAULT = 1,
	STENCILREF_CUSTOMSHADER = 2,
	STENCILREF_LAST = 15
};

// constant buffers
enum CBTYPES
{
	CBTYPE_FRAME,
	CBTYPE_CAMERA,
	CBTYPE_MISC,
	CBTYPE_VOLUMELIGHT,
	CBTYPE_CUBEMAPRENDER,
	CBTYPE_TESSELLATION,
	CBTYPE_RAYTRACE,
	CBTYPE_MIPGEN,
	CBTYPE_FILTERENVMAP,
	CBTYPE_COPYTEXTURE,
	CBTYPE_FORWARDENTITYMASK,
	CBTYPE_POSTPROCESS,
	CBTYPE_POSTPROCESS_MSAO,
	CBTYPE_POSTPROCESS_MSAO_UPSAMPLE,
	CBTYPE_LENSFLARE,
	CBTYPE_PAINTRADIUS,
	CBTYPE_SHADINGRATECLASSIFICATION,
	CBTYPE_COUNT
};

// resource buffers (StructuredBuffer, Buffer, etc.)
enum RBTYPES
{
	RBTYPE_ENTITYARRAY,
	RBTYPE_VOXELSCENE,
	RBTYPE_MATRIXARRAY,
	RBTYPE_BLUENOISE_SOBOL_SEQUENCE,
	RBTYPE_BLUENOISE_SCRAMBLING_TILE,
	RBTYPE_BLUENOISE_RANKING_TILE,
	RBTYPE_COUNT
};

// textures
enum TEXTYPES
{
	TEXTYPE_3D_VOXELRADIANCE,
	TEXTYPE_3D_VOXELRADIANCE_HELPER,
	TEXTYPE_2D_IMPOSTORARRAY,
	TEXTYPE_CUBEARRAY_ENVMAPARRAY,
	TEXTYPE_2D_SKYATMOSPHERE_TRANSMITTANCELUT,
	TEXTYPE_2D_SKYATMOSPHERE_MULTISCATTEREDLUMINANCELUT,
	TEXTYPE_2D_SKYATMOSPHERE_SKYVIEWLUT,
	TEXTYPE_COUNT
};

// shaders
enum SHADERTYPE
{
    // vertex shaders
    VSTYPE_OBJECT_DEBUG,
    VSTYPE_OBJECT_COMMON,
    VSTYPE_OBJECT_SIMPLE,
    VSTYPE_OBJECT_POSITIONSTREAM,
    VSTYPE_OBJECT_COMMON_TESSELLATION,
    VSTYPE_OBJECT_SIMPLE_TESSELLATION,
    VSTYPE_SHADOW,
    VSTYPE_SHADOW_ALPHATEST,
    VSTYPE_SHADOW_TRANSPARENT,
    VSTYPE_SHADOWCUBEMAPRENDER,
	VSTYPE_SHADOWCUBEMAPRENDER_ALPHATEST,
	VSTYPE_SHADOWCUBEMAPRENDER_TRANSPARENT,
    VSTYPE_IMPOSTOR,
    VSTYPE_VERTEXCOLOR,
    VSTYPE_VOLUMETRICLIGHT_DIRECTIONAL,
    VSTYPE_VOLUMETRICLIGHT_POINT,
    VSTYPE_VOLUMETRICLIGHT_SPOT,
    VSTYPE_LIGHTVISUALIZER_SPOTLIGHT,
    VSTYPE_LIGHTVISUALIZER_POINTLIGHT,
    VSTYPE_SKY,
    VSTYPE_ENVMAP,
    VSTYPE_ENVMAP_SKY,
    VSTYPE_SPHERE,
    VSTYPE_CUBE,
    VSTYPE_VOXELIZER,
    VSTYPE_VOXEL,
    VSTYPE_FORCEFIELDVISUALIZER_POINT,
    VSTYPE_FORCEFIELDVISUALIZER_PLANE,
    VSTYPE_RENDERLIGHTMAP,
    VSTYPE_RAYTRACE_SCREEN,
    VSTYPE_SCREEN,
    VSTYPE_LENSFLARE,


	// pixel shaders
	PSTYPE_OBJECT,
    PSTYPE_OBJECT_TRANSPARENT,
    PSTYPE_OBJECT_PLANARREFLECTION,
    PSTYPE_OBJECT_TRANSPARENT_PLANARREFLECTION,
    PSTYPE_OBJECT_POM,
    PSTYPE_OBJECT_TRANSPARENT_POM,
    PSTYPE_OBJECT_ANISOTROPIC,
    PSTYPE_OBJECT_TRANSPARENT_ANISOTROPIC,
    PSTYPE_OBJECT_CARTOON,
    PSTYPE_OBJECT_TRANSPARENT_CARTOON,
    PSTYPE_OBJECT_UNLIT,
    PSTYPE_OBJECT_TRANSPARENT_UNLIT,
	PSTYPE_OBJECT_WATER,
    PSTYPE_OBJECT_TERRAIN,
    PSTYPE_IMPOSTOR,

    PSTYPE_OBJECT_HOLOGRAM,

    PSTYPE_OBJECT_DEBUG,
    PSTYPE_OBJECT_PAINTRADIUS,
    PSTYPE_OBJECT_SIMPLEST,
    PSTYPE_OBJECT_TEXTUREONLY,
    PSTYPE_OBJECT_ALPHATESTONLY,
    PSTYPE_IMPOSTOR_ALPHATESTONLY,
    PSTYPE_IMPOSTOR_SIMPLE,
    PSTYPE_IMPOSTOR_WIRE,

    PSTYPE_SHADOW_ALPHATEST,
    PSTYPE_SHADOW_TRANSPARENT,
    PSTYPE_SHADOW_WATER,

    PSTYPE_VERTEXCOLOR,
    PSTYPE_LIGHTVISUALIZER,
    PSTYPE_VOLUMETRICLIGHT_DIRECTIONAL,
    PSTYPE_VOLUMETRICLIGHT_POINT,
    PSTYPE_VOLUMETRICLIGHT_SPOT,
    PSTYPE_SKY_STATIC,
    PSTYPE_SKY_DYNAMIC,
    PSTYPE_SUN,
    PSTYPE_ENVMAP,
    PSTYPE_ENVMAP_TERRAIN,
    PSTYPE_ENVMAP_SKY_STATIC,
    PSTYPE_ENVMAP_SKY_DYNAMIC,
    PSTYPE_CUBEMAP,
    PSTYPE_CAPTUREIMPOSTOR_ALBEDO,
    PSTYPE_CAPTUREIMPOSTOR_NORMAL,
    PSTYPE_CAPTUREIMPOSTOR_SURFACE,
    PSTYPE_VOXELIZER,
    PSTYPE_VOXELIZER_TERRAIN,
    PSTYPE_VOXEL,
    PSTYPE_FORCEFIELDVISUALIZER,
    PSTYPE_RENDERLIGHTMAP,
    PSTYPE_RAYTRACE_DEBUGBVH,
    PSTYPE_DOWNSAMPLEDEPTHBUFFER,
    PSTYPE_POSTPROCESS_UPSAMPLE_BILATERAL,
    PSTYPE_POSTPROCESS_OUTLINE,
    PSTYPE_LENSFLARE,


	// geometry shaders
	GSTYPE_SHADOWCUBEMAPRENDER_EMULATION,
	GSTYPE_SHADOWCUBEMAPRENDER_ALPHATEST_EMULATION,
	GSTYPE_SHADOWCUBEMAPRENDER_TRANSPARENT_EMULATION,
    GSTYPE_ENVMAP_EMULATION,
    GSTYPE_ENVMAP_SKY_EMULATION,
    GSTYPE_VOXELIZER,
    GSTYPE_VOXEL,
    GSTYPE_LENSFLARE,


	// hull shaders
	HSTYPE_OBJECT,



    // domain shaders
    DSTYPE_OBJECT,


		
    // compute shaders
	CSTYPE_LUMINANCE_PASS1,
    CSTYPE_LUMINANCE_PASS2,
    CSTYPE_SHADINGRATECLASSIFICATION,
    CSTYPE_SHADINGRATECLASSIFICATION_DEBUG,
    CSTYPE_TILEFRUSTUMS,
    CSTYPE_LIGHTCULLING,
    CSTYPE_LIGHTCULLING_DEBUG,
    CSTYPE_LIGHTCULLING_ADVANCED,
    CSTYPE_LIGHTCULLING_ADVANCED_DEBUG,
    CSTYPE_RESOLVEMSAADEPTHSTENCIL,
    CSTYPE_VOXELSCENECOPYCLEAR,
    CSTYPE_VOXELSCENECOPYCLEAR_TEMPORALSMOOTHING,
    CSTYPE_VOXELRADIANCESECONDARYBOUNCE,
    CSTYPE_VOXELCLEARONLYNORMAL,
    CSTYPE_SKYATMOSPHERE_TRANSMITTANCELUT,
    CSTYPE_SKYATMOSPHERE_MULTISCATTEREDLUMINANCELUT,
    CSTYPE_SKYATMOSPHERE_SKYVIEWLUT,
    CSTYPE_GENERATEMIPCHAIN2D_UNORM4,
    CSTYPE_GENERATEMIPCHAIN2D_FLOAT4,
    CSTYPE_GENERATEMIPCHAIN3D_UNORM4,
    CSTYPE_GENERATEMIPCHAIN3D_FLOAT4,
    CSTYPE_GENERATEMIPCHAINCUBE_UNORM4,
    CSTYPE_GENERATEMIPCHAINCUBE_FLOAT4,
    CSTYPE_GENERATEMIPCHAINCUBEARRAY_UNORM4,
    CSTYPE_GENERATEMIPCHAINCUBEARRAY_FLOAT4,
    CSTYPE_FILTERENVMAP,
    CSTYPE_COPYTEXTURE2D_UNORM4,
    CSTYPE_COPYTEXTURE2D_FLOAT4,
    CSTYPE_COPYTEXTURE2D_UNORM4_BORDEREXPAND,
    CSTYPE_COPYTEXTURE2D_FLOAT4_BORDEREXPAND,
    CSTYPE_SKINNING,
    CSTYPE_SKINNING_LDS,
    CSTYPE_RAYTRACE_LAUNCH,
    CSTYPE_RAYTRACE_KICKJOBS,
    CSTYPE_RAYTRACE_CLOSESTHIT,
    CSTYPE_RAYTRACE_SHADE,
    CSTYPE_RAYTRACE_TILESORT,
    CSTYPE_PAINT_TEXTURE,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_FLOAT1,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_FLOAT3,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_FLOAT4,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_UNORM1,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_UNORM4,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_WIDE_FLOAT1,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_WIDE_FLOAT3,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_WIDE_FLOAT4,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_WIDE_UNORM1,
    CSTYPE_POSTPROCESS_BLUR_GAUSSIAN_WIDE_UNORM4,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_FLOAT1,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_FLOAT3,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_FLOAT4,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_UNORM1,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_UNORM4,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_WIDE_FLOAT1,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_WIDE_FLOAT3,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_WIDE_FLOAT4,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_WIDE_UNORM1,
    CSTYPE_POSTPROCESS_BLUR_BILATERAL_WIDE_UNORM4,
    CSTYPE_POSTPROCESS_SSAO,
    CSTYPE_POSTPROCESS_HBAO,
    CSTYPE_POSTPROCESS_MSAO_PREPAREDEPTHBUFFERS1,
    CSTYPE_POSTPROCESS_MSAO_PREPAREDEPTHBUFFERS2,
    CSTYPE_POSTPROCESS_MSAO_INTERLEAVE,
    CSTYPE_POSTPROCESS_MSAO,
    CSTYPE_POSTPROCESS_MSAO_BLURUPSAMPLE,
    CSTYPE_POSTPROCESS_MSAO_BLURUPSAMPLE_BLENDOUT,
    CSTYPE_POSTPROCESS_MSAO_BLURUPSAMPLE_PREMIN,
    CSTYPE_POSTPROCESS_MSAO_BLURUPSAMPLE_PREMIN_BLENDOUT,
    CSTYPE_POSTPROCESS_SSR_RAYTRACE,
    CSTYPE_POSTPROCESS_SSR_RESOLVE,
    CSTYPE_POSTPROCESS_SSR_TEMPORAL,
    CSTYPE_POSTPROCESS_SSR_MEDIAN,
    CSTYPE_POSTPROCESS_RTAO_DENOISE_TEMPORAL,
    CSTYPE_POSTPROCESS_RTAO_DENOISE_BLUR,
    CSTYPE_POSTPROCESS_LIGHTSHAFTS,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_TILEMAXCOC_HORIZONTAL,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_TILEMAXCOC_VERTICAL,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_NEIGHBORHOODMAXCOC,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_KICKJOBS,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_PREPASS,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_PREPASS_EARLYEXIT,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_MAIN,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_MAIN_EARLYEXIT,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_MAIN_CHEAP,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_POSTFILTER,
    CSTYPE_POSTPROCESS_DEPTHOFFIELD_UPSAMPLE,
    CSTYPE_POSTPROCESS_MOTIONBLUR_TILEMAXVELOCITY_HORIZONTAL,
    CSTYPE_POSTPROCESS_MOTIONBLUR_TILEMAXVELOCITY_VERTICAL,
    CSTYPE_POSTPROCESS_MOTIONBLUR_NEIGHBORHOODMAXVELOCITY,
    CSTYPE_POSTPROCESS_MOTIONBLUR_KICKJOBS,
    CSTYPE_POSTPROCESS_MOTIONBLUR,
    CSTYPE_POSTPROCESS_MOTIONBLUR_EARLYEXIT,
    CSTYPE_POSTPROCESS_MOTIONBLUR_CHEAP,
    CSTYPE_POSTPROCESS_BLOOMSEPARATE,
    CSTYPE_POSTPROCESS_BLOOMCOMBINE,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_SHAPENOISE,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_DETAILNOISE,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_CURLNOISE,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_WEATHERMAP,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_RENDER,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_REPROJECT,
    CSTYPE_POSTPROCESS_VOLUMETRICCLOUDS_FINAL,
    CSTYPE_POSTPROCESS_FXAA,
    CSTYPE_POSTPROCESS_TEMPORALAA,
    CSTYPE_POSTPROCESS_LINEARDEPTH,
    CSTYPE_POSTPROCESS_SHARPEN,
    CSTYPE_POSTPROCESS_TONEMAP,
    CSTYPE_POSTPROCESS_CHROMATIC_ABERRATION,
    CSTYPE_POSTPROCESS_UPSAMPLE_BILATERAL_FLOAT1,
    CSTYPE_POSTPROCESS_UPSAMPLE_BILATERAL_UNORM1,
    CSTYPE_POSTPROCESS_UPSAMPLE_BILATERAL_FLOAT4,
    CSTYPE_POSTPROCESS_UPSAMPLE_BILATERAL_UNORM4,
    CSTYPE_POSTPROCESS_DOWNSAMPLE4X,
    CSTYPE_POSTPROCESS_NORMALSFROMDEPTH,


       
    // raytracing shaders
    RTTYPE_RTAO,
    RTTYPE_RTREFLECTION,



    SHADERTYPE_COUNT,
};

// input layouts
enum ILTYPES
{
	ILTYPE_OBJECT_DEBUG,
	ILTYPE_OBJECT_POS,
	ILTYPE_OBJECT_POS_TEX,
	ILTYPE_OBJECT_ALL,
	ILTYPE_SHADOW_POS,
	ILTYPE_SHADOW_POS_TEX,
	ILTYPE_RENDERLIGHTMAP,
	ILTYPE_VERTEXCOLOR,
	ILTYPE_COUNT
};
// rasterizer states
enum RSTYPES
{
	RSTYPE_FRONT,
	RSTYPE_BACK,
	RSTYPE_DOUBLESIDED,
	RSTYPE_WIRE,
	RSTYPE_WIRE_SMOOTH,
	RSTYPE_WIRE_DOUBLESIDED,
	RSTYPE_WIRE_DOUBLESIDED_SMOOTH,
	RSTYPE_SHADOW,
	RSTYPE_SHADOW_DOUBLESIDED,
	RSTYPE_OCCLUDEE, 
	RSTYPE_VOXELIZE,
	RSTYPE_SKY,
	RSTYPE_COUNT
};
// depth-stencil states
enum DSSTYPES
{
	DSSTYPE_DEFAULT,
	DSSTYPE_SHADOW,
	DSSTYPE_XRAY,
	DSSTYPE_DEPTHREAD,
	DSSTYPE_DEPTHREADEQUAL,
	DSSTYPE_ENVMAP,
	DSSTYPE_CAPTUREIMPOSTOR,
	DSSTYPE_WRITEONLY,
	DSSTYPE_COUNT
};
// blend states
enum BSTYPES
{
	BSTYPE_OPAQUE,
	BSTYPE_TRANSPARENT,
	BSTYPE_INVERSE,
	BSTYPE_ADDITIVE,
	BSTYPE_PREMULTIPLIED,
	BSTYPE_COLORWRITEDISABLE,
	BSTYPE_ENVIRONMENTALLIGHT,
	BSTYPE_DECAL,
	BSTYPE_MULTIPLY,
	BSTYPE_TRANSPARENTSHADOW,
	BSTYPE_COUNT
};
