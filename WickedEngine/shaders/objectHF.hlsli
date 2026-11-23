#ifndef WI_OBJECTSHADER_HF
#define WI_OBJECTSHADER_HF

#ifdef TRANSPARENT
#else
#define SHADOW_MASK_ENABLED
#endif // TRANSPARENT

#if !defined(TRANSPARENT) && !defined(PREPASS) && !defined(ENVMAPRENDERING)
#define DISABLE_ALPHATEST
#endif // !defined(TRANSPARENT) && !defined(PREPASS) && !defined(ENVMAPRENDERING)

#ifdef PLANARREFLECTION
#define DISABLE_ENVMAPS
#define DISABLE_VOXELGI
#endif // PLANARREFLECTION

#ifdef WATER
#define DISABLE_ENVMAPS
#define DISABLE_VOXELGI
#endif // WATER

//#define LIGHTMAP_QUALITY_BICUBIC

#ifdef DISABLE_ALPHATEST
#define EARLY_DEPTH_STENCIL
#endif // DISABLE_ALPHATEST

#ifdef EARLY_DEPTH_STENCIL
#define SVT_FEEDBACK
#endif // EARLY_DEPTH_STENCIL

#ifdef TERRAINBLENDED
#define TEXTURE_SLOT_NONUNIFORM
#endif // TERRAINBLENDED

#if !defined(OBJECTSHADER_LAYOUT_COMMON) && !defined(ENVMAPRENDERING)
#define DISABLE_SVT
#endif // !defined(OBJECTSHADER_LAYOUT_COMMON) && !defined(ENVMAPRENDERING)

#include "globals.hlsli"
#include "brdf.hlsli"
#include "lightingHF.hlsli"
#include "skyAtmosphere.hlsli"
#include "fogHF.hlsli"
#include "ShaderInterop_SurfelGI.h"
#include "ShaderInterop_DDGI.h"
#include "shadingHF.hlsli"

// DEFINITIONS
//////////////////

PUSHCONSTANT(push, ObjectPushConstants);

#define GetMesh() (load_geometry(push.geometryIndex))
#define GetMaterial() (load_material(push.materialIndex))

//#define sampler_objectshader bindless_samplers[descriptor_index(GetMaterial().sampler_descriptor)]
#define sampler_objectshader bindless_samplers[descriptor_index(push.samplerIndex)] // This one loads it faster from push constant than the above that loads from material struct but it must be fed per draw call

// Use these to compile this file as shader prototype:
//#define OBJECTSHADER_COMPILE_VS				- compile vertex shader prototype
//#define OBJECTSHADER_COMPILE_PS				- compile pixel shader prototype

// Use these to define the expected layout for the shader:
//#define OBJECTSHADER_LAYOUT_SHADOW			- layout for shadow pass
//#define OBJECTSHADER_LAYOUT_SHADOW_TEX		- layout for shadow pass and alpha test or transparency
//#define OBJECTSHADER_LAYOUT_PREPASS			- layout for prepass
//#define OBJECTSHADER_LAYOUT_PREPASS_TEX		- layout for prepass and alpha test or dithering
//#define OBJECTSHADER_LAYOUT_COMMON			- layout for common passes

// Use these to enable features for the shader:
//	(Some of these are enabled automatically with OBJECTSHADER_LAYOUT defines)
//#define OBJECTSHADER_USE_CLIPPLANE				- shader will be clipped according to camera clip planes
//#define OBJECTSHADER_USE_COLOR					- shader will use colors (material color, vertex color...)
//#define OBJECTSHADER_USE_DITHERING				- shader will use dithered transparency
//#define OBJECTSHADER_USE_UVSETS					- shader will sample textures with uv sets
//#define OBJECTSHADER_USE_NORMAL					- shader will use normals
//#define OBJECTSHADER_USE_TANGENT					- shader will use tangents, normal mapping
//#define OBJECTSHADER_USE_EMISSIVE					- shader will use emissive
//#define OBJECTSHADER_USE_RENDERTARGETARRAYINDEX	- shader will use dynamic render target slice selection
//#define OBJECTSHADER_USE_VIEWPORTARRAYINDEX		- shader will use dynamic viewport selection
//#define OBJECTSHADER_USE_NOCAMERA					- shader will not use camera space transform
//#define OBJECTSHADER_USE_INSTANCEINDEX			- shader will use instance ID
//#define OBJECTSHADER_USE_CAMERAINDEX				- shader will use camera ID
//#define OBJECTSHADER_USE_COMMON					- shader will use atlas, ambient occlusion, wetmap
//#define OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER	- shader will load vertex ID through provoking index buffer reordering


#ifdef OBJECTSHADER_LAYOUT_SHADOW
#define OBJECTSHADER_USE_CAMERAINDEX
#endif // OBJECTSHADER_LAYOUT_SHADOW

#ifdef OBJECTSHADER_LAYOUT_SHADOW_TEX
#define OBJECTSHADER_USE_INSTANCEINDEX
#define OBJECTSHADER_USE_UVSETS
#define OBJECTSHADER_USE_CAMERAINDEX
#endif // OBJECTSHADER_LAYOUT_SHADOW_TEX

#ifdef OBJECTSHADER_LAYOUT_PREPASS
#define PREPASS
#define OBJECTSHADER_USE_CLIPPLANE
#define OBJECTSHADER_USE_INSTANCEINDEX
#ifndef OBJECTSHADER_COMPILE_MS
#define OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER
#endif // OBJECTSHADER_COMPILE_MS
#endif // OBJECTSHADER_LAYOUT_SHADOW

#ifdef OBJECTSHADER_LAYOUT_PREPASS_TEX
#define PREPASS
#define OBJECTSHADER_USE_CLIPPLANE
#define OBJECTSHADER_USE_UVSETS
#define OBJECTSHADER_USE_DITHERING
#define OBJECTSHADER_USE_INSTANCEINDEX
#ifndef OBJECTSHADER_COMPILE_MS
#define OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER
#endif // OBJECTSHADER_COMPILE_MS
#endif // OBJECTSHADER_LAYOUT_SHADOW_TEX

#ifdef OBJECTSHADER_LAYOUT_COMMON
#define OBJECTSHADER_USE_CLIPPLANE
#define OBJECTSHADER_USE_UVSETS
#define OBJECTSHADER_USE_COLOR
#define OBJECTSHADER_USE_NORMAL
#define OBJECTSHADER_USE_TANGENT
#define OBJECTSHADER_USE_EMISSIVE
#define OBJECTSHADER_USE_INSTANCEINDEX
#define OBJECTSHADER_USE_COMMON
#ifndef OBJECTSHADER_COMPILE_MS
#define OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER // even though primitiveID is not exported, color pass required to have same primitive order on Intel GPU, otherwise depth mismatch occurs
#endif // OBJECTSHADER_COMPILE_MS
#endif // OBJECTSHADER_LAYOUT_COMMON

struct VertexInput
{
	uint vertexID : SV_VertexID;
	uint instanceID : SV_InstanceID;
	STEREO_VIEWID_FIELD
	
#ifdef OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER
	uint GetPrimitiveID()
	{
		// For prepass the meshopt_generateProvokingIndexBuffer is used to emulate SV_PrimitiveID via provoking vertex
		PrimitiveID prim;
		prim.init();
		prim.primitiveIndex = vertexID - GetMesh().indexOffset / 3;
		prim.instanceIndex = GetInstancePointer().GetInstanceIndex();
		prim.subsetIndex = push.geometryIndex - GetInstance().geometryOffset;
		return prim.pack(GetInstance(), GetMesh());
	}
#endif // OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER

	uint GetVertexID()
	{
#ifdef OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER
		// For prepass the meshopt_generateProvokingIndexBuffer is used to emulate SV_PrimitiveID via provoking vertex
		return bindless_buffers_uint[descriptor_index(GetMesh().ib_reorder)][vertexID];
#else
		return vertexID;
#endif // OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER
	}

	float4 GetPositionWind()
	{
		return bindless_buffers_float4[descriptor_index(GetMesh().vb_pos_wind)][GetVertexID()];
	}

	float4 GetUVSets()
	{
		[branch]
		if (GetMesh().vb_uvs < 0)
			return 0;
		return lerp(GetMesh().uv_range_min.xyxy, GetMesh().uv_range_max.xyxy, bindless_buffers_float4[descriptor_index(GetMesh().vb_uvs)][GetVertexID()]);
	}

	ShaderMeshInstancePointer GetInstancePointer()
	{
		if (push.instances >= 0)
			return bindless_buffers[descriptor_index(push.instances)].Load<ShaderMeshInstancePointer>(push.instance_offset + instanceID * sizeof(ShaderMeshInstancePointer));

		ShaderMeshInstancePointer poi;
		poi.init();
		return poi;
	}

	float2 GetAtlasUV()
	{
		[branch]
		if (GetMesh().vb_atl < 0)
			return 0;
		return bindless_buffers_float2[descriptor_index(GetMesh().vb_atl)][GetVertexID()];
	}

	half4 GetVertexColor()
	{
		[branch]
		if (GetMesh().vb_col < 0)
			return 1;
		return bindless_buffers_half4[descriptor_index(GetMesh().vb_col)][GetVertexID()];
	}
	
	float3 GetNormal()
	{
		[branch]
		if (GetMesh().vb_nor < 0)
			return 0;
		return bindless_buffers_float4[descriptor_index(GetMesh().vb_nor)][GetVertexID()].xyz;
	}

	float4 GetTangent()
	{
		[branch]
		if (GetMesh().vb_tan < 0)
			return 0;
		return bindless_buffers_float4[descriptor_index(GetMesh().vb_tan)][GetVertexID()];
	}

	ShaderMeshInstance GetInstance()
	{
		if (push.instances >= 0)
			return load_instance(GetInstancePointer().GetInstanceIndex());

		ShaderMeshInstance inst;
		inst.init();
		return inst;
	}

	half GetVertexAO()
	{
		[branch]
		if (GetInstance().vb_ao < 0)
			return 1;
		return bindless_buffers_half[NonUniformResourceIndex(descriptor_index(GetInstance().vb_ao))][GetVertexID()];
	}

	half GetWetmap()
	{
		//[branch]
		//if (GetInstance().vb_wetmap < 0)
		//	return 0;
		//return bindless_buffers_half[NonUniformResourceIndex(descriptor_index(GetInstance().vb_wetmap))][GetVertexID()];

		// There is something seriously bad with AMD driver's shader compiler as the above commented version works incorrectly and this works correctly but only for wetmap
		[branch]
		if (GetInstance().vb_wetmap >= 0)
			return bindless_buffers_half[NonUniformResourceIndex(descriptor_index(GetInstance().vb_wetmap))][GetVertexID()];
		return 0;
	}
};


struct VertexSurface
{
	float4 position;
	float4 uvsets;
	float2 atlas;
	half4 color;
	float3 normal;
	float4 tangent;
	half ao;
	half wet;
	half block_light;

	inline void create(in ShaderMaterial material, in VertexInput input)
	{
		ShaderMeshInstance inst = input.GetInstance();
		float4 pos_wind = input.GetPositionWind();
		position = float4(pos_wind.xyz, 1);
		color = half4(material.GetBaseColor() * inst.GetColor());

		block_light = 0;
		[branch]
		if (material.IsUsingVertexColors() || material.IsBlockLight())
		{
			half4 vertex_color = input.GetVertexColor();
			[branch]
			if (material.IsBlockLight())
			{
				// The alpha is the light level of the vertex (MaterialComponent::SetBlockLight()):
				block_light = vertex_color.a;
				vertex_color.a = 1;
			}
			[branch]
			if (material.IsUsingVertexColors())
			{
				color *= vertex_color;
			}
		}

		[branch]
		if (!material.IsTransparent())
		{
			color.a = 1;
		}

		color.a *= half(1 - input.GetInstancePointer().GetDither());

		[branch]
		if (material.IsUsingVertexAO())
		{
			ao = input.GetVertexAO();
		}
		else
		{
			ao = 1;
		}

		float3x3 adjoint = inst.transformRaw.GetMatrixAdjoint();
		normal = input.GetNormal();
		normal = mul(adjoint, normal);
		normal = any(normal) ? normalize(normal) : 0;

		tangent = input.GetTangent();
		tangent.xyz = mul(adjoint, tangent.xyz);
		tangent.xyz = any(tangent.xyz) ? normalize(tangent.xyz) : 0;
		
		uvsets = input.GetUVSets();
		uvsets.xy = mad(uvsets.xy, material.texMulAdd.xy, material.texMulAdd.zw);

		atlas = input.GetAtlasUV();

		position = mul(inst.transform.GetMatrix(), position);

		wet = input.GetWetmap();

#ifndef DISABLE_WIND
		[branch]
		if (material.IsUsingWind())
		{
			position.xyz += sample_wind(position.xyz, pos_wind.w);
		}
#endif // DISABLE_WIND
	}
};

struct PixelInput
{
	precise float4 pos : SV_Position;

#ifdef OBJECTSHADER_COMPILE_PS
	STEREO_VIEWID_FIELD
#endif // OBJECTSHADER_COMPILE_PS

#ifdef OBJECTSHADER_USE_COLOR
	half4 color : COLOR;
#endif // OBJECTSHADER_USE_COLOR
	
#ifndef OBJECTSHADER_COMPILE_MS // Per-primitive params are handled separately by mesh shader
#if defined(OBJECTSHADER_USE_INSTANCEINDEX) || defined(OBJECTSHADER_USE_DITHERING) || defined(OBJECTSHADER_USE_CAMERAINDEX)
	uint poi : INSTANCEPOINTER;
#endif // OBJECTSHADER_USE_INSTANCEINDEX || OBJECTSHADER_USE_DITHERING || OBJECTSHADER_USE_CAMERAINDEX

#if defined(PREPASS)
	uint primitiveID : PRIMITIVEID;
#endif // defined(PREPASS)
#endif // OBJECTSHADER_COMPILE_MS

#ifdef OBJECTSHADER_USE_COMMON
	float2 atl : ATLAS;
	half3 ao_wet : COMMON; // z: the block light, see MaterialComponent::SetBlockLight()
#endif // OBJECTSHADER_USE_COMMON

#ifdef OBJECTSHADER_USE_UVSETS
	float4 uvsets : UVSETS;
#endif // OBJECTSHADER_USE_UVSETS

#ifdef OBJECTSHADER_USE_TANGENT
	float4 tan : TANGENT;
#endif // OBJECTSHADER_USE_TANGENT

// Reminder: NORMAL is used by all tessellation shaders for PN-triangle smoothing, but it will be stripped from pixel shader in prepass, so anything that will be needed in
//	both tessellation and pixel shaders can not be put after NORMAL!
#ifdef OBJECTSHADER_USE_NORMAL
	float3 nor : NORMAL;
#endif // OBJECTSHADER_USE_NORMAL

// Reminder: SV_ClipDistance0 is not required in pixel shader, so it can be stripped out even though it is still used by rasterizer
#ifndef OBJECTSHADER_COMPILE_PS
#ifdef OBJECTSHADER_USE_CLIPPLANE
	float clip : SV_ClipDistance0;
#endif // OBJECTSHADER_USE_CLIPPLANE
#endif // OBJECTSHADER_COMPILE_PS

#ifndef OBJECTSHADER_COMPILE_MS // Per-primitive params are handled separately by mesh shader
#ifndef OBJECTSHADER_COMPILE_PS
#ifdef OBJECTSHADER_USE_RENDERTARGETARRAYINDEX
	uint RTIndex : SV_RenderTargetArrayIndex;
#endif // OBJECTSHADER_USE_RENDERTARGETARRAYINDEX
#ifdef OBJECTSHADER_USE_VIEWPORTARRAYINDEX
	uint VPIndex : SV_ViewportArrayIndex;
#endif // OBJECTSHADER_USE_VIEWPORTARRAYINDEX
#endif // OBJECTSHADER_COMPILE_PS

#ifdef OBJECTSHADER_USE_INSTANCEINDEX
	inline uint GetInstanceIndex()
	{
		ShaderMeshInstancePointer pointer;
		pointer.data = poi;
		return pointer.GetInstanceIndex();
	}
#endif // OBJECTSHADER_USE_INSTANCEINDEX

#ifdef OBJECTSHADER_USE_DITHERING
	inline half GetDither()
	{
		ShaderMeshInstancePointer pointer;
		pointer.data = poi;
		return pointer.GetDither();
	}
#endif // OBJECTSHADER_USE_DITHERING

	inline uint GetCameraIndex()
	{
#ifdef OBJECTSHADER_USE_CAMERAINDEX
		ShaderMeshInstancePointer pointer;
		pointer.data = poi;
		return pointer.GetCameraIndex();
#else
		return g_xCameraIndex;
#endif // OBJECTSHADER_USE_CAMERAINDEX
	}
	
#ifdef OBJECTSHADER_USE_UVSETS
	inline float4 GetUVSets()
	{
		return uvsets;
	}
#endif // OBJECTSHADER_USE_UVSETS

	inline float3 GetPos3D()
	{
		ShaderCamera camera = GetCameraIndexed(GetCameraIndex());
		return camera.screen_to_world(pos);
	}

	inline float3 GetViewVector()
	{
		ShaderCamera camera = GetCameraIndexed(GetCameraIndex());
		return camera.screen_to_view(pos);
	}

#endif // OBJECTSHADER_COMPILE_MS
};

PixelInput vertex_to_pixel_export(VertexInput input)
{
	STEREO_VIEWID_APPLY(input.stereo_view_id);
	ShaderMaterial material = GetMaterial();

	VertexSurface surface;
	surface.create(material, input);

	PixelInput Out;
	
	Out.pos = surface.position;

#ifdef OBJECTSHADER_USE_CAMERAINDEX
	ShaderCamera camera = GetCameraIndexed(input.GetInstancePointer().GetCameraIndex());
#else
	ShaderCamera camera = GetCamera();
#endif // OBJECTSHADER_USE_CAMERAINDEX

#ifndef OBJECTSHADER_USE_NOCAMERA
	Out.pos = mul(camera.view_projection, Out.pos);
#endif // OBJECTSHADER_USE_NOCAMERA

#ifndef OBJECTSHADER_COMPILE_PS
#ifdef OBJECTSHADER_USE_CLIPPLANE
	Out.clip = dot(surface.position, camera.clip_plane);
#endif // OBJECTSHADER_USE_CLIPPLANE
#endif // OBJECTSHADER_COMPILE_PS

#ifdef OBJECTSHADER_USE_COLOR
	Out.color = surface.color;
#endif // OBJECTSHADER_USE_COLOR

#ifdef OBJECTSHADER_USE_UVSETS
	Out.uvsets = surface.uvsets;
#endif // OBJECTSHADER_USE_UVSETS

#ifdef OBJECTSHADER_USE_NORMAL
	Out.nor = surface.normal;
#endif // OBJECTSHADER_USE_NORMAL

#ifdef OBJECTSHADER_USE_COMMON
	Out.atl = surface.atlas;
	Out.ao_wet = half3(surface.ao, surface.wet, surface.block_light);
#endif // OBJECTSHADER_USE_COMMON

#ifdef OBJECTSHADER_USE_TANGENT
	Out.tan = surface.tangent;
#endif // OBJECTSHADER_USE_TANGENT

// Per-primitive attribute export can go below here (excluded in mesh shaders)

#ifndef OBJECTSHADER_COMPILE_MS

#if defined(OBJECTSHADER_USE_INSTANCEINDEX) || defined(OBJECTSHADER_USE_DITHERING) || defined(OBJECTSHADER_USE_CAMERAINDEX)
	Out.poi = input.GetInstancePointer().data;
#endif // OBJECTSHADER_USE_INSTANCEINDEX || OBJECTSHADER_USE_DITHERING || OBJECTSHADER_USE_CAMERAINDEX
	
#if defined(PREPASS) && defined(OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER)
	Out.primitiveID = input.GetPrimitiveID();
#endif // defined(PREPASS) && defined(OBJECTSHADER_USE_PROVOKING_INDEX_BUFFER)

#if !defined(OBJECTSHADER_COMPILE_PS)
#ifdef OBJECTSHADER_USE_RENDERTARGETARRAYINDEX
	Out.RTIndex = input.GetInstancePointer().GetCameraIndex();
#endif // OBJECTSHADER_USE_RENDERTARGETARRAYINDEX
#ifdef OBJECTSHADER_USE_VIEWPORTARRAYINDEX
	Out.VPIndex = input.GetInstancePointer().GetCameraIndex();
#endif // OBJECTSHADER_USE_VIEWPORTARRAYINDEX
#endif // !defined(OBJECTSHADER_COMPILE_PS)

#endif // OBJECTSHADER_COMPILE_MS

	return Out;
}


// OBJECT SHADER PROTOTYPE
///////////////////////////

#ifdef OBJECTSHADER_COMPILE_VS

// Vertex shader base:
PixelInput main(VertexInput input)
{
	return vertex_to_pixel_export(input);
}

#endif // OBJECTSHADER_COMPILE_VS


#ifdef OBJECTSHADER_COMPILE_PS

// Possible switches:
//	PREPASS				-	assemble object shader for depth prepass rendering
//	DEPTHONLY			-	assemble object shader for depth prepass rendering with no return
//	TRANSPARENT			-	assemble object shader for tiled forward transparent rendering
//	ENVMAPRENDERING		-	modify object shader for envmap rendering
//	PLANARREFLECTION	-	include planar reflection sampling
//	PARALLAXOCCLUSIONMAPPING					-	include parallax occlusion mapping computation
//	WATER				-	include specialized water shader code
//  ... and other material type specific defines

// The second uv set can hold the distances in meters to the edges of a flat surface along the two directions of the face,
//	see MaterialComponent::SetParallaxEdgeFade() and SetEdgeBevel(). Inner edges are marked with an offset:
static const float EDGE_BEVEL_CONCAVE_OFFSET = 32;
inline float2 IsEdgeConcave(float2 encoded)
{
	return step(EDGE_BEVEL_CONCAVE_OFFSET * 0.75, encoded);
}
inline float2 DecodeEdgeDistance(float2 encoded)
{
	return encoded - IsEdgeConcave(encoded) * EDGE_BEVEL_CONCAVE_OFFSET;
}

// Bends the normal of a flat surface towards its outer edges, as if the edges were rounded with a circle
//	(MaterialComponent::SetEdgeBevel()), the outline of the mesh stays sharp:
//	The angle grows linearly from 0 at the given width to 45 degrees at the edge, where it meets the bent normal of the
//	other face of the edge, so the light goes around the edge without a break. At a corner both directions add up.
//	Inner edges are not rounded. The directions to the edges come from the screen derivatives, so the faces don't have
//	to be aligned to any axis.
float3 EdgeBevelNormal(float3 N, float3 P, float2 encoded, float width)
{
	const float2 distance = DecodeEdgeDistance(encoded);
	const float2 convex = 1 - IsEdgeConcave(encoded);
	const float3 P_dx = ddx(P);
	const float3 P_dy = ddy(P);
	const float2 distance_dx = ddx(distance);
	const float2 distance_dy = ddy(distance);

	float2 amount = saturate(1 - distance / width) * convex;
	// Thinner than a few pixels the rounding would only flicker in the highlights:
	const float2 meters_per_pixel = max(sqrt(distance_dx * distance_dx + distance_dy * distance_dy), 1e-6);
	amount *= saturate(width / meters_per_pixel * 0.5 - 0.5);
	[branch]
	if (!any(amount > 0))
		return N;

	// The gradients of the distances along the surface point away from the edges:
	const float3 r1 = cross(P_dy, N);
	const float3 r2 = cross(N, P_dx);
	const float det = dot(P_dx, r1);
	if (abs(det) < 1e-20)
		return N;
	const float3 gradient_u = (distance_dx.x * r1 + distance_dy.x * r2) / det;
	const float3 gradient_v = (distance_dx.y * r1 + distance_dy.y * r2) / det;
	const float3 to_edge_u = -gradient_u / max(length(gradient_u), 1e-6);
	const float3 to_edge_v = -gradient_v / max(length(gradient_v), 1e-6);

	const float2 bend = tan(amount * (PI * 0.25));
	return normalize(N + to_edge_u * bend.x + to_edge_v * bend.y);
}

// The second layer of a flowing surface (MaterialComponent::SetFlow()): smaller, turned and moving the other way with the
//	animation offset texMulAdd.w, against the first layer that moves with texMulAdd.zw
inline float4 GetFlowUVSets(ShaderMaterial material, float4 uvsets)
{
	const float2 base = uvsets.xy - material.texMulAdd.zw;
	return float4(float2(base.y, -base.x) * 0.79 + float2(0.37, 0.61) - material.texMulAdd.ww * float2(0.7, -1.1), uvsets.zw);
}

// How near a point is to the border between the cells of a pattern of wandering points (one in each unit square), 0 on
//	the border
inline float CausticCellBorder(float2 p, float t)
{
	const float2 cell = floor(p);
	const float2 f = p - cell;
	float nearest = 8, second = 8;
	[unroll]
	for (int y = -1; y <= 1; ++y)
	{
		[unroll]
		for (int x = -1; x <= 1; ++x)
		{
			const int2 c = int2(cell) + int2(x, y);
			uint h = uint(c.x) * 0x8da6b343u ^ uint(c.y) * 0xd8163841u;
			h = (h ^ (h >> 15)) * 0x2c1b3c6du;
			h ^= h >> 12;
			const float2 random = float2(h & 0xFFFF, h >> 16) / 65535.0;
			const float2 center = float2(x, y) + 0.5 + 0.38 * sin(t * (0.6 + 0.5 * random.yx) + 6.2832 * random);
			const float d = length(center - f);
			second = d < nearest ? nearest : min(second, d);
			nearest = min(nearest, d);
		}
	}
	return second - nearest;
}

// The light of the sun focused by the waves on the ground under water: organic wandering light filaments generated from
//	domain-warped wave interference across two drifting scales, 0 to 1
inline half WaterCaustics(float2 p, float t)
{
	const float2 warp =
		float2(sin(p.y * 2.3 + t * 1.15), cos(p.x * 2.1 - t * 0.95)) * 0.14 +
		float2(cos((p.x + p.y) * 3.6 - t * 1.7), sin((p.x - p.y) * 3.4 + t * 1.5)) * 0.06;
	const float2 wp = p + warp;
	const float a = CausticCellBorder(wp * 2.9, t * 0.95);
	const float b = CausticCellBorder(float2(wp.y, -wp.x) * 2.1 + 7.3 - warp * 0.6, t * 0.72);
	const float filA = pow(smoothstep(0.32, 0.0, a), 2.2);
	const float filB = pow(smoothstep(0.34, 0.0, b), 2.2);
	return (half)saturate(filA * 0.78 + filB * 0.58 + filA * filB * 0.35);
}

#if defined(__PSSL__) && defined(PREPASS) && !defined(DEPTHONLY)
#pragma PSSL_target_output_format (target 0 FMT_32_R)
#endif // __PSSL__ && PREPASS

#ifdef DISABLE_ALPHATEST
#define APPEND_COVERAGE_OUTPUT
#else
#define APPEND_COVERAGE_OUTPUT , out uint coverage : SV_Coverage
#endif // DISABLE_ALPHATEST

#ifdef EARLY_DEPTH_STENCIL
[earlydepthstencil]
#endif // EARLY_DEPTH_STENCIL

// entry point:
#ifdef PREPASS
#ifdef DEPTHONLY
void main(PixelInput input APPEND_COVERAGE_OUTPUT)
#else
uint main(PixelInput input APPEND_COVERAGE_OUTPUT) : SV_Target
#endif // DEPTHONLY
#else
float4 main(PixelInput input, in bool is_frontface : SV_IsFrontFace APPEND_COVERAGE_OUTPUT) : SV_Target
#endif // PREPASS


// Pixel shader base:
{
#ifdef OBJECTSHADER_USE_CAMERAINDEX
	const uint cameraIndex = WaveReadLaneFirst(input.GetCameraIndex()); // scalarized camera index assumes that wave from two cameras will not be packed together, this simplifies camera resource indexing significantly
#else
	STEREO_VIEWID_APPLY(input.stereo_view_id);
	const uint cameraIndex = g_xCameraIndex;
#endif // OBJECTSHADER_USE_CAMERAINDEX

	ShaderCamera camera = GetCameraIndexed(cameraIndex);

	const min16uint2 pixel = input.pos.xy; // no longer pixel center!
	const float2 ScreenCoord = input.pos.xy * camera.internal_resolution_rcp; // use pixel center!
	
	Surface surface;
	surface.init();
	surface.P = input.GetPos3D();
	surface.V = input.GetViewVector();
	float dist = length(surface.V);
	surface.V /= dist;
	
#ifdef OBJECTSHADER_USE_UVSETS
	float4 uvsets = input.GetUVSets();
	const float2 edge_encoded = uvsets.zw; // before parallax mapping shifts the uv sets
#endif // OBJECTSHADER_USE_UVSETS

#ifdef TILEDFORWARD
	write_mipmap_feedback(push.materialIndex, ddx_coarse(uvsets), ddy_coarse(uvsets));
#endif // TILEDFORWARD

#ifdef OBJECTSHADER_USE_INSTANCEINDEX
	ShaderMeshInstance meshinstance = load_instance(input.GetInstanceIndex());
#endif // OBJECTSHADER_USE_INSTANCEINDEX

	ShaderMaterial material = GetMaterial();


#ifdef OBJECTSHADER_USE_NORMAL
#if !defined(PREPASS) && !defined(DEPTHONLY)
	if (is_frontface == false)
	{
		input.nor = -input.nor;
	}
#endif // !defined(PREPASS) && !defined(DEPTHONLY)
	surface.N = normalize(input.nor);
	surface.facenormal = surface.N;
#endif // OBJECTSHADER_USE_NORMAL

#ifdef OBJECTSHADER_USE_COMMON
	surface.occlusion = input.ao_wet.x;
#endif // OBJECTSHADER_USE_COMMON

#ifdef OBJECTSHADER_USE_TANGENT
	surface.T = input.tan;
	surface.T.w = surface.T.w < 0 ? -1 : 1;
	half3 bitangent = cross(surface.T.xyz, input.nor) * surface.T.w;
	float3x3 TBN = float3x3(surface.T.xyz, bitangent, input.nor); // unnormalized TBN! http://www.mikktspace.com/
	
	surface.T.xyz = normalize(surface.T.xyz);

#ifdef PARALLAXOCCLUSIONMAPPING
	[branch]
	if (material.textures[DISPLACEMENTMAP].IsValid())
	{
		Texture2D<half4> tex = bindless_textures_half4[descriptor_index(material.textures[DISPLACEMENTMAP].texture_descriptor)];
		float2 uv = material.textures[DISPLACEMENTMAP].GetUVSet() == 0 ? uvsets.xy : uvsets.zw;
		float2 uv_dx = ddx_coarse(uv);
		float2 uv_dy = ddy_coarse(uv);

		half parallax_strength = material.GetParallaxOcclusionMapping();
		if (material.IsParallaxEdgeFade() && material.IsEdgeBevel())
		{
			// Unchamfered blocks (IsEdgeBevel) fade parallax over 12 cm from sharp 90-degree edges so the shifted
			//	texture doesn't clash across a razor edge. Chamfered blocks (!IsEdgeBevel) keep full parallax relief
			//	all the way across the smooth bevel:
			static const half PARALLAX_EDGE_FADE_DISTANCE = 0.12;
			const float2 edge_distance = DecodeEdgeDistance(edge_encoded);
			const float edge_min = min(edge_distance.x, edge_distance.y);
			parallax_strength *= smoothstep(0, 1, saturate(edge_min / PARALLAX_EDGE_FADE_DISTANCE));
		}
		// Far away the relief is smaller than a pixel, there the steps through the height map are left out (a large part
		//	of the cost of the parallax mapping in a big resolution, like the eyes of a headset):
		static const float PARALLAX_FADE_START = 10;
		static const float PARALLAX_FADE_END = 16;
		parallax_strength *= (half)saturate((PARALLAX_FADE_END - dist) / (PARALLAX_FADE_END - PARALLAX_FADE_START));

		ParallaxOcclusionMapping_Impl(
			uvsets,
			surface.V,
			TBN,
			parallax_strength,
			tex,
			uv,
			uv_dx,
			uv_dy
		);
	}
#endif // PARALLAXOCCLUSIONMAPPING

#endif // OBJECTSHADER_USE_TANGENT


#ifdef OBJECTSHADER_USE_UVSETS

#ifndef INTERIORMAPPING
	[branch]
#ifdef PREPASS
	if (material.textures[BASECOLORMAP].IsValid())
#else
	if (material.textures[BASECOLORMAP].IsValid() && (GetFrame().options & OPTION_BIT_DISABLE_ALBEDO_MAPS) == 0)
#endif // PREPASS
	{
		half4 base_map = material.textures[BASECOLORMAP].Sample(sampler_objectshader, uvsets);
		[branch]
		if (material.IsFlow())
		{
			base_map = max(base_map, material.textures[BASECOLORMAP].Sample(sampler_objectshader, GetFlowUVSets(material, uvsets)));
		}
		surface.baseColor *= base_map;
	}
#endif // INTERIORMAPPING
	
#if defined(PREPASS) || defined(TRANSPARENT)
	[branch]
	if (material.textures[TRANSPARENCYMAP].IsValid())
	{
		surface.baseColor.a *= material.textures[TRANSPARENCYMAP].Sample(sampler_objectshader, uvsets).r;
	}
#endif // PREPASS || TRANSPARENT

#endif // OBJECTSHADER_USE_UVSETS


#ifdef OBJECTSHADER_USE_COLOR
	surface.baseColor *= input.color;
#endif // OBJECTSHADER_USE_COLOR


#ifndef WATER
#ifdef OBJECTSHADER_USE_TANGENT
	[branch]
	if (material.textures[NORMALMAP].IsValid())
	{
		half2 bump_map = material.textures[NORMALMAP].Sample(sampler_objectshader, uvsets).rg;
		[branch]
		if (material.IsFlow())
		{
			bump_map = (bump_map + material.textures[NORMALMAP].Sample(sampler_objectshader, GetFlowUVSets(material, uvsets)).rg) * 0.5;
		}
		surface.bumpColor = half3(bump_map, 1);
		surface.bumpColor = surface.bumpColor * 2 - 1;
		// Normal maps use OpenGL convention (+G = up / -v), whereas TBN bitangent points along +dP/dv (down, required by POM):
		surface.bumpColor.g = -surface.bumpColor.g;
		surface.bumpColor.rg *= material.GetNormalMapStrength();
	}
#endif // OBJECTSHADER_USE_TANGENT
#endif // WATER

	surface.layerMask = material.layerMask & meshinstance.layerMask;


	half4 surfaceMap = 1;
#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (material.textures[SURFACEMAP].IsValid())
	{
		surfaceMap = material.textures[SURFACEMAP].Sample(sampler_objectshader, uvsets);
	}
#endif // OBJECTSHADER_USE_UVSETS

#ifdef OBJECTSHADER_USE_EMISSIVE
	// Emissive map:
	surface.emissiveColor = material.GetEmissive();

#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (any(surface.emissiveColor) && material.textures[EMISSIVEMAP].IsValid())
	{
		half4 emissiveMap = material.textures[EMISSIVEMAP].Sample(sampler_objectshader, uvsets);
		[branch]
		if (material.IsFlow())
		{
			emissiveMap = max(emissiveMap, material.textures[EMISSIVEMAP].Sample(sampler_objectshader, GetFlowUVSets(material, uvsets)));
		}
		if (material.IsSparkle())
		{
			surface.emissiveColor *= SparkleEmissive(emissiveMap, surface.V);
		}
		else
		{
			surface.emissiveColor *= emissiveMap.rgb * emissiveMap.a;
		}
	}
#endif // OBJECTSHADER_USE_UVSETS

	surface.emissiveColor *= meshinstance.GetEmissive();
#endif // OBJECTSHADER_USE_EMISSIVE

#ifdef OBJECTSHADER_USE_UVSETS
#ifdef TERRAINBLENDED
	[branch]
	if (material.GetTerrainBlendRcp() > 0)
	{
		// Blend object into terrain material:
		ShaderTerrain terrain = GetScene().terrain;
		[branch]
		if(terrain.chunk_buffer >= 0)
		{
			int2 chunk_coord = floor((surface.P.xz - terrain.center_chunk_pos.xz) / terrain.chunk_size);
			if(chunk_coord.x >= -terrain.chunk_buffer_range && chunk_coord.x <= terrain.chunk_buffer_range && chunk_coord.y >= -terrain.chunk_buffer_range && chunk_coord.y <= terrain.chunk_buffer_range)
			{
				uint chunk_idx = flatten2D(chunk_coord + terrain.chunk_buffer_range, terrain.chunk_buffer_range * 2 + 1);
				ShaderTerrainChunk chunk = bindless_structured_terrain_chunks[descriptor_index(terrain.chunk_buffer)][chunk_idx];
				
				[branch]
				if(chunk.heightmap >= 0)
				{
					Texture2D terrain_heightmap = bindless_textures[NonUniformResourceIndex(descriptor_index(chunk.heightmap))];
					float2 chunk_min = terrain.center_chunk_pos.xz + chunk_coord * terrain.chunk_size;
					float2 chunk_max = terrain.center_chunk_pos.xz + terrain.chunk_size + chunk_coord * terrain.chunk_size;
					float2 terrain_uv = saturate(inverse_lerp(chunk_min, chunk_max, surface.P.xz));
					float terrain_height0 = terrain_heightmap.SampleLevel(sampler_linear_clamp, terrain_uv, 0).r;
					float terrain_height1 = terrain_heightmap.SampleLevel(sampler_linear_clamp, terrain_uv, 0, int2(1, 0)).r;
					float terrain_height2 = terrain_heightmap.SampleLevel(sampler_linear_clamp, terrain_uv, 0, int2(0, 1)).r;
					float3 P0 = float3(0, terrain_height0, 0); 
					float3 P1 = float3(1, terrain_height1, 0); 
					float3 P2 = float3(0, terrain_height2, 1);
					float3 terrain_normal = normalize(cross(P2 - P0, P1 - P0));
					float terrain_height = lerp(terrain.min_height, terrain.max_height, terrain_height0);
					float object_height = surface.P.y;
					float diff = (object_height - terrain_height) * material.GetTerrainBlendRcp();
					float blend = 1 - sqr(saturate(diff));
					//blend *= lerp(1, saturate((noise_gradient_3D(surface.P * 2) * 0.5 + 0.5) * 2), saturate(diff));
					//terrain_uv = lerp(saturate(inverse_lerp(chunk_min, chunk_max, surface.P.xz - surface.N.xz * diff)), terrain_uv, saturate(surface.N.y)); // uv stretching improvement: stretch in normal direction if normal gets horizontal
					ShaderMaterial terrain_material = load_material(chunk.materialID);
					terrain_uv = mad(terrain_uv, terrain_material.texMulAdd.xy, terrain_material.texMulAdd.zw);
					float4 terrain_baseColor = terrain_material.textures[BASECOLORMAP].Sample(sampler_objectshader, terrain_uv.xyxy);
					float4 terrain_bumpColor = terrain_material.textures[NORMALMAP].Sample(sampler_objectshader, terrain_uv.xyxy);
					float4 terrain_surfaceMap = terrain_material.textures[SURFACEMAP].Sample(sampler_objectshader, terrain_uv.xyxy);
					float3 terrain_emissiveMap = terrain_material.textures[EMISSIVEMAP].Sample(sampler_objectshader, terrain_uv.xyxy).rgb;
					surface.baseColor = lerp(surface.baseColor, terrain_baseColor, blend);
					surface.bumpColor = lerp(surface.bumpColor, terrain_bumpColor.rgb * 2 - 1, blend);
					surfaceMap = lerp(surfaceMap, terrain_surfaceMap, blend);
					surface.emissiveColor += terrain_emissiveMap * terrain_material.GetEmissive() * blend;
					input.nor = lerp(input.nor, terrain_normal, blend);
					TBN[2] = input.nor;
					surface.N = normalize(input.nor);
				}
			}
		}
	}
#endif // TERRAINBLENDED
#endif // OBJECTSHADER_USE_UVSETS

	[branch]
	if (!material.IsUsingSpecularGlossinessWorkflow())
	{
		// Premultiply these before evaluating decals:
		surfaceMap.g *= material.GetRoughness();
		surfaceMap.b *= material.GetMetalness();
		surfaceMap.a *= material.GetReflectance();
	}

#ifdef TILEDFORWARD
	const uint flat_tile_index = GetFlatTileIndex(pixel, camera);
#endif // TILEDFORWARD

#ifndef PREPASS
#ifndef WATER
#ifdef TILEDFORWARD
	TiledDecals(surface, surfaceMap, sampler_objectshader, flat_tile_index, camera);
#endif // TILEDFORWARD
#endif // WATER
#endif // PREPASS


#ifndef WATER
#if defined(OBJECTSHADER_USE_UVSETS) && defined(OBJECTSHADER_USE_NORMAL)
	[branch]
	if (material.IsEdgeBevel())
	{
		surface.N = EdgeBevelNormal(surface.N, surface.P, edge_encoded, material.GetEdgeBevel());
#ifdef OBJECTSHADER_USE_TANGENT
		// The normal map is applied on the rounded surface:
		TBN[2] = surface.N;
		TBN[0] -= surface.N * dot(TBN[0], surface.N);
		TBN[1] -= surface.N * dot(TBN[1], surface.N);
#endif // OBJECTSHADER_USE_TANGENT
	}
#endif // OBJECTSHADER_USE_UVSETS && OBJECTSHADER_USE_NORMAL
#ifdef OBJECTSHADER_USE_TANGENT
	[branch]
	if (any(surface.bumpColor))
	{
		surface.N = normalize(mul(surface.bumpColor, TBN));
	}
#endif // OBJECTSHADER_USE_TANGENT
#endif // WATER


	half4 specularMap = 1;

#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (material.textures[SPECULARMAP].IsValid())
	{
		specularMap = material.textures[SPECULARMAP].Sample(sampler_objectshader, uvsets);
	}
#endif // OBJECTSHADER_USE_UVSETS


	surface.create(material, surface.baseColor, surfaceMap, specularMap);
	
	

#ifdef OBJECTSHADER_USE_COMMON
	half wet = input.ao_wet.y;
	if (wet > 0)
	{
		surface.albedo = lerp(surface.albedo, 0, wet); // darken color when wet
		surface.roughness = clamp(surface.roughness * saturate(sqr((1 - wet) * 2 - 1)), 0.01, 1); // decrease eoughness when wet, but only at shoreline, not deeper underwater (sand underwater shouldn't be shiny)
		surface.f0 = lerp(surface.f0, 0, wet); // decrease reflectance when wet (not shiny when fully underwater)
		surface.N = normalize(lerp(surface.N, input.nor, wet)); // blend to vertex normal when wet
	}

	// Under water (MaterialComponent::SetRainWetness() with 32768 added to the code in the atlas uv y): the x is how much of
	//	the light of the sun reaches the vertex through the water, it gets the caustics below, and no rain:
	half caustics_weight = 0;
	bool under_water = false;
	[branch]
	if (material.IsRainWetness())
	{
		under_water = round(saturate(input.atl.y) * 65535.0) >= 32768;
		caustics_weight = under_water ? (half)saturate(input.atl.x) : 0;
	}

	// Rain on the surface (MaterialComponent::SetRainWetness()): the atlas uv tells how much rain reaches the vertex (x)
	//	and how the surface reacts to it (y, a 16 bit code: film * 100 + darkening, both in percent). It gets darker, and
	//	the water film makes it smooth and fills the small bumps:
	[branch]
	if (material.IsRainWetness() && GetWeather().rain_wetness > 0 && !under_water)
	{
		const half rain_wet = (half)saturate(input.atl.x) * (half)GetWeather().rain_wetness;
		const uint code = (uint)round(saturate(input.atl.y) * 65535.0);
		const half darkening = (half)(code % 100) * 0.01;
		const half film_strength = (half)min(code / 100, 100) * 0.01;
		// Surfaces that soak up water (darkening over 30 %, earth and stone) are damp with a thin film, and in patches fixed
		//	in the world on level tops the water stands in puddles with the full film. Leaves and grass have an even film.
		//	A medium film everywhere made the ground pale from the sky:
		half film = film_strength;
		[branch]
		if (darkening > 0.3)
		{
			const half patches = (half)saturate(noise_gradient_3D(surface.P * 0.7) * 1.2 + 0.5);
			const half level = (half)saturate(input.nor.y * 4 - 3);
			// A sharp border: between damp and puddle the roughness passes the medium range, which reflects the bright sky
			//	widely and showed as light outlines around the puddles:
			const half puddle = smoothstep(0.6, 0.62, patches) * level;
			film = film_strength * lerp(0.4, 2.0, puddle);
		}
		film = saturate(film) * rain_wet;
		surface.albedo *= 1.0 - darkening * rain_wet;
		surface.roughness = lerp(surface.roughness, 0.08, film);
		// The vertex normal turned to the side that is seen (double sided leaves and grass flip the shading normal):
		float3 flat_normal = input.nor;
		flat_normal = dot(flat_normal, surface.N) < 0 ? -flat_normal : flat_normal;
		surface.N = normalize(lerp(surface.N, flat_normal, film * 0.3));
	}
#endif // OBJECTSHADER_USE_COMMON


#ifdef OBJECTSHADER_USE_UVSETS
	// Secondary occlusion map:
	[branch]
	if (material.IsOcclusionEnabled_Secondary() && material.textures[OCCLUSIONMAP].IsValid())
	{
		surface.occlusion *= material.textures[OCCLUSIONMAP].Sample(sampler_objectshader, uvsets).r;
	}
#endif // OBJECTSHADER_USE_UVSETS


#ifdef ANISOTROPIC
	surface.aniso.strength = material.GetAnisotropy();
	surface.aniso.direction = half2(material.GetAnisotropyCos(), material.GetAnisotropySin());

#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (material.textures[ANISOTROPYMAP].IsValid())
	{
		half2 anisotropyTexture = material.textures[ANISOTROPYMAP].Sample(sampler_objectshader, uvsets).rg * 2 - 1;
		surface.aniso.strength *= length(anisotropyTexture);
		surface.aniso.direction = mul(half2x2(surface.aniso.direction.x, surface.aniso.direction.y, -surface.aniso.direction.y, surface.aniso.direction.x), normalize(anisotropyTexture));
	}
#endif // OBJECTSHADER_USE_UVSETS

	surface.aniso.T = normalize(mul(TBN, half3(surface.aniso.direction, 0)));

#endif // ANISOTROPIC


#ifdef SHEEN
	surface.sheen.color = material.GetSheenColor();
	surface.sheen.roughness = material.GetSheenRoughness();

#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (material.textures[SHEENCOLORMAP].IsValid())
	{
		surface.sheen.color *= material.textures[SHEENCOLORMAP].Sample(sampler_objectshader, uvsets).rgb;
	}
	[branch]
	if (material.textures[SHEENROUGHNESSMAP].IsValid())
	{
		surface.sheen.roughness *= material.textures[SHEENROUGHNESSMAP].Sample(sampler_objectshader, uvsets).a;
	}
#endif // OBJECTSHADER_USE_UVSETS
#endif // SHEEN


#ifdef CLEARCOAT
	surface.clearcoat.factor = material.GetClearcoat();
	surface.clearcoat.roughness = material.GetClearcoatRoughness();
	surface.clearcoat.N = input.nor;

#ifdef OBJECTSHADER_USE_UVSETS
	[branch]
	if (material.textures[CLEARCOATMAP].IsValid())
	{
		surface.clearcoat.factor *= material.textures[CLEARCOATMAP].Sample(sampler_objectshader, uvsets).r;
	}
	[branch]
	if (material.textures[CLEARCOATROUGHNESSMAP].IsValid())
	{
		surface.clearcoat.roughness *= material.textures[CLEARCOATROUGHNESSMAP].Sample(sampler_objectshader, uvsets).g;
	}
#ifdef OBJECTSHADER_USE_TANGENT
	[branch]
	if (material.textures[CLEARCOATNORMALMAP].IsValid())
	{
		half3 clearcoatNormalMap = half3(material.textures[CLEARCOATNORMALMAP].Sample(sampler_objectshader, uvsets).rg, 1);
		clearcoatNormalMap = clearcoatNormalMap * 2 - 1;
		clearcoatNormalMap.g = -clearcoatNormalMap.g;
		surface.clearcoat.N = mul(clearcoatNormalMap, TBN);
	}
#endif // OBJECTSHADER_USE_TANGENT

	surface.clearcoat.N = normalize(surface.clearcoat.N);

#endif // OBJECTSHADER_USE_UVSETS
#endif // CLEARCOAT

	surface.sss = material.GetSSS();
	surface.sss_inv = material.GetSSSInverse();

#ifdef WATER
	surface.extinction = material.GetSheenColor().rgb; // Note: sheen color is repurposed as extinction color for water
#endif // WATER

	surface.pixel = pixel;
	surface.screenUV = ScreenCoord;

#if !defined(WATER) && !defined(PREPASS) && !defined(DEPTHONLY)
	{
		// Geometric specular AA: widen roughness on sub-pixel chamfers and distant block edges to eliminate shimmer:
		const float3 dndu = ddx_coarse(surface.N);
		const float3 dndv = ddy_coarse(surface.N);
		const float variance = dot(dndu, dndu) + dot(dndv, dndv);
		const float kernelRoughness2 = min(2.0 * variance, 0.18);
		surface.roughness = (half)sqrt(saturate((float)surface.roughness * (float)surface.roughness + kernelRoughness2));
	}
#endif

	surface.update();

	// Use the sky hemisphere for thin cards, independent of which face the
	// camera sees. This replaces the existing lookup; it adds no probe sample.
	half3 ambient = GetAmbient(surface.IsThinSurface() ? float3(0, 1, 0) : surface.N);
	ambient = lerp(ambient, ambient * surface.sss.rgb, saturate(surface.sss.a));

	Lighting lighting;
	lighting.create(0, 0, ambient, 0);

	
	half4 color = surface.baseColor;

#ifdef WATER
	//NORMALMAP
	half2 bumpColor0 = 0;
	half2 bumpColor1 = 0;
	half2 bumpColor2 = 0;
	const float water_cam_dist = distance(surface.P, camera.position);
	const float water_wave_fade = saturate(1.0 - (water_cam_dist - 18.0) / 90.0);
	const float water_normal_strength = material.GetNormalMapStrength() * lerp(0.22, 1.0, water_wave_fade);
	float2 water_wave_xy = surface.P.xz * 0.25;
	[branch]
	if (material.textures[NORMALMAP].IsValid())
	{
		Texture2D<half4> texture_normalmap = bindless_textures_half4[descriptor_index(material.textures[NORMALMAP].texture_descriptor)];
		const float2 UV_normalMap = material.textures[NORMALMAP].GetUVSet() == 0 ? uvsets.xy : uvsets.zw;
		water_wave_xy = UV_normalMap;
		// Two scrolling octaves (broad swells + counter-moving rotated capillary ripples), NormalGL green negated for TBN:
		const float2 uv0 = UV_normalMap - material.texMulAdd.ww;
		const float2 raw_uv1 = UV_normalMap * 2.13 + float2(material.texMulAdd.z * 1.35, -material.texMulAdd.w * 1.15);
		const float2 uv1 = float2(raw_uv1.x * 0.80 - raw_uv1.y * 0.60, raw_uv1.x * 0.60 + raw_uv1.y * 0.80);
		bumpColor0 = (2 * texture_normalmap.Sample(sampler_objectshader, uv0).rg - 1) * half2(1, -1);
		bumpColor1 = (2 * texture_normalmap.Sample(sampler_objectshader, uv1).rg - 1) * half2(1, -1) * 0.65h;
	}
	[branch]
	if (camera.texture_waterriples_index >= 0)
	{
		bumpColor2 = bindless_textures_half4[descriptor_index(camera.texture_waterriples_index)].SampleLevel(sampler_linear_clamp, ScreenCoord, 0).rg;
	}
	surface.bumpColor = half3(bumpColor0 + bumpColor1 + bumpColor2, 1) * material.GetRefraction();
	surface.N = normalize(lerp(surface.N, mul(normalize(surface.bumpColor), TBN), water_normal_strength));
	surface.bumpColor.rg *= water_normal_strength;
	// Recompute Fresnel and reflection vectors from the perturbed wave normal:
	surface.update();

	const bool valid_planar_reflection =
		camera.texture_reflection_index >= 0 &&
		is_frontface &&
		camera.reflection_plane.y > 0.5 &&
		abs(dot(float4(surface.P, 1), camera.reflection_plane)) < 0.2 &&
		dot(float4(camera.position, 1), camera.reflection_plane) > 0;
	[branch]
	if (valid_planar_reflection)
	{
		//REFLECTION
		float4 reflectionUV = mul(camera.reflection_view_projection, float4(surface.P, 1));
		reflectionUV.xy /= max(abs(reflectionUV.w), 1e-4) * (reflectionUV.w < 0 ? -1.0 : 1.0);
		reflectionUV.xy = clamp(clipspace_to_uv(reflectionUV.xy) + surface.bumpColor.rg, 0.001, 0.999);
		half3 reflectiveColor = bindless_textures_half4[descriptor_index(camera.texture_reflection_index)].SampleLevel(sampler_linear_mirror, reflectionUV.xy, 0).rgb;
		[branch]
		if (camera.texture_reflection_depth_index >= 0)
		{
			float reflectiveDepth = bindless_textures[descriptor_index(camera.texture_reflection_depth_index)].SampleLevel(sampler_point_clamp, reflectionUV.xy, 0).r;
			if (reflectiveDepth > 0)
			{
				float3 reflectivePosition = reconstruct_position(reflectionUV.xy, reflectiveDepth, camera.reflection_inverse_view_projection);
				float4 water_plane = camera.reflection_plane;
				float water_depth = max(0.0, -dot(float4(reflectivePosition, 1), water_plane));
				reflectiveColor.rgb = lerp(color.rgb, reflectiveColor.rgb, saturate(exp(-water_depth * color.a)));
			}
		}
		lighting.indirect.specular += reflectiveColor * surface.F;
	}
	else
	{
		// Without matching planar reflections (stereo rendering, different water elevations, or underwater),
		// start from the global sky cubemap and layer fast per-eye SSR of trees, banks, and cliffs:
		half3 water_refl = EnvironmentReflection_Global(surface);
		[branch]
		if (is_frontface && camera.texture_refraction_index >= 0)
		{
			const float surface_lin_depth = compute_lineardepth(input.pos.z);
			float3 refl_dir = normalize(lerp(reflect(-surface.V, surface.facenormal), (float3)surface.R, 0.32));
			refl_dir.y = max(refl_dir.y, 0.01);

			bool ssr_hit = false;
			float t_lo = 0.0;
			float t_hi = 0.0;
			float2 hit_uv = 0.0;

			[loop]
			for (int i = 1; i <= 14; ++i)
			{
				const float fi = float(i);
				const float prev_fi = fi - 1.0;
				const float cur_t = 0.25 * fi * fi + 0.35 * fi;
				const float prev_t = 0.25 * prev_fi * prev_fi + 0.35 * prev_fi;
				const float step_len = cur_t - prev_t;

				const float3 sample_pos = surface.P + refl_dir * cur_t;
				float4 clip = mul(camera.view_projection, float4(sample_pos, 1));
				if (clip.w <= 1e-4)
					break;
				clip.xyz /= clip.w;
				const float2 uv = clipspace_to_uv(clip.xy);
				if (any(uv < 0.0) || any(uv > 1.0))
					break;

				const float scene_depth = texture_depth.SampleLevel(sampler_point_clamp, uv, 0);
				if (scene_depth > 0.0 && scene_depth > clip.z)
				{
					const float scene_lin = compute_lineardepth(scene_depth);
					const float ray_lin = compute_lineardepth(clip.z);
					if (scene_lin > surface_lin_depth + 0.05 && (ray_lin - scene_lin) < max(1.4, step_len * 2.2))
					{
						ssr_hit = true;
						t_lo = prev_t;
						t_hi = cur_t;
						hit_uv = uv;
						break;
					}
				}
			}

			if (ssr_hit)
			{
				[unroll]
				for (int j = 0; j < 3; ++j)
				{
					const float mid_t = 0.5 * (t_lo + t_hi);
					const float3 mid_pos = surface.P + refl_dir * mid_t;
					float4 mid_clip = mul(camera.view_projection, float4(mid_pos, 1));
					if (mid_clip.w <= 1e-4)
						break;
					mid_clip.xyz /= mid_clip.w;
					const float2 mid_uv = clipspace_to_uv(mid_clip.xy);
					if (any(mid_uv < 0.0) || any(mid_uv > 1.0))
						break;
					const float mid_scene = texture_depth.SampleLevel(sampler_point_clamp, mid_uv, 0);
					const float mid_scene_lin = compute_lineardepth(mid_scene);
					if (mid_scene > 0.0 && mid_scene > mid_clip.z && mid_scene_lin > surface_lin_depth + 0.05)
					{
						t_hi = mid_t;
						hit_uv = mid_uv;
					}
					else
					{
						t_lo = mid_t;
					}
				}

				const float edge_dist = min(min(hit_uv.x, 1.0 - hit_uv.x), min(hit_uv.y, 1.0 - hit_uv.y));
				const half border_fade = (half)smoothstep(0.0, 0.10, edge_dist);
				const half dist_fade = (half)smoothstep(54.0, 28.0, t_hi);
				const half ssr_weight = border_fade * dist_fade;
				const half3 ssr_color = bindless_textures_half4[descriptor_index(camera.texture_refraction_index)].SampleLevel(sampler_linear_clamp, hit_uv, 0).rgb;
				water_refl = lerp(water_refl, ssr_color * surface.F, ssr_weight);
			}
		}
		lighting.indirect.specular += water_refl;
	}
#endif // WATER



#ifdef TRANSPARENT
	surface.transmission = lerp(material.GetTransmission(), 1, material.GetCloak());
	
	[branch]
	if (surface.transmission > 0)
	{
#ifdef OBJECTSHADER_USE_UVSETS
		[branch]
		if (material.textures[TRANSMISSIONMAP].IsValid())
		{
			half transmissionMap = (half)material.textures[TRANSMISSIONMAP].Sample(sampler_objectshader, uvsets).r;
			surface.transmission *= transmissionMap;
		}
#endif // OBJECTSHADER_USE_UVSETS

		[branch]
		if (camera.texture_refraction_index >= 0)
		{
			Texture2D<half4> texture_refraction = bindless_textures_half4[descriptor_index(camera.texture_refraction_index)];
			float2 size;
			float mipLevels;
			texture_refraction.GetDimensions(0, size.x, size.y, mipLevels);
			const float2 normal2D = mul((float3x3)camera.view, surface.N.xyz).xy;
			float2 perturbatedRefrTexCoords = ScreenCoord.xy + normal2D * lerp(material.GetRefraction(), 0.1, material.GetCloak());
			float mip = lerp(surface.roughness, 0.1, material.GetCloak()) * mipLevels;
			float chromatic = material.GetChromaticAberration() / size;
			half refractiveColorR = texture_refraction.SampleLevel(sampler_linear_clamp, perturbatedRefrTexCoords + float2(1, 1) * chromatic, mip).r;
			half refractiveColorG = texture_refraction.SampleLevel(sampler_linear_clamp, perturbatedRefrTexCoords + float2(0, 0) * chromatic, mip).g;
			half refractiveColorB = texture_refraction.SampleLevel(sampler_linear_clamp, perturbatedRefrTexCoords - float2(1, 1) * chromatic, mip).b;
			half3 refractiveColor = half3(refractiveColorR, refractiveColorG, refractiveColorB);
			surface.refraction.rgb = lerp(surface.albedo, 1, material.GetCloak()) * refractiveColor.rgb;
			surface.refraction.a = surface.transmission;
		}
	}
#endif // TRANSPARENT


#ifdef OBJECTSHADER_USE_COMMON
	LightMapping(meshinstance.lightmap, input.atl, lighting, surface);

	// The light of glowing blocks (MaterialComponent::SetBlockLight()): the level in the vertex, linear from block to block,
	//	gets the falloff of a light here, each level 75 % of the one above, and 0 at level 0. Added to the direct light, so the
	//	ambient occlusion (the sky visibility of the voxel world) doesn't take it away in caves:
	[branch]
	if (material.IsBlockLight() && input.ao_wet.z > 0)
	{
		static const half levels = 15;
		static const half falloff = 0.75; // per level
		static const half floor_light = 0.0134; // pow(falloff, levels)
		const half intensity = saturate(((half)pow(falloff, levels * (1 - input.ao_wet.z)) - floor_light) / (1 - floor_light));
		lighting.direct.diffuse += (half3)GetWeather().block_light_color.rgb * intensity * PI;
	}
#endif // OBJECTSHADER_USE_COMMON

#ifdef PLANARREFLECTION
	lighting.indirect.specular += PlanarReflection(surface, surface.bumpColor.rg) * surface.F;
#endif

#ifdef TILEDFORWARD
#ifdef OBJECTSHADER_USE_COMMON
	const half3 diffuse_before_lights = lighting.direct.diffuse;
#endif // OBJECTSHADER_USE_COMMON
	TiledLighting(surface, lighting, flat_tile_index, camera);
#ifdef OBJECTSHADER_USE_COMMON
	// The caustics of the water: the direct light of the sun and lamps is gathered into wandering lines (brighter on them,
	//	darker between them), only where it reaches, so not in the shadows, fading out cleanly with distance:
	[branch]
	if (caustics_weight > 0)
	{
		const half caustics_fade = (half)saturate(1.0 - (distance(surface.P, camera.position) - 12.0) / 28.0);
		if (caustics_fade > 0.001h)
		{
			const half caustics = WaterCaustics(surface.P.xz + surface.P.y * 0.25, GetTime());
			lighting.direct.diffuse += (lighting.direct.diffuse - diffuse_before_lights) * caustics_weight * caustics_fade * (caustics * 2.1 - 0.25);
		}
	}
#endif // OBJECTSHADER_USE_COMMON
#endif // TILEDFORWARD


#ifndef WATER
#ifndef ENVMAPRENDERING
#ifndef TRANSPARENT
#ifndef CARTOON
	[branch]
	if (camera.texture_ssr_index >= 0)
	{
		half4 ssr = bindless_textures_half4[descriptor_index(camera.texture_ssr_index)].SampleLevel(sampler_linear_clamp, ScreenCoord, 0);
		lighting.indirect.specular = lerp(lighting.indirect.specular, ssr.rgb * surface.F, ssr.a);
	}
	[branch]
	if (camera.texture_ssgi_index >= 0)
	{
		surface.ssgi = bindless_textures_half4[descriptor_index(camera.texture_ssgi_index)].SampleLevel(sampler_linear_clamp, ScreenCoord, 0).rgb;
	}
	[branch]
	if (camera.texture_ao_index >= 0)
	{
		surface.occlusion *= bindless_textures_half4[descriptor_index(camera.texture_ao_index)].SampleLevel(sampler_linear_clamp, ScreenCoord, 0).r;
	}
#endif // CARTOON
#endif // TRANSPARENT
#endif // ENVMAPRENDERING
#endif // WATER

#ifdef WATER
	[branch]
	if (camera.texture_refraction_index >= 0)
	{
		// Water refraction and Beer-Lambert optical absorption using outward surface plane and true path length:
		const float3 water_out_normal = is_frontface ? surface.facenormal : -surface.facenormal;
		const float4 water_plane = valid_planar_reflection ? camera.reflection_plane : float4(water_out_normal, -dot(surface.P, water_out_normal));
		const bool camera_in_water = dot(float4(camera.position, 1), water_plane) < 0;
		Texture2D<half4> texture_refraction = bindless_textures_half4[descriptor_index(camera.texture_refraction_index)];

		// Unperturbed depth directly beneath this water pixel anchors shoreline contact feather & foam in both stereo eyes:
		const float center_depth = texture_depth.SampleLevel(sampler_point_clamp, ScreenCoord.xy, 0);
		const float3 center_pos = reconstruct_position(ScreenCoord.xy, center_depth);
		float shore_depth = (center_depth > 0.0) ? -dot(float4(center_pos, 1), water_plane) : 8.0;
		if (camera_in_water)
			shore_depth = (center_depth > 0.0) ? -shore_depth : water_cam_dist;
		shore_depth = max(0.0, shore_depth);

		float2 refraction_uv = clamp(ScreenCoord.xy + surface.bumpColor.rg, 0.001, 0.999);
		float refraction_depth = find_max_depth(refraction_uv, 2, 2);
		float3 refraction_position = reconstruct_position(refraction_uv, refraction_depth);
		float water_depth = (refraction_depth > 0.0) ? -dot(float4(refraction_position, 1), water_plane) : 8.0;
		if (camera_in_water)
			water_depth = (refraction_depth > 0.0) ? -water_depth : water_cam_dist;

		if (water_depth <= 0)
		{
			// Above water, fill shoreline holes cleanly with unperturbed background
			refraction_uv = ScreenCoord.xy;
		}
		else if (camera_in_water)
		{
			refraction_uv = clamp(ScreenCoord.xy + surface.bumpColor.rg * saturate(1.0 - exp(-water_depth * 2.2)), 0.001, 0.999);
		}
		else
		{
			refraction_uv = clamp(ScreenCoord.xy + surface.bumpColor.rg * saturate(1.0 - exp(-min(water_depth, shore_depth) * 2.8)), 0.001, 0.999);
		}

		surface.refraction.rgb = (half3)texture_refraction.SampleLevel(sampler_linear_mirror, refraction_uv, 0).rgb;
		refraction_depth = texture_depth.SampleLevel(sampler_point_clamp, refraction_uv, 0);
		refraction_position = reconstruct_position(refraction_uv, refraction_depth);
		float water_depth_sample = (refraction_depth > 0.0) ? -dot(float4(refraction_position, 1), water_plane) : 8.0;
		if (camera_in_water)
			water_depth_sample = (refraction_depth > 0.0) ? -water_depth_sample : water_cam_dist;
		water_depth = max(0.0, max(water_depth, water_depth_sample));

		const float raw_ray_depth = camera_in_water ? water_cam_dist : (refraction_depth > 0.0 ? distance(refraction_position, surface.P) : 48.0);
		const float ray_depth = max(water_depth, min(raw_ray_depth, 48.0));

		float waterfog = saturate(exp(-ray_depth * color.a));
		float3 transmittance = saturate(exp(-ray_depth * surface.extinction * color.a));
		surface.refraction.a = waterfog;
		surface.refraction.rgb *= transmittance;

		if (!is_frontface || camera_in_water)
		{
			// Underwater Snell's window (critical angle water->air ~48.6 deg -> cos_c = 0.6614)
			const half snell = smoothstep(0.60h, 0.72h, surface.NdotV);
			surface.F = lerp(half3(1.0h, 1.0h, 1.0h), max(surface.F, (half3)0.04h), snell);
			const half3 tir_tint = surface.albedo * max(lighting.indirect.diffuse, (half3)0.12h);
			lighting.indirect.specular += tir_tint * (1.0h - snell);
		}
		else
		{
			// Soft shoreline contact feather and subtle animated foam anchored on unperturbed shoreline depth
			const half water_edge_fade = (half)smoothstep(0.0, 0.18, shore_depth);
			lighting.direct.specular *= water_edge_fade;
			lighting.indirect.specular *= water_edge_fade;
			surface.F *= water_edge_fade;

			const float foam_band = smoothstep(0.22, 0.015, shore_depth) * smoothstep(0.0, 0.025, shore_depth);
			const float foam_noise = 0.5 + 0.5 * sin(water_wave_xy.x * 18.0 + GetTime() * 1.9 + sin(water_wave_xy.y * 14.0 - GetTime() * 1.3));
			const half water_shore_foam = (half)(foam_band * smoothstep(0.32, 0.92, foam_noise) * 0.42);
			surface.albedo = lerp(surface.albedo, half3(0.84h, 0.90h, 0.92h), water_shore_foam);
			surface.refraction.a *= (1.0h - water_shore_foam);
		}
		color.a = 1;
	}
#endif // WATER

	ApplyLighting(surface, lighting, color);


#ifdef OBJECTSHADER_USE_INSTANCEINDEX
	half4 rimHighlight = meshinstance.GetRimHighlight();
	color.rgb += rimHighlight.rgb * pow(1 - surface.NdotV, rimHighlight.w);
#endif // OBJECTSHADER_USE_INSTANCEINDEX


#ifdef UNLIT
	color = surface.baseColor;
#endif // UNLIT

#ifdef INTERIORMAPPING
	surface.baseColor.rgb += surface.emissiveColor;
	color = surface.baseColor * InteriorMapping(surface.P, surface.N, surface.V, material, meshinstance);
#endif // INTERIORMAPPING


// Transparent objects has been rendered separately from opaque, so let's apply it now.
// Must also be applied before fog since fog is layered over.
#if defined(TRANSPARENT) || defined(ENVMAPRENDERING)
	ApplyAerialPerspective(ScreenCoord, surface.P, color);
#endif // defined(TRANSPARENT) || defined(ENVMAPRENDERING)


	ApplyFog(dist, surface.V, color);

	color.rgb = mul(saturationMatrix(material.GetSaturation()), color.rgb);

	color = saturateMediump(color);

	half alphatest = material.GetAlphaTest() + meshinstance.GetAlphaTest();
	if (material.IsThinSurface())
	{
		// Material density changes smoothly, independently of mesh LOD. Instance
		// alpha/dithering still controls visibility of the whole object.
		alphatest = FoliageAlphaTest(material.GetAlphaTest(), dist) + meshinstance.GetAlphaTest();
	}

	half dithering = 0;
#ifndef DISABLE_ALPHATEST
#ifndef TRANSPARENT
#ifndef ENVMAPRENDERING
#ifdef OBJECTSHADER_USE_DITHERING
	dithering = input.GetDither();
#endif // OBJECTSHADER_USE_DITHERING
#endif // DISABLE_ALPHATEST
#endif // TRANSPARENT
#endif // ENVMAPRENDERING

#ifndef DISABLE_ALPHATEST
	coverage = AlphaToCoverage(color.a, alphatest, dithering, input.pos); // opaque soft alpha test (MSAA, temporal AA support)
#endif // DISABLE_ALPHATEST

#ifdef ENVMAPRENDERING
	color = clamp(color, 0, 1000); // don't allow very large values in envmap, because it could cause filtering to blow up
#endif // ENVMAPRENDERING
	
	// end point:
#ifdef PREPASS
#ifndef DEPTHONLY
	return input.primitiveID;
#endif // DEPTHONLY
#else
	return color;
#endif // PREPASS
}


#endif // OBJECTSHADER_COMPILE_PS



#endif // WI_OBJECTSHADER_HF

