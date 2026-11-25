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
	half ore_edge;

	inline void create(in ShaderMaterial material, in VertexInput input)
	{
		ShaderMeshInstance inst = input.GetInstance();
		float4 pos_wind = input.GetPositionWind();
		position = float4(pos_wind.xyz, 1);
		ore_edge = half(pos_wind.w);
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
	half4 ao_wet : COMMON; // z: the block light (SetBlockLight()), w: ore deposit boundary code
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
	Out.ao_wet = half4(surface.ao, surface.wet, surface.block_light, surface.ore_edge);
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

// A liquid flowing along its mesh (MaterialComponent::SetVertexFlow()): the second uv set is the flow in uv per second. The
//	maps are read at two places shifted along the flow, half a cycle apart, and crossfaded (flow map technique)
struct LiquidFlow
{
	float2 uv0;
	float2 uv1;
	half weight0;
};
inline bool IsFlowing(float2 flow)
{
	return dot(flow, flow) > 1e-8;
}
inline LiquidFlow GetLiquidFlow(float2 uv, float2 flow)
{
	const float cycle = 1.6; // seconds until a layer starts again
	const float t = GetTime() / cycle;
	const float phase0 = frac(t);
	const float phase1 = frac(t + 0.5);
	LiquidFlow result;
	result.uv0 = uv - flow * (phase0 * cycle);
	result.uv1 = uv - flow * (phase1 * cycle) + float2(0.37, 0.61);
	result.weight0 = (half)(1 - abs(2 * phase0 - 1));
	return result;
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

// Fast integer 3D hash & Perlin edge-gradient noise (precision-stable at arbitrary world coordinates):
inline uint OreWangHash(uint h)
{
	h = (h ^ 61u) ^ (h >> 16u);
	h *= 9u;
	h = h ^ (h >> 4u);
	h *= 0x27d4eb2du;
	h = h ^ (h >> 15u);
	return h;
}

inline uint OreHash3(int3 c)
{
	const uint3 uc = asuint(c);
	return OreWangHash(uc.x * 0x8da6b343u ^ uc.y * 0xd8163841u ^ uc.z * 0xcb1ab31fu);
}

inline float OreGradDot(uint h, float3 d)
{
	const uint g = h & 15u;
	const float u = g < 8u ? d.x : d.y;
	const float v = g < 4u ? d.y : ((g == 12u || g == 14u) ? d.x : d.z);
	return ((g & 1u) == 0u ? u : -u) + ((g & 2u) == 0u ? v : -v);
}

inline float OreNoise3D(float3 p)
{
	const int3 i = int3(floor(p));
	const float3 f = p - float3(i);
	const float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	const float c000 = OreGradDot(OreHash3(i + int3(0, 0, 0)), f - float3(0, 0, 0));
	const float c100 = OreGradDot(OreHash3(i + int3(1, 0, 0)), f - float3(1, 0, 0));
	const float c010 = OreGradDot(OreHash3(i + int3(0, 1, 0)), f - float3(0, 1, 0));
	const float c110 = OreGradDot(OreHash3(i + int3(1, 1, 0)), f - float3(1, 1, 0));
	const float c001 = OreGradDot(OreHash3(i + int3(0, 0, 1)), f - float3(0, 0, 1));
	const float c101 = OreGradDot(OreHash3(i + int3(1, 0, 1)), f - float3(1, 0, 1));
	const float c011 = OreGradDot(OreHash3(i + int3(0, 1, 1)), f - float3(0, 1, 1));
	const float c111 = OreGradDot(OreHash3(i + int3(1, 1, 1)), f - float3(1, 1, 1));
	const float x00 = lerp(c000, c100, u.x);
	const float x10 = lerp(c010, c110, u.x);
	const float x01 = lerp(c001, c101, u.x);
	const float x11 = lerp(c011, c111, u.x);
	return lerp(lerp(x00, x10, u.y), lerp(x01, x11, u.y), u.z);
}

// Jittered 2x2x2 3D angular crystal/clast pod field (single flat 8-cell loop, seamless across cell borders for radius < 0.60):
inline float OrePockets3D(float3 p, float blocky)
{
	const int3 base = int3(floor(p - 0.5));
	const float shear_gain = saturate((blocky - 0.50) * 5.0);
	float best = 0.0;
	[loop]
	for (uint ci = 0u; ci < 8u; ++ci)
	{
		const int3 cid = base + int3(int(ci & 1u), int((ci >> 1u) & 1u), int(ci >> 2u));
		const uint h = OreHash3(cid);
		const float pres = float(h & 0xFFu) * (1.0 / 255.0);
		if (pres > 0.20)
		{
			const float rx = float((h >> 8u) & 0xFFu) * (1.0 / 255.0);
			const float ry = float((h >> 16u) & 0xFFu) * (1.0 / 255.0);
			const float rz = float((h >> 24u) & 0xFFu) * (1.0 / 255.0);
			const float3 ctr = float3(cid) + float3(0.22 + 0.56 * rx, 0.22 + 0.56 * ry, 0.22 + 0.56 * rz);
			float3 d = p - ctr;
			if (shear_gain > 0.0)
			{
				const float txy = (frac(rx * 13.7) - 0.5) * 0.42 * shear_gain;
				const float tzy = (frac(rz * 17.3) - 0.5) * 0.42 * shear_gain;
				const float txz = (frac(ry * 11.1) - 0.5) * 0.62 * shear_gain;
				d = float3(d.x + txz * d.z - txy * d.y, d.y + txy * d.x + tzy * d.z, d.z - txz * d.x - tzy * d.y);
			}
			const float3 stretch = float3(
				0.68 + 0.64 * frac(rx * 7.3),
				0.68 + 0.64 * frac(ry * 5.7),
				0.68 + 0.64 * frac(rz * 9.1)
			);
			const float3 ds = abs(d) * stretch;
			const float d_l1 = (ds.x + ds.y + ds.z) * 0.61;
			const float d_linf = max(ds.x, max(ds.y, ds.z));
			const float dist = (1.0 - blocky) * d_l1 + blocky * d_linf;
			const float size_mul = 0.72 + 0.56 * ((pres - 0.20) * (1.0 / 0.80));
			const float t = saturate(1.0 - dist / (0.60 * size_mul));
			if (t > 0.0)
			{
				best = max(best, pow(t, 0.46));
			}
		}
	}
	return best;
}

// Continuous world-space 3D vein, coal-clast/seam, and crystal-pocket field for MaterialComponent::SetOreOverlay():
//	uses constant per-ore strike/dip rotation + angular rock-joint warps so veins & clasts vary organically without
//	origin-distance stretching, tile repetition, or isolated paint-splatter droplets
inline float EvalOreVeinField(float3 P, float scale, float style_blend, float seed)
{
	const bool is_coal = (style_blend < 0.07);
	const float theta = frac(seed * 0.3713) * 6.2831853;
	const float phi = 0.22 + frac(seed * 0.7137) * 0.52;
	float st, ct, sp, cp;
	sincos(theta, st, ct);
	sincos(phi, sp, cp);
	const float rx = P.x * ct - P.z * st;
	const float rz = P.x * st + P.z * ct;
	const float ry = P.y * cp - rz * sp;
	const float rz2 = P.y * sp + rz * cp;

	const float bed_y = 1.0 + (1.0 - style_blend) * 0.55;
	const float3 s_off = float3(seed * 13.7, seed * 29.3, seed * 41.9);
	const float3 q0 = is_coal
		? (float3(P.x * 0.90, P.y * 1.38, P.z * 0.90) * scale + s_off)
		: (float3(rx, ry * bed_y, rz2) * scale + s_off);

	const float3 w1 = float3(
		OreNoise3D(q0 * 0.58 + float3(1.7, 9.2, 4.1)),
		OreNoise3D(q0 * 0.58 + float3(8.3, 2.8, 6.5)),
		OreNoise3D(q0 * 0.58 + float3(3.4, 7.1, 1.9))
	);
	const float3 w2 = float3(
		OreNoise3D(q0 * 1.95 + w1 * 0.35 + float3(5.1, 2.2, 8.8)),
		OreNoise3D(q0 * 1.95 + w1 * 0.35 + float3(1.4, 6.9, 3.7)),
		OreNoise3D(q0 * 1.95 + w1 * 0.35 + float3(9.6, 4.3, 2.1))
	);
	const float3 j3 = float3(
		OreNoise3D(q0 * 5.2 + float3(2.3, 8.7, 5.1)),
		OreNoise3D(q0 * 5.2 + float3(6.1, 1.9, 9.4)),
		OreNoise3D(q0 * 5.2 + float3(4.8, 7.3, 3.2))
	);
	const float3 w2_fold = abs(w2) * 2.0 - 0.5;
	const float3 qw = q0 + 0.34 * w1 + 0.22 * w2_fold + 0.085 * j3;
	const float crag = (1.0 - abs(OreNoise3D(qw * 4.6 + float3(2.3, 8.7, 5.1))) * 2.0) * 0.092
		+ OreNoise3D(qw * 10.8 - float3(6.1, 1.9, 9.4)) * 0.050;

	const float vein_gain = is_coal ? 0.0 : saturate((0.92 - style_blend) * (1.0 / 0.42));
	const float pocket_gain = is_coal ? 1.0 : saturate((style_blend - 0.05) * (1.0 / 0.40));

	float vein_f = 0.0;
	if (vein_gain > 0.001)
	{
		const float n1 = OreNoise3D(qw);
		const float n2 = OreNoise3D(qw * 1.75 + float3(12.4, 5.7, 9.1));
		const float pinch1 = clamp(0.80 + 0.78 * OreNoise3D(q0 * 0.72 + float3(7.1, 3.3, 11.9)), 0.22, 1.12);
		const float pinch2 = clamp(0.70 + 0.78 * OreNoise3D(q0 * 1.05 - float3(4.8, 9.2, 2.7)), 0.18, 1.08);
		const float ra_base = saturate(1.0 - abs(n1) * 2.28);
		const float rb_base = saturate(1.0 - abs(n2) * 2.68);
		const float ra = (ra_base > 0.0 ? pow(ra_base, 1.20) : 0.0) * pinch1;
		const float rb = (rb_base > 0.0 ? pow(rb_base, 1.30) : 0.0) * pinch2 * (0.64 + 0.36 * saturate(ra * 2.0));
		const float core = max(ra, 0.86 * rb);
		vein_f = saturate(core + crag * smoothstep(0.22, 0.55, core));
	}

	float pocket_f = 0.0;
	if (pocket_gain > 0.001)
	{
		const float3 qp = is_coal
			? (q0 + float3(0.24, 0.16, 0.24) * w1 + float3(0.16, 0.12, 0.16) * w2_fold)
			: (float3(rx, ry, rz2) * (scale * 1.15) + s_off * 0.63 + 0.20 * w1 + 0.16 * w2);
		const float blocky = is_coal ? 0.68 : 0.48;
		const float p_main = OrePockets3D(qp, blocky);
		const float p_sat = OrePockets3D(qp * 1.90 + float3(14.2, 7.6, 3.9), blocky);
		float cluster;
		if (is_coal)
		{
			const float bed_fold = q0.y * 1.05 + 0.55 * OreNoise3D(q0 * float3(0.45, 0.35, 0.45) + float3(2.2, 6.1, 8.4));
			cluster = clamp(0.92 + 0.16 * sin(bed_fold * 2.3) + 0.18 * OreNoise3D(P * 1.35 + s_off * 0.29), 0.78, 1.12);
		}
		else
		{
			cluster = clamp(0.96 + 0.22 * OreNoise3D(P * 1.35 + s_off * 0.29), 0.70, 1.12);
		}
		const float p_core = max(p_main, 0.90 * p_sat) * cluster;
		pocket_f = saturate(p_core + crag * smoothstep(0.25, 0.58, p_core));
	}

	return saturate(max(vein_f * vein_gain, pocket_f * pocket_gain));
}

inline float3 OreGradVec(uint h)
{
	const uint g = h & 15u;
	const float sx = (g & 1u) == 0u ? 1.0 : -1.0;
	const float sy = (g & 2u) == 0u ? 1.0 : -1.0;
	if (g < 4u) return float3(sx, sy, 0.0);
	if (g < 8u) return float3(sx, 0.0, sy);
	if (g < 12u) return float3(0.0, sx, sy);
	if (g == 12u) return float3(1.0, 1.0, 0.0);
	if (g == 13u) return float3(-1.0, 1.0, 0.0);
	if (g == 14u) return float3(0.0, -1.0, 1.0);
	return float3(0.0, -1.0, -1.0);
}

// Returns float4(value, d/dx, d/dy, d/dz) of 3D gradient noise in one pass:
inline float4 OreNoise3DGrad(float3 p)
{
	const int3 i = int3(floor(p));
	const float3 f = p - float3(i);
	const float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	const float3 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

	const float3 g000 = OreGradVec(OreHash3(i + int3(0, 0, 0)));
	const float3 g100 = OreGradVec(OreHash3(i + int3(1, 0, 0)));
	const float3 g010 = OreGradVec(OreHash3(i + int3(0, 1, 0)));
	const float3 g110 = OreGradVec(OreHash3(i + int3(1, 1, 0)));
	const float3 g001 = OreGradVec(OreHash3(i + int3(0, 0, 1)));
	const float3 g101 = OreGradVec(OreHash3(i + int3(1, 0, 1)));
	const float3 g011 = OreGradVec(OreHash3(i + int3(0, 1, 1)));
	const float3 g111 = OreGradVec(OreHash3(i + int3(1, 1, 1)));

	const float c000 = dot(g000, f - float3(0, 0, 0));
	const float c100 = dot(g100, f - float3(1, 0, 0));
	const float c010 = dot(g010, f - float3(0, 1, 0));
	const float c110 = dot(g110, f - float3(1, 1, 0));
	const float c001 = dot(g001, f - float3(0, 0, 1));
	const float c101 = dot(g101, f - float3(1, 0, 1));
	const float c011 = dot(g011, f - float3(0, 1, 1));
	const float c111 = dot(g111, f - float3(1, 1, 1));

	const float k0 = c000;
	const float k1 = c100 - c000;
	const float k2 = c010 - c000;
	const float k3 = c001 - c000;
	const float k4 = c000 - c100 - c010 + c110;
	const float k5 = c000 - c010 - c001 + c011;
	const float k6 = c000 - c100 - c001 + c101;
	const float k7 = -c000 + c100 + c010 - c110 + c001 - c101 - c011 + c111;

	const float val = k0 + k1 * u.x + k2 * u.y + k3 * u.z
		+ k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
	const float3 g_interp = lerp(
		lerp(lerp(g000, g100, u.x), lerp(g010, g110, u.x), u.y),
		lerp(lerp(g001, g101, u.x), lerp(g011, g111, u.x), u.y),
		u.z
	);
	const float3 dval = g_interp + du * float3(
		k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
		k2 + k5 * u.z + k4 * u.x + k7 * u.z * u.x,
		k3 + k6 * u.x + k5 * u.y + k7 * u.x * u.y
	);
	return float4(val, dval);
}

// Sparse 3D crystal glints inside ore veins, flashing with view direction and time:
inline half OreSparkle(float3 P, float3 V, float seed)
{
	const float3 grid = P * 115.0 + seed * 3.7;
	const float3 cell = floor(grid);
	const float3 f = frac(grid);
	const uint3 uc = asuint(int3(cell));
	const uint h = OreWangHash(uc.x * 0x8da6b343u ^ uc.y * 0xd8163841u ^ uc.z * 0xcb1ab31fu ^ uint(seed * 100.0));
	const float r0 = float(h & 0xFFFFu) / 65535.0;
	if (r0 < 0.935)
		return 0;
	const float r1 = float((h >> 16u) & 0xFFu) / 255.0;
	const float r2 = float((h >> 24u) & 0xFFu) / 255.0;
	const float3 pt = float3(0.25 + 0.5 * r1, 0.25 + 0.5 * r2, 0.25 + 0.5 * frac(r0 * 19.3));
	const float spot = smoothstep(0.26, 0.04, length(f - pt));
	const float3 axis = normalize(frac(r0 * float3(13.17, 71.31, 37.73)) * 2.0 - 1.0 + 0.001);
	const float wave = saturate(sin(dot(V, axis) * 55.0 + r0 * 44.0 + GetTime() * (1.5 + r1 * 2.0)));
	return wave > 0.0 ? (half)(spot * pow(wave, 26.0)) : 0;
}

// Orthonormal 3x3 crystal orientation matrix from integer hash:
inline float3x3 OreGemRotMatrix(uint h)
{
	const float a = float(h & 0xFFu) * (6.2831853 / 255.0);
	const float b = float((h >> 8u) & 0xFFu) * (6.2831853 / 255.0);
	const float c = float((h >> 16u) & 0xFFu) * (6.2831853 / 255.0);
	float sa, ca, sb, cb, sc, cc;
	sincos(a, sa, ca);
	sincos(b, sb, cb);
	sincos(c, sc, cc);
	return float3x3(
		ca * cc - sa * sb * sc, -sa * cb, ca * sc + sa * sb * cc,
		sa * cc + ca * sb * sc,  ca * cb, sa * sc - ca * sb * cc,
		-cb * sc,                sb,      cb * cc
	);
}

inline uint OreMaskPack4(uint grp)
{
	if (grp < 6u)
	{
		if (grp == 0u) return 0x04030201u;
		if (grp == 1u) return 0x08070605u;
		if (grp == 2u) return 0x0c0b0a09u;
		if (grp == 3u) return 0x100f0e0du;
		if (grp == 4u) return 0x201a1812u;
		return 0x30292821u;
	}
	if (grp == 6u)  return 0x44424038u;
	if (grp == 7u)  return 0x60525046u;
	if (grp == 8u)  return 0x84818070u;
	if (grp == 9u)  return 0xa1a09085u;
	if (grp == 10u) return 0xd0c4c0b0u;
	return 0x0000f0e0u;
}

// Decodes exact 2D distance in meters (0.0 .. 0.25m) to the nearest coplanar non-matching ore deposit boundary:
inline float DecodeOreDepositEdgeDist(float ore_edge_raw, float2 uv0_pre_pom, float2 tex_mul)
{
	const uint code = uint(round(saturate(ore_edge_raw) * 255.0));
	if (code >= 184u)
		return 0.25;
	const uint state46 = code >> 2u;
	const uint mask8 = (OreMaskPack4(state46 >> 2u) >> ((state46 & 3u) * 8u)) & 0xFFu;
	const float px = float(code & 1u);
	const float py = float((code >> 1u) & 1u);
	const float2 uv_blk = uv0_pre_pom * (4.0 / max(abs(tex_mul), 1e-4));
	const float fx = saturate(uv_blk.x - (2.0 * floor((uv_blk.x - px + 0.5) * 0.5) + px));
	const float fy = saturate(uv_blk.y - (2.0 * floor((uv_blk.y - py + 0.5) * 0.5) + py));
	const float cx = 1.0 - fx;
	const float cy = 1.0 - fy;
	float d = 0.5;
	if (mask8 & 1u)   d = min(d, fx);
	if (mask8 & 2u)   d = min(d, cx);
	if (mask8 & 4u)   d = min(d, fy);
	if (mask8 & 8u)   d = min(d, cy);
	if ((mask8 & 5u) == 5u)   d = min(d, fx * fy * rsqrt(fx * fx + fy * fy + 1e-8) * 1.08);
	if ((mask8 & 6u) == 6u)   d = min(d, cx * fy * rsqrt(cx * cx + fy * fy + 1e-8) * 1.08);
	if ((mask8 & 9u) == 9u)   d = min(d, fx * cy * rsqrt(fx * fx + cy * cy + 1e-8) * 1.08);
	if ((mask8 & 10u) == 10u) d = min(d, cx * cy * rsqrt(cx * cx + cy * cy + 1e-8) * 1.08);
	if (mask8 & 16u)  d = min(d, length(float2(fx, fy)));
	if (mask8 & 32u)  d = min(d, length(float2(cx, fy)));
	if (mask8 & 64u)  d = min(d, length(float2(fx, cy)));
	if (mask8 & 128u) d = min(d, length(float2(cx, cy)));
	return d * 0.5;
}

inline void OreGemHouseholderAxesTabular(uint h, float3 N_grid, out float3 v1, out float3 v2)
{
	const uint hb = OreWangHash(h ^ 0x6c8e9cf5u);
	// Tilt crystal {001} axis ~15-50 degrees around face normal N_grid so square Autunite plates catch varied light & specular glints:
	const float3 jitter = float3(
		float(h & 0xFFu) * (2.0 / 255.0) - 1.0,
		float((h >> 8u) & 0xFFu) * (2.0 / 255.0) - 1.0,
		float((h >> 16u) & 0xFFu) * (2.0 / 255.0) - 1.0
	);
	const float3 axis = normalize(N_grid + jitter * 0.94);
	const float3 target_y = float3(0.0, axis.y >= 0.0 ? -1.0 : 1.0, 0.0);
	const float3 u1 = axis - target_y;
	v1 = u1 * rsqrt(max(dot(u1, u1), 1e-8));
	// Uniform 0..360 deg twist in local XZ plane rotates the square/rectangular plate silhouette without tilting local Y:
	const float2 u2_xz = float2(
		float(hb & 0xFFu) * (2.0 / 255.0) - 1.0 + 0.0037,
		float((hb >> 8u) & 0xFFu) * (2.0 / 255.0) - 1.0 - 0.0023
	);
	const float2 v2_xz = u2_xz * rsqrt(dot(u2_xz, u2_xz));
	v2 = float3(v2_xz.x, 0.0, v2_xz.y);
}

// Zero-trig double-Householder SO(3) crystal rotation (no sincos, no 3x3 matrix inside loop):
inline void OreGemHouseholderAxes(uint h, out float3 v1, out float3 v2)
{
	const uint hb = OreWangHash(h ^ 0x6c8e9cf5u);
	const float3 u1 = float3(
		float(h & 0xFFu) * (2.0 / 255.0) - 1.0 + 0.0031,
		float((h >> 8u) & 0xFFu) * (2.0 / 255.0) - 1.0 - 0.0017,
		float((h >> 16u) & 0xFFu) * (2.0 / 255.0) - 1.0 + 0.0023
	);
	const float3 u2 = float3(
		float(hb & 0xFFu) * (2.0 / 255.0) - 1.0 - 0.0029,
		float((hb >> 8u) & 0xFFu) * (2.0 / 255.0) - 1.0 + 0.0019,
		float((hb >> 16u) & 0xFFu) * (2.0 / 255.0) - 1.0 - 0.0013
	);
	v1 = u1 * rsqrt(dot(u1, u1));
	v2 = u2 * rsqrt(dot(u2, u2));
}

inline float3 OreGemRotFwd(float3 x, float3 v1, float3 v2)
{
	x -= (2.0 * dot(v1, x)) * v1;
	x -= (2.0 * dot(v2, x)) * v2;
	return x;
}

inline float3 OreGemRotInv(float3 x, float3 v1, float3 v2)
{
	x -= (2.0 * dot(v2, x)) * v2;
	x -= (2.0 * dot(v1, x)) * v1;
	return x;
}

inline float3 OreGemSlabDir(uint id)
{
	if (id == 0u) return float3( 1.0,  1.0,  1.0);
	if (id == 1u) return float3(-1.0,  1.0,  1.0);
	if (id == 2u) return float3( 1.0, -1.0,  1.0);
	if (id == 3u) return float3( 1.0,  1.0, -1.0);
	if (id == 4u) return float3( 1.0,  0.0,  0.0);
	if (id == 5u) return float3( 0.0,  1.0,  0.0);
	return float3(0.0, 0.0, 1.0);
}

// Ultra-fast single-loop 3D polyhedral slab ray-tracer (supports sharp {111} octahedral gems and stepped square-tabular Autunite books):
//	zero sincos, zero inner loops, and minimal scalar loop state for instant Vulkan/DX12 driver PSO compilation
inline void EvalOreGemRay(
	float3 p_surf,
	float3 p_mid,
	float3 D_grid,
	float3 N_grid,
	float t_rock,
	float layer_scale,
	float pres_thresh,
	float ore_taper,
	bool is_tabular,
	uint seed_tag,
	out float best_t,
	out float best_ridge,
	out float best_thick,
	out float best_sock,
	out float3 out_N_grid,
	out float3 out_Npav_grid,
	out float3 out_q_loc,
	out uint out_rot_hash,
	out uint out_hit_meta
)
{
	best_t = 1e6;
	best_ridge = 0.0;
	best_thick = 0.0;
	best_sock = 0.0;
	out_N_grid = N_grid;
	out_Npav_grid = -N_grid;
	out_q_loc = 0;
	out_rot_hash = 1u;
	out_hit_meta = 0u;

	const float eff_thresh = lerp(1.02, pres_thresh, ore_taper);
	const float z_max = is_tabular ? 0.028 : 0.023;
	const float d_len2 = max(dot(D_grid, D_grid), 1e-6);
	const float3 p_rock = p_surf + D_grid * t_rock;
	const int3 base = int3(floor(p_mid - 0.5));

	uint hit_h2 = 0u;
	uint hit_pack = 0xFFFFFFFFu;
	float hit_rad = 0.1;
	float second_t = 1e6;

	[loop]
	for (uint ci = 0u; ci < 8u; ++ci)
	{
		const int3 cid = base + int3(int(ci & 1u), int((ci >> 1u) & 1u), int(ci >> 2u));
		const uint h = OreWangHash(OreHash3(cid) ^ seed_tag);
		const float pres = float(h & 0xFFFFu) * (1.0 / 65535.0);
		if (pres >= eff_thresh)
		{
			const uint h2 = OreWangHash(h ^ 0x9e3779b9u);
			const float j_min = is_tabular ? 0.27 : 0.18;
			const float j_span = is_tabular ? 0.46 : 0.64;
			float3 ctr = float3(cid) + float3(
				j_min + j_span * (float(h2 & 0xFFu) * (1.0 / 255.0)),
				j_min + j_span * (float((h2 >> 8u) & 0xFFu) * (1.0 / 255.0)),
				j_min + j_span * (float((h2 >> 16u) & 0xFFu) * (1.0 / 255.0))
			);

			float z_ctr = dot(p_surf - ctr, N_grid) / layer_scale;
			const float3 ctr_vein = ctr;
			if (is_tabular && z_ctr > -0.014 && z_ctr < 0.036)
			{
				const float z_pulled = 0.0055 + 0.0095 * saturate((z_ctr + 0.014) * (1.0 / 0.050));
				ctr += N_grid * ((z_ctr - z_pulled) * layer_scale);
				z_ctr = z_pulled;
			}
			if (z_ctr > 0.0015 && z_ctr < z_max)
			{
				const float taper = is_tabular
					? 1.0
					: (saturate((z_ctr - 0.0015) * (1.0 / 0.0025)) * saturate((z_max - z_ctr) * (1.0 / 0.0045)));
				const float size_t = (pres - eff_thresh) / max(1.0 - eff_thresh, 1e-4);
				float rad;
				if (is_tabular)
				{
					const float p_lobe = 0.52
						+ 0.92 * OreNoise3D(ctr_vein * 0.24 + float3(3.1, 7.4, 2.2))
						+ 0.34 * OreNoise3D(ctr_vein * 0.53 - float3(6.2, 1.8, 4.9));
					const float p_frac = saturate(1.0 - abs(OreNoise3D(ctr_vein * 0.29 + float3(8.5, 2.3, 5.7))) * 2.65)
						* saturate(0.42 + 0.95 * OreNoise3D(ctr_vein * 0.20 - float3(1.9, 5.4, 7.8)));
					const float pocket_t = saturate((max(p_lobe, p_frac * 0.90) - 0.62) * (1.0 / 0.28));
					rad = (pocket_t > 0.0)
						? ((0.33 + 0.18 * (0.35 * size_t + 0.65 * pocket_t)) * saturate(0.45 + pocket_t * 1.55) * ore_taper)
						: 0.0;
				}
				else
				{
					rad = (0.145 + 0.195 * (size_t * size_t)) * taper * ore_taper;
				}

				if (rad > 0.015)
				{
					const float dist_rock = length(p_rock - ctr);
					const float sock_rad = is_tabular ? (rad * 0.74) : (rad * 0.85);
					const float sock_span = is_tabular ? (rad * 0.34) : (rad * 0.60);
					const float sock_w = saturate(1.0 - (dist_rock - sock_rad) / max(sock_span, 1e-4));
					best_sock = max(best_sock, sock_w);

					const float3 v_to_c = ctr - p_surf;
					const float t_closest = dot(v_to_c, D_grid) / d_len2;
					const float3 closest_vec = (p_surf + D_grid * t_closest) - ctr;
					const float rad_bound = rad * 1.65;
					if (dot(closest_vec, closest_vec) < rad_bound * rad_bound)
					{
						float3 rv1, rv2;
						if (is_tabular)
						{
							OreGemHouseholderAxesTabular(OreWangHash(h2 ^ 0x27d4eb2du), N_grid, rv1, rv2);
						}
						else
						{
							OreGemHouseholderAxes(OreWangHash(h2 ^ 0x27d4eb2du), rv1, rv2);
						}
						const uint ht = OreWangHash(h2 ^ 0x85ebca6bu);
						const float rx = float(ht & 0xFFu) * (1.0 / 255.0);
						const float ry = float((ht >> 8u) & 0xFFu) * (1.0 / 255.0);
						const float rz = float((ht >> 16u) & 0xFFu) * (1.0 / 255.0);
						const float rw = float((ht >> 24u) & 0xFFu) * (1.0 / 255.0);

						const float3 stretch = is_tabular
							? float3(0.86 + 0.28 * rx, 1.95 + 0.75 * ry, 0.86 + 0.28 * rz)
							: float3(0.82 + 0.36 * rx, 0.82 + 0.36 * ry, 0.78 + 0.42 * rz);
						const float r_oct = is_tabular ? (rad * (2.14 + 0.22 * rw)) : (rad * 1.7320508);
						const float3 r3_cub = is_tabular
							? (float3(0.92, 0.74, 0.92) * rad)
							: ((1.38 + 0.28 * rw) * rad).xxx;

						const float3 o_s = OreGemRotFwd(p_surf - ctr, rv1, rv2) * stretch;
						const float3 d_s = OreGemRotFwd(D_grid, rv1, rv2) * stretch;

						const float4 o4 = float4(o_s.x + o_s.y + o_s.z, -o_s.x + o_s.y + o_s.z, o_s.x - o_s.y + o_s.z, o_s.x + o_s.y - o_s.z);
						const float4 d4 = float4(d_s.x + d_s.y + d_s.z, -d_s.x + d_s.y + d_s.z, d_s.x - d_s.y + d_s.z, d_s.x + d_s.y - d_s.z);
						const float4 sgn_d4 = float4(d4.x >= 0.0 ? 1.0 : -1.0, d4.y >= 0.0 ? 1.0 : -1.0, d4.z >= 0.0 ? 1.0 : -1.0, d4.w >= 0.0 ? 1.0 : -1.0);
						const float4 inv_d4 = sgn_d4 / max(abs(d4), 1e-5);
						const float4 ta4 = (-r_oct - o4) * inv_d4;
						const float4 tb4 = ( r_oct - o4) * inv_d4;
						const float4 ten4 = min(ta4, tb4);
						const float4 tex4 = max(ta4, tb4);

						const float3 sgn_d3 = float3(d_s.x >= 0.0 ? 1.0 : -1.0, d_s.y >= 0.0 ? 1.0 : -1.0, d_s.z >= 0.0 ? 1.0 : -1.0);
						const float3 inv_d3 = sgn_d3 / max(abs(d_s), 1e-5);
						const float3 ta3 = (-r3_cub - o_s) * inv_d3;
						const float3 tb3 = ( r3_cub - o_s) * inv_d3;
						const float3 ten3 = min(ta3, tb3);
						const float3 tex3 = max(ta3, tb3);

						float t_enter = ten4.x;
						float t_enter2 = -1e6;
						uint id_en = 0u;
						if (ten4.y > t_enter) { t_enter2 = t_enter; t_enter = ten4.y; id_en = 1u; } else { t_enter2 = ten4.y; }
						if (ten4.z > t_enter) { t_enter2 = t_enter; t_enter = ten4.z; id_en = 2u; } else if (ten4.z > t_enter2) { t_enter2 = ten4.z; }
						if (ten4.w > t_enter) { t_enter2 = t_enter; t_enter = ten4.w; id_en = 3u; } else if (ten4.w > t_enter2) { t_enter2 = ten4.w; }
						if (ten3.x > t_enter) { t_enter2 = t_enter; t_enter = ten3.x; id_en = 4u; } else if (ten3.x > t_enter2) { t_enter2 = ten3.x; }
						if (ten3.y > t_enter) { t_enter2 = t_enter; t_enter = ten3.y; id_en = 5u; } else if (ten3.y > t_enter2) { t_enter2 = ten3.y; }
						if (ten3.z > t_enter) { t_enter2 = t_enter; t_enter = ten3.z; id_en = 6u; } else if (ten3.z > t_enter2) { t_enter2 = ten3.z; }

						float t_exit = tex4.x;
						uint id_ex = 0u;
						if (tex4.y < t_exit) { t_exit = tex4.y; id_ex = 1u; }
						if (tex4.z < t_exit) { t_exit = tex4.z; id_ex = 2u; }
						if (tex4.w < t_exit) { t_exit = tex4.w; id_ex = 3u; }
						if (tex3.x < t_exit) { t_exit = tex3.x; id_ex = 4u; }
						if (tex3.y < t_exit) { t_exit = tex3.y; id_ex = 5u; }
						if (tex3.z < t_exit) { t_exit = tex3.z; id_ex = 6u; }

						uint tier2_flag = 0u;
						if (is_tabular)
						{
							// Interlocking 45-deg rotated & independently tilted partner Autunite square plate filling pocket gaps:
							const float2 tilt_b = float2(rx - 0.5, rz - 0.5) * 0.56;
							const float3 off_b = float3((rw >= 0.5 ? 0.34 : -0.34), (ry - 0.5) * 0.26, (ry >= 0.5 ? 0.30 : -0.30)) * rad;
							const float3 o_b = float3((o_s.x + o_s.z) * 0.70710678, o_s.y + dot(o_s.xz, tilt_b), (o_s.x - o_s.z) * 0.70710678) - off_b;
							const float3 d_b = float3((d_s.x + d_s.z) * 0.70710678, d_s.y + dot(d_s.xz, tilt_b), (d_s.x - d_s.z) * 0.70710678);
							const float3 sgn_db = float3(d_b.x >= 0.0 ? 1.0 : -1.0, d_b.y >= 0.0 ? 1.0 : -1.0, d_b.z >= 0.0 ? 1.0 : -1.0);
							const float3 inv_db = sgn_db / max(abs(d_b), 1e-5);
							const float3 r3_b = float3(0.76, 0.72, 0.72) * rad;
							const float3 ta3_b = (-r3_b - o_b) * inv_db;
							const float3 tb3_b = ( r3_b - o_b) * inv_db;
							const float3 ten3_b = min(ta3_b, tb3_b);
							const float3 tex3_b = max(ta3_b, tb3_b);
							float ten_b = ten3_b.x;
							float ten2_b = -1e6;
							uint id_en_b = 4u;
							if (ten3_b.y > ten_b) { ten2_b = ten_b; ten_b = ten3_b.y; id_en_b = 5u; } else { ten2_b = ten3_b.y; }
							if (ten3_b.z > ten_b) { ten2_b = ten_b; ten_b = ten3_b.z; id_en_b = 6u; } else if (ten3_b.z > ten2_b) { ten2_b = ten3_b.z; }
							const float tex_b = min(tex3_b.x, min(tex3_b.y, tex3_b.z));
							const bool hit1 = (t_enter < t_exit && t_enter < t_rock);
							const bool hit2 = (ten_b < tex_b && ten_b < t_rock);
							if (hit1 && hit2)
							{
								second_t = min(second_t, max(t_enter, ten_b));
							}
							if (hit2 && (!hit1 || ten_b < t_enter))
							{
								t_enter = ten_b;
								t_enter2 = ten2_b;
								t_exit = tex_b;
								id_en = id_en_b;
								tier2_flag = 1u << 11u;
							}
						}

						if (t_enter < t_exit && t_enter < t_rock)
						{
							if (t_enter < best_t)
							{
								second_t = min(second_t, best_t);
								const float edge_dt = (t_enter - t_enter2) * layer_scale / max(rad, 1e-4);
								const float thick_norm = (t_exit - t_enter) * layer_scale / max(rad, 1e-4);
								const float ridge = max(saturate(1.0 - edge_dt * (1.0 / 0.13)), saturate(1.0 - thick_norm * (1.0 / 0.18)) * 0.55);
								best_t = t_enter;
								best_ridge = ridge;
								best_thick = saturate(thick_norm * 0.65);
								hit_h2 = h2;
								hit_rad = rad;
								hit_pack = ci | (id_en << 3u) | (id_ex << 7u) | tier2_flag;
							}
							else
							{
								second_t = min(second_t, t_enter);
							}
						}
					}
				}
			}
		}
	}

	if (hit_pack != 0xFFFFFFFFu)
	{
		if (second_t < 1e5)
		{
			const float overlap_gap = (second_t - best_t);
			best_ridge = max(best_ridge, saturate(1.0 - overlap_gap * (1.0 / 0.0014)) * 0.75);
			best_thick *= lerp(0.18, 1.0, saturate(overlap_gap * (1.0 / 0.0040)));
		}
		const uint ci = hit_pack & 7u;
		const uint id_en = (hit_pack >> 3u) & 15u;
		const uint id_ex = (hit_pack >> 7u) & 15u;
		const uint is_tier2 = (hit_pack >> 11u) & 1u;
		const int3 cid = base + int3(int(ci & 1u), int((ci >> 1u) & 1u), int(ci >> 2u));
		const float j_min = is_tabular ? 0.27 : 0.18;
		const float j_span = is_tabular ? 0.46 : 0.64;
		float3 ctr = float3(cid) + float3(
			j_min + j_span * (float(hit_h2 & 0xFFu) * (1.0 / 255.0)),
			j_min + j_span * (float((hit_h2 >> 8u) & 0xFFu) * (1.0 / 255.0)),
			j_min + j_span * (float((hit_h2 >> 16u) & 0xFFu) * (1.0 / 255.0))
		);
		if (is_tabular)
		{
			const float z_ctr_h = dot(p_surf - ctr, N_grid) / layer_scale;
			const float z_pulled_h = 0.0055 + 0.0095 * saturate((z_ctr_h + 0.014) * (1.0 / 0.050));
			ctr += N_grid * ((z_ctr_h - z_pulled_h) * layer_scale);
		}
		out_rot_hash = OreWangHash(hit_h2 ^ 0x27d4eb2du);
		float3 rv1, rv2;
		if (is_tabular)
		{
			OreGemHouseholderAxesTabular(out_rot_hash, N_grid, rv1, rv2);
		}
		else
		{
			OreGemHouseholderAxes(out_rot_hash, rv1, rv2);
		}
		const uint ht = OreWangHash(hit_h2 ^ 0x85ebca6bu);
		const float rx = float(ht & 0xFFu) * (1.0 / 255.0);
		const float ry = float((ht >> 8u) & 0xFFu) * (1.0 / 255.0);
		const float rz = float((ht >> 16u) & 0xFFu) * (1.0 / 255.0);
		const float rw = float((ht >> 24u) & 0xFFu) * (1.0 / 255.0);
		const float3 stretch = is_tabular
			? float3(0.86 + 0.28 * rx, 1.95 + 0.75 * ry, 0.86 + 0.28 * rz)
			: float3(0.82 + 0.36 * rx, 0.82 + 0.36 * ry, 0.78 + 0.42 * rz);
		const float3 o_loc = OreGemRotFwd(p_surf - ctr, rv1, rv2);
		const float3 d_loc = OreGemRotFwd(D_grid, rv1, rv2);
		const float3 d_s = d_loc * stretch;

		float3 dir_en = OreGemSlabDir(id_en);
		const float3 dir_ex = OreGemSlabDir(id_ex);
		if (is_tabular && is_tier2 != 0u)
		{
			const float2 tilt_b = float2(rx - 0.5, rz - 0.5) * 0.56;
			dir_en = float3((dir_en.x + dir_en.z) * 0.70710678 + tilt_b.x * dir_en.y, dir_en.y, (dir_en.x - dir_en.z) * 0.70710678 + tilt_b.y * dir_en.y);
		}
		const float sign_en = dot(dir_en, d_s) < 0.0 ? 1.0 : -1.0;
		const float sign_ex = dot(dir_ex, d_s) >= 0.0 ? 1.0 : -1.0;

		out_N_grid = normalize(OreGemRotInv(dir_en * stretch * sign_en, rv1, rv2));
		out_Npav_grid = normalize(OreGemRotInv(dir_ex * stretch * sign_ex, rv1, rv2));
		float3 q_hit = (o_loc + d_loc * best_t) / max(hit_rad, 1e-4);
		if (is_tabular && is_tier2 != 0u)
		{
			const float2 tilt_b = float2(rx - 0.5, rz - 0.5) * 0.56;
			const float3 off_b = float3((rw >= 0.5 ? 0.34 : -0.34), (ry - 0.5) * 0.26, (ry >= 0.5 ? 0.30 : -0.30));
			const float3 q_s = q_hit * stretch;
			const float3 q_b = float3((q_s.x + q_s.z) * 0.70710678, q_s.y + dot(q_s.xz, tilt_b), (q_s.x - q_s.z) * 0.70710678) - off_b;
			q_hit = q_b * float3(1.0 / 0.76, 1.0 / 0.72, 1.0 / 0.72);
		}
		else if (is_tabular)
		{
			q_hit *= stretch * float3(1.0 / 0.92, 1.0 / 0.74, 1.0 / 0.92);
		}
		out_q_loc = q_hit;
		out_hit_meta = (hit_h2 & ~1u) | is_tier2;
	}
}

// 3D pinpoint gem glitter locked onto the ray-traced 3D crystal surface (flashes with head/eye angle and shimmers gently):
inline half3 EvalOreGemGlitter(float3 P_hit, float3 V, float seed)
{
	const float3 grid = P_hit * 290.0 + seed * 4.3;
	const int3 cell = int3(floor(grid));
	const float3 f = grid - float3(cell);
	const uint h = OreWangHash(OreHash3(cell) ^ uint(seed * 137.0));
	const float r0 = float(h & 0xFFFFu) * (1.0 / 65535.0);
	if (r0 < 0.44)
		return 0;
	const float r1 = float((h >> 16u) & 0xFFu) * (1.0 / 255.0);
	const float r2 = float((h >> 24u) & 0xFFu) * (1.0 / 255.0);
	const float3 pt = float3(0.24 + 0.52 * r1, 0.24 + 0.52 * r2, 0.24 + 0.52 * frac(r0 * 19.3));
	const float spot = smoothstep(0.38, 0.05, length(f - pt));
	if (spot <= 0.0)
		return 0;
	const float3 axis = normalize(frac(r0 * float3(13.17, 71.31, 37.73)) * 2.0 - 1.0 + 0.001);
	const float phase = dot(V, axis) * 64.0 + r0 * 44.0 + GetTime() * (1.2 + r1 * 1.8);
	const float wR = saturate(sin(phase - 0.16));
	const float wG = saturate(sin(phase));
	const float wB = saturate(sin(phase + 0.16));
	const float3 flash = float3(
		wR > 0.0 ? pow(wR, 26.0) : 0.0,
		wG > 0.0 ? pow(wG, 26.0) : 0.0,
		wB > 0.0 ? pow(wB, 26.0) : 0.0
	);
	return (half3)(flash * (spot * 3.1));
}

// Single-channel internal pavilion double-bounce TIR + caustic brilliance:
inline float EvalOreGemFireChannel(float3 Vin, float3 Npav1, float3 Npav2, float3x3 R_w2c, float3 L_sun)
{
	const float3 R1 = reflect(Vin, Npav1);
	const float cos_inc = abs(dot(Vin, Npav1));
	const float tir = clamp((0.88 - cos_inc) * (1.0 / 0.14), 0.03, 1.0);
	const float3 R2 = reflect(R1, Npav2);

	const float d_sun = saturate(dot(R2, L_sun));
	const float sun_lobe = d_sun > 0.0 ? pow(d_sun, 46.0) * 7.2 : 0.0;

	const float3 R2_loc = mul(R_w2c, R2);
	const float3 R1_loc = mul(R_w2c, R1);
	const float cw1 = saturate(cos(R2_loc.x * 4.2 + R2_loc.y * 3.7 - R2_loc.z * 4.5));
	const float cw2 = saturate(cos(R1_loc.y * 4.6 - R1_loc.z * 3.9 + R1_loc.x * 3.3));
	const float c1 = cw1 > 0.0 ? pow(cw1, 18.0) * 4.8 : 0.0;
	const float c2 = cw2 > 0.0 ? pow(cw2, 20.0) * 3.5 : 0.0;

	const float up = saturate(R2.y * 0.5 + 0.5);
	const float sky_dome = up > 0.0 ? pow(up, 3.5) * 0.20 : 0.0;
	return tir * (sun_lobe + c1 + c2 + sky_dome);
}

// Internal crystal pavilion sub-facet refraction, corner-cube TIR, and RGB Cauchy dispersion (zero loops):
inline half4 EvalOreGemInternalFire(float3 V, float3 N_crown, float3 Npav_exit, float3 q_loc, float hm, float3x3 R_w2c, float3 L_sun)
{
	const float3 I = -V;
	const float3 Vin_R = normalize(refract(I, N_crown, 1.0 / 2.26));
	const float3 Vin_G = normalize(refract(I, N_crown, 1.0 / 2.42));
	const float3 Vin_B = normalize(refract(I, N_crown, 1.0 / 2.62));

	// Offset internal cleavage origin slightly from crystal center so raw crystals show natural asymmetric triangular facets:
	const float3 q_pav = (q_loc + float3(0.29, -0.18, 0.23)) * 1.32 + mul(R_w2c, Vin_G) * (0.62 + 0.48 * hm);
	const float3 sg = float3(q_pav.x >= 0.0 ? 1.0 : -1.0, q_pav.y >= 0.0 ? 1.0 : -1.0, q_pav.z >= 0.0 ? 1.0 : -1.0);
	const float3 a = abs(q_pav);

	float v1 = (a.x + a.y + a.z) * 0.57735027;
	float3 n1 = sg * 0.57735027;

	float min_a = a.x;
	float3 sg_flip = float3(-sg.x, sg.y, sg.z);
	if (a.y < min_a) { min_a = a.y; sg_flip = float3(sg.x, -sg.y, sg.z); }
	if (a.z < min_a) { min_a = a.z; sg_flip = float3(sg.x, sg.y, -sg.z); }
	float v2 = (a.x + a.y + a.z - 2.0 * min_a) * 0.57735027;
	float3 n2 = sg_flip * 0.57735027;

	const float v_dxy = (a.x + a.y) * (0.70710678 * 0.98);
	const float3 n_dxy = float3(sg.x, sg.y, 0.0) * 0.70710678;
	if (v_dxy > v1) { v2 = v1; n2 = n1; v1 = v_dxy; n1 = n_dxy; }
	else if (v_dxy > v2) { v2 = v_dxy; n2 = n_dxy; }

	const float v_dyz = (a.y + a.z) * (0.70710678 * 0.98);
	const float3 n_dyz = float3(0.0, sg.y, sg.z) * 0.70710678;
	if (v_dyz > v1) { v2 = v1; n2 = n1; v1 = v_dyz; n1 = n_dyz; }
	else if (v_dyz > v2) { v2 = v_dyz; n2 = n_dyz; }

	const float v_dzx = (a.z + a.x) * (0.70710678 * 0.98);
	const float3 n_dzx = float3(sg.x, 0.0, sg.z) * 0.70710678;
	if (v_dzx > v1) { v2 = v1; n2 = n1; v1 = v_dzx; n1 = n_dzx; }
	else if (v_dzx > v2) { v2 = v_dzx; n2 = n_dzx; }

	const float3 Npav1 = Npav_exit;
	const float3 Npav2 = mul(transpose(R_w2c), n1);
	const float int_seam = saturate(1.0 - (v1 - v2) * (1.0 / 0.042));

	const float fR = EvalOreGemFireChannel(Vin_R, Npav1, Npav2, R_w2c, L_sun);
	const float fG = EvalOreGemFireChannel(Vin_G, Npav1, Npav2, R_w2c, L_sun);
	const float fB = EvalOreGemFireChannel(Vin_B, Npav1, Npav2, R_w2c, L_sun);
	return half4((half)fR, (half)fG, (half)fB, (half)int_seam);
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
	const float2 uv0_pre_pom = uvsets.xy;
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
		if (material.IsVertexFlow() && IsFlowing(edge_encoded))
		{
			const LiquidFlow flow = GetLiquidFlow(uvsets.xy, edge_encoded);
			base_map = material.textures[BASECOLORMAP].Sample(sampler_objectshader, float4(flow.uv0, uvsets.zw)) * flow.weight0 +
				material.textures[BASECOLORMAP].Sample(sampler_objectshader, float4(flow.uv1, uvsets.zw)) * (1 - flow.weight0);
		}
		else if (material.IsFlow())
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
		if (material.IsVertexFlow() && IsFlowing(edge_encoded))
		{
			const LiquidFlow flow = GetLiquidFlow(uvsets.xy, edge_encoded);
			bump_map = material.textures[NORMALMAP].Sample(sampler_objectshader, float4(flow.uv0, uvsets.zw)).rg * flow.weight0 +
				material.textures[NORMALMAP].Sample(sampler_objectshader, float4(flow.uv1, uvsets.zw)).rg * (1 - flow.weight0);
		}
		else if (material.IsFlow())
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
		if (material.IsVertexFlow() && IsFlowing(edge_encoded))
		{
			const LiquidFlow flow = GetLiquidFlow(uvsets.xy, edge_encoded);
			emissiveMap = material.textures[EMISSIVEMAP].Sample(sampler_objectshader, float4(flow.uv0, uvsets.zw)) * flow.weight0 +
				material.textures[EMISSIVEMAP].Sample(sampler_objectshader, float4(flow.uv1, uvsets.zw)) * (1 - flow.weight0);
		}
		else if (material.IsFlow())
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

#if !defined(PREPASS) && !defined(WATER) && !defined(TRANSPARENT) && !defined(ENVMAPRENDERING) && !defined(SHEEN) && !defined(CLEARCOAT) && !defined(ANISOTROPIC) && !defined(CARTOON) && !defined(TERRAINBLENDED) && !defined(PLANARREFLECTION) && !defined(INTERIORMAPPING) && !defined(UNLIT) && defined(OBJECTSHADER_USE_UVSETS) && defined(OBJECTSHADER_USE_TANGENT)
	half3 ore_gem_fire_unit = 0;
	[branch]
	if (material.IsOreOverlay() && material.textures[SHEENCOLORMAP].IsValid())
	{
		const float coverage = f16tof32(material.userdata.x);
		const float ore_scale = f16tof32(material.userdata.x >> 16u);
		const float style_blend = f16tof32(material.userdata.y);
		const float rock_height_bias = f16tof32(material.userdata.y >> 16u);
		const float rim_strength = f16tof32(material.userdata.z);
		const float sparkle_strength = f16tof32(material.userdata.z >> 16u);
		const float ore_seed = f16tof32(material.userdata.w);
		const float uv_scale = f16tof32(material.userdata.w >> 16u);

		const float3 T_unit = any(TBN[0]) ? normalize(TBN[0]) : float3(1, 0, 0);
		const float3 B_unit = any(TBN[1]) ? normalize(TBN[1]) : float3(0, 1, 0);
		const float3 N_geom = surface.N;
		const float meters_per_uv = 0.5 / max(abs(material.texMulAdd.x), 1e-4);
		const float2 pom_uv_delta = uvsets.xy - uv0_pre_pom;
		const float rock_h = material.textures[DISPLACEMENTMAP].IsValid()
			? (float)material.textures[DISPLACEMENTMAP].Sample(sampler_objectshader, uvsets).r
			: 0.5;
		const float pom_fade = saturate((16.0 - dist) * (1.0 / 6.0));
		const float pom_depth_m = (float)material.GetParallaxOcclusionMapping() * meters_per_uv * pom_fade;
		const float3 P_pom = surface.P
			+ (T_unit * pom_uv_delta.x + B_unit * pom_uv_delta.y) * meters_per_uv
			- N_geom * ((1.0 - rock_h) * pom_depth_m * 0.65);

#ifdef OBJECTSHADER_USE_COMMON
		const float ore_edge_raw = (float)input.ao_wet.w;
#else
		const float ore_edge_raw = 1.0;
#endif
		const float ore_edge_dist = DecodeOreDepositEdgeDist(ore_edge_raw, uv0_pre_pom, material.texMulAdd.xy);
		const float ore_edge_noise = OreNoise3D(P_pom * 4.2 + float3(ore_seed * 1.7, ore_seed * 3.1, ore_seed * 2.3));
		const float ore_edge_eff = ore_edge_dist + ore_edge_noise * 0.020 * saturate((ore_edge_dist - 0.015) * 14.0);
		const float ore_taper = smoothstep(0.018, 0.145, ore_edge_eff);

		[branch]
		if (style_blend > 0.82)
		{
			// 3D ray-traced polyhedral crystal mode:
			//	style_blend > 0.91 -> Diamond Ore (sharp {111} octahedral gems + TIR dispersion + starlight glitter)
			//	style_blend <= 0.91 -> Uranium Ore (stepped square-tabular Autunite crystal books in crusty olive-sage vugs)
			const bool is_tabular = (style_blend < 0.91);
			const uint seed_u = OreWangHash(uint(ore_seed * 100.0) ^ 0x13579bdfu);
			const float3x3 R_grid = OreGemRotMatrix(seed_u);
			const float3 N_grid = mul(R_grid, N_geom);
			const float3 s_off0 = float3(ore_seed * 0.37, ore_seed * 0.83, ore_seed * 1.29);

			const float gem_scale = is_tabular ? (ore_scale * 5.20) : (ore_scale * 3.45);
			const float gem_thresh = is_tabular ? 0.02 : saturate(1.0 - coverage * 3.65);

			// Construct eye ray entering the POM slab (fades tangent parallax past 14m or extreme >74deg grazing):
			const float VdotN_raw = dot(surface.V, N_geom);
			const float VdotN_safe = max(VdotN_raw, 0.28);
			const float3 V_tan_raw = surface.V - N_geom * VdotN_raw;
			float gem_par_fade = saturate((16.0 - dist) * (1.0 / 5.0));
			if (material.IsParallaxEdgeFade() && material.IsEdgeBevel())
			{
				const float2 edge_d = DecodeEdgeDistance(edge_encoded);
				gem_par_fade *= smoothstep(0.0, 0.08, min(edge_d.x, edge_d.y));
			}
			const float3 V_ray = normalize(V_tan_raw * gem_par_fade + N_geom * VdotN_safe);
			const float3 D_world = -V_ray;

			// Crusty meta-autunite textures sampled uniformly per material; only applied inside actual 3D crystal vug sockets (gem_sock):
			half3 crust_tex = 0;
			half2 crust_nrm = 0;
			const bool has_crust_nrm = material.textures[CLEARCOATNORMALMAP].IsValid();
			if (is_tabular)
			{
				const float2 vug_uv = uvsets.xy * uv_scale + float2(ore_seed * 0.37, ore_seed * 0.71);
				const float4 vug_uv4 = float4(vug_uv, vug_uv);
				crust_tex = material.textures[SHEENCOLORMAP].Sample(sampler_objectshader, vug_uv4).rgb;
				if (has_crust_nrm)
				{
					crust_nrm = material.textures[CLEARCOATNORMALMAP].Sample(sampler_objectshader, vug_uv4).rg * 2.0h - 1.0h;
					crust_nrm.g = -crust_nrm.g;
				}
			}

			const float slab_depth = max(pom_depth_m, 0.022 * pom_fade);
			float z_rock = (pom_depth_m > 0.001) ? ((1.0 - rock_h) * slab_depth) : 0.013;
			if (is_tabular)
			{
				z_rock += 0.007 * pom_fade;
			}
			const float t_rock = z_rock / max(dot(V_ray, N_geom), 0.28);

			const float3 P_surf_grid = mul(R_grid, surface.P);
			const float3 P_mid_grid = mul(R_grid, surface.P + D_world * 0.010);
			const float3 D_dir_grid = mul(R_grid, D_world);

			float gem_t = 1e6;
			float gem_thick = 0.0;
			float gem_ridge = 0.0;
			float gem_sock = 0.0;
			float3 gem_N_grid = N_grid;
			float3 gem_Npav_grid = -N_grid;
			float3 gem_q_loc = 0;
			uint gem_rot_hash = 1u;
			uint gem_hit_meta = 0u;

			if (ore_taper > 0.001)
			{
				EvalOreGemRay(
					P_surf_grid * gem_scale + s_off0, P_mid_grid * gem_scale + s_off0, D_dir_grid * gem_scale, N_grid,
					t_rock, gem_scale, gem_thresh, ore_taper, is_tabular, seed_u ^ 0x243f6a88u,
					gem_t, gem_ridge, gem_thick, gem_sock, gem_N_grid, gem_Npav_grid, gem_q_loc, gem_rot_hash, gem_hit_meta
				);
			}

			const float mask = (gem_t < 1e5) ? saturate((t_rock - gem_t) * 1800.0) : 0.0;
			const float vug_mask = is_tabular ? smoothstep(0.52, 0.88, gem_sock) : 0.0;

			if (is_tabular && vug_mask > 0.001 && mask < 0.999)
			{
				// Crusty pale-sage & dark moss-olive meta-autunite strictly inside deep multi-crystal crevices (never haloing outer square edges):
				const float cl_n = saturate(0.45 + 0.85 * OreNoise3D(P_pom * 22.0 + s_off0));
				const half3 crust_col = lerp(half3(0.016h, 0.032h, 0.004h), crust_tex * half3(0.68h, 0.74h, 0.42h), (half)cl_n);
				if ((GetFrame().options & OPTION_BIT_DISABLE_ALBEDO_MAPS) == 0)
				{
					surface.baseColor.rgb = lerp(surface.baseColor.rgb, crust_col, (half)vug_mask);
				}
				if (has_crust_nrm)
				{
					surface.bumpColor.rg = lerp(surface.bumpColor.rg, surface.bumpColor.rg * 0.30h + crust_nrm * 1.15h, (half)vug_mask);
				}
				surfaceMap = lerp(surfaceMap, half4(1.0h, 0.48h, 0.0h, 0.05h), (half)vug_mask);
			}

			const float ao_gain = is_tabular ? 0.46 : 0.62;
			float outer_ao = 1.0 - ao_gain * min(rim_strength, 1.35) * (gem_sock > 0.0 ? pow(gem_sock, 1.5) : 0.0) * (1.0 - mask);
			surface.occlusion *= (half)saturate(lerp(outer_ao, 1.0, mask));

			if (mask > 0.001)
			{
				const float dist_fade = saturate(1.0 - max(dist - 18.0, 0.0) * 0.04);
				const float3 gem_N_raw = normalize(mul(transpose(R_grid), gem_N_grid));
				const float3 gem_Npav_world = normalize(mul(transpose(R_grid), gem_Npav_grid));
				const float3x3 R_w2c = mul(OreGemRotMatrix(gem_rot_hash), R_grid);
				float3 gem_N_shaded = gem_N_raw;

				const float t0_len = max(length(TBN[0]), 1e-4);
				const float t1_len = max(length(TBN[1]), 1e-4);
				const float t2_len = max(length(TBN[2]), 1e-4);

				if (is_tabular)
				{
					// Tabular tetragonal Autunite crystal plates & stacked micaceous books:
					float3 rv1_h, rv2_h;
					OreGemHouseholderAxesTabular(gem_rot_hash, N_grid, rv1_h, rv2_h);
					const float3 n_loc = OreGemRotFwd(gem_N_grid, rv1_h, rv2_h);
					const float is_basal = smoothstep(0.68, 0.88, abs(n_loc.y));
					const float3 c_up_world = normalize(mul(transpose(R_grid), OreGemRotInv(float3(0.0, 1.0, 0.0), rv1_h, rv2_h)));

					// Parallel micaceous sheet cleavage steps along side bevels of thick Autunite crystal books:
					const float lam_wave = sin(gem_q_loc.y * 36.0);
					gem_N_shaded = normalize(gem_N_shaded + c_up_world * (lam_wave * 0.17 * (1.0 - is_basal)));
					const float zn = dot(gem_N_shaded, N_geom);
					if (zn < 0.22)
					{
						gem_N_shaded = normalize(gem_N_shaded + (0.22 - zn) * N_geom);
					}
					const float3 gem_N_world = normalize(lerp(N_geom, gem_N_shaded, dist_fade));

					const float r_dark1 = float((gem_hit_meta >> 8u) & 0xFFu) * (1.0 / 255.0);
					const float r_dark2 = float((gem_hit_meta >> 16u) & 0xFFu) * (1.0 / 255.0);
					const bool is_tier2 = (gem_hit_meta & 1u) != 0u;
					const float r_dark = is_tier2 ? r_dark2 : r_dark1;
					const float olive_dark = (r_dark < 0.38) ? (0.52 + 0.44 * (r_dark * (1.0 / 0.38))) : (0.12 * r_dark);

					// Concentric square/rectangular growth zoning on {001} plates + sulfur-canary {101} bevel rims:
					const float sq_r = saturate(max(abs(gem_q_loc.x), abs(gem_q_loc.z)));
					const float sq_band = 0.5 + 0.5 * cos(sq_r * 16.0 + r_dark * 6.283);
					const float z_body = saturate(0.26 + 0.54 * sq_r + 0.20 * sq_band + (1.0 - is_basal) * 0.08 * lam_wave);
					const float z_sulfur = saturate(gem_ridge * 0.82 + smoothstep(0.74, 0.99, sq_r) * 0.42);

					const half3 deep_chartreuse = half3(0.036h, 0.078h, 0.003h);
					const half3 vivid_autunite = half3(0.275h, 0.430h, 0.008h);
					const half3 bright_sulfur = half3(0.75h, 0.88h, 0.045h);
					half3 aut_col = lerp(deep_chartreuse, vivid_autunite, (half)z_body);
					aut_col = lerp(aut_col, bright_sulfur, (half)z_sulfur);
					const half3 olive_tone = lerp(half3(1.0h, 1.0h, 1.0h), half3(0.18h, 0.26h, 0.12h), (half)olive_dark);
					aut_col *= olive_tone;

					if ((GetFrame().options & OPTION_BIT_DISABLE_ALBEDO_MAPS) == 0)
					{
						surface.baseColor.rgb = lerp(surface.baseColor.rgb, aut_col, (half)mask);
					}

					const half3 gem_bump = half3(
						(half)(dot(gem_N_world, T_unit) / t0_len),
						(half)(dot(gem_N_world, B_unit) / t1_len),
						(half)(max(dot(gem_N_world, N_geom), 0.22) / t2_len)
					);
					surface.bumpColor = lerp(surface.bumpColor, gem_bump, (half)mask);

					// Vitreous-pearly mirror {001} basal plates catch crisp square specular glints + deep crevice AO between overlapping plates:
					const half aut_rough = (half)lerp(0.18, 0.068, is_basal * (1.0 - 0.45 * gem_ridge));
					const half aut_ao = (half)saturate(0.36 + 0.64 * gem_thick);
					surfaceMap = lerp(surfaceMap, half4(aut_ao, aut_rough, 0.0h, 0.12h), (half)mask);

#ifdef OBJECTSHADER_USE_EMISSIVE
					if (sparkle_strength > 0.0)
					{
						// Subtle natural uranyl-ion rim fluorescence along thin chartreuse crystal edges (no polka-dot glitter):
						const float fluor = (0.025 + 0.075 * z_sulfur) * (1.0 - 0.65 * olive_dark) * saturate(sparkle_strength);
						surface.emissiveColor += half3(0.22h, 0.44h, 0.015h) * (half)(fluor * mask);
					}
#endif // OBJECTSHADER_USE_EMISSIVE
				}
				else
				{
					const float zn = dot(gem_N_shaded, N_geom);
					if (zn < 0.24)
					{
						gem_N_shaded = normalize(gem_N_shaded + (0.24 - zn) * N_geom);
					}
					const float3 gem_N_world = normalize(lerp(N_geom, gem_N_shaded, dist_fade));

					const half4 fire_and_seam = EvalOreGemInternalFire(
						surface.V, gem_N_raw, gem_Npav_world, gem_q_loc, gem_thick, R_w2c, (float3)GetSunDirection()
					);
					ore_gem_fire_unit = fire_and_seam.rgb * (half)(mask * saturate(sparkle_strength * 0.36));

					// Deep glassy obsidian-ice absorption core + crisp frosty highlight along razor-sharp 3D facet ridges:
					const float edge_catch = 0.35 + 1.45 * saturate(gem_N_raw.y * 0.65 + dot(gem_N_raw, (float3)GetSunDirection()) * 0.45);
					const half3 gem_core = half3(0.012h, 0.022h, 0.036h);
					const half3 gem_edge = half3(0.78h, 0.90h, 1.0h) * (half)(gem_ridge * 0.24 * edge_catch + (float)fire_and_seam.a * 0.035);
					const half3 gem_col = gem_core + gem_edge;

					if ((GetFrame().options & OPTION_BIT_DISABLE_ALBEDO_MAPS) == 0)
					{
						surface.baseColor.rgb = lerp(surface.baseColor.rgb, gem_col, (half)mask);
					}

					const half3 gem_bump = half3(
						(half)(dot(gem_N_world, T_unit) / t0_len),
						(half)(dot(gem_N_world, B_unit) / t1_len),
						(half)(max(dot(gem_N_world, N_geom), 0.24) / t2_len)
					);
					surface.bumpColor = lerp(surface.bumpColor, gem_bump, (half)mask);

					const half gem_rough = lerp(0.016h, 0.11h, (half)gem_ridge);
					surfaceMap = lerp(surfaceMap, half4(1.0h, gem_rough, 0.0h, 0.20h), (half)mask);

#ifdef OBJECTSHADER_USE_EMISSIVE
					if (sparkle_strength > 0.0)
					{
						const float glitter_fade = saturate(1.0 - max(dist - 16.0, 0.0) * 0.06);
						const float3 P_hit = surface.P + D_world * gem_t;
						const half3 glit = EvalOreGemGlitter(P_hit, surface.V, ore_seed);
						surface.emissiveColor += glit * (half)(sparkle_strength * mask * glitter_fade);
					}
#endif // OBJECTSHADER_USE_EMISSIVE
				}
			}
		}
		else
		{
			// Single evaluation of 3D vein/seam/pocket field, smoothly pinched along seam spine to sharp tips before deposit boundaries:
			const bool is_coal = (style_blend < 0.07);
			const float field = (ore_taper > 0.001) ? EvalOreVeinField(P_pom, ore_scale, style_blend, ore_seed) : -1.0;
			const float h_mod = (0.5 - rock_h) * rock_height_bias * (is_coal ? 0.11 : 0.16);
			const float signed_ore = (ore_taper > 0.001)
				? ((field + h_mod * ore_taper) - (1.0 - coverage * ore_taper))
				: -1.0;
			const float mask = smoothstep(0.0, is_coal ? 0.0075 : 0.0095, signed_ore);

			const float norm_span = is_coal ? 0.105 : lerp(0.20, 0.14, style_blend);
			const float u_crown = saturate(signed_ore / norm_span);
			const float crown = u_crown > 0.0 ? pow(u_crown, is_coal ? 0.36 : lerp(0.50, 0.62, style_blend)) : 0.0;

			// Screen-space derivatives of smooth macro crown + world pos (outside inner branches for uniform quad ops):
			const float crown_dx = ddx_fine(crown);
			const float crown_dy = ddy_fine(crown);
			const float3 P_dx = ddx_fine(P_pom);
			const float3 P_dy = ddy_fine(P_pom);

			// Analytic 3D cleavage & hackly fracture facets (exact per-pixel derivatives, zero extra field calls):
			float facets = 1.0;
			float3 grad_facets = 0;
			if (crown > 0.001)
			{
				const float3 f_off = float3(ore_seed * 5.3, ore_seed * 11.7, ore_seed * 17.1);
				const float freq1 = ore_scale * (is_coal ? 7.4 : 5.4);
				const float freq2 = ore_scale * (is_coal ? 17.2 : 12.0);
				const float4 n1g = OreNoise3DGrad(P_pom * freq1 + f_off);
				const float4 n2g = OreNoise3DGrad(P_pom * freq2 - f_off * 0.73);
				const float a1 = abs(n1g.x);
				const float a2 = abs(n2g.x);
				const float k1 = is_coal ? 1.95 : 1.65;
				const float k2 = is_coal ? 2.15 : 1.75;
				const float r1_val = 1.0 - saturate(a1 * k1);
				const float r2_val = 1.0 - saturate(a2 * k2);
				const float s1 = n1g.x * rsqrt(n1g.x * n1g.x + (is_coal ? 0.0012 : 0.0025));
				const float s2 = n2g.x * rsqrt(n2g.x * n2g.x + (is_coal ? 0.0012 : 0.0025));
				const float3 dr1 = (a1 * k1 < 1.0) ? (-k1 * s1 * freq1 * n1g.yzw) : 0;
				const float3 dr2 = (a2 * k2 < 1.0) ? (-k2 * s2 * freq2 * n2g.yzw) : 0;

				float f_comb = 0.64 * r1_val + 0.36 * r2_val;
				float3 df_comb = 0.64 * dr1 + 0.36 * dr2;
				if (is_coal)
				{
					// Rough stepped sedimentary fracture ledges gently undulating along coal bedding:
					const float3 ax_b = float3(0.099, 0.990, 0.099);
					const float bed_p = (dot(P_pom, ax_b) * ore_scale * 21.0) + n1g.x * 1.6;
					const float lam = 0.5 + 0.5 * sin(bed_p);
					const float3 dlam = (0.5 * cos(bed_p)) * (ax_b * (ore_scale * 21.0) + n1g.yzw * (freq1 * 1.6));
					f_comb = 0.52 * r1_val + 0.28 * r2_val + 0.20 * lam;
					df_comb = 0.52 * dr1 + 0.28 * dr2 + 0.20 * dlam;
				}
				const float facet_amp = is_coal ? 0.74 : lerp(0.36, 0.48, style_blend);
				facets = (1.0 - facet_amp) + facet_amp * f_comb;
				grad_facets = facet_amp * df_comb;
			}
			const float h_ore = crown * facets;

			// Lightweight protruding UV parallax shift along view tangent:
			const float ore_par_fade = saturate((10.0 - dist) * (1.0 / 4.0));
			const float VdotN = max(dot(surface.V, N_geom), 0.45);
			const float3 V_tan = surface.V - N_geom * dot(surface.V, N_geom);
			const float3 shift_w = V_tan * (h_ore * 0.012 * rim_strength * ore_par_fade / VdotN);
			const float2 ore_par_uv = float2(dot(shift_w, T_unit), dot(shift_w, B_unit)) / meters_per_uv;

			const float2 uv_warp = float2(
				OreNoise3D(P_pom * 1.7 + float3(ore_seed * 0.43, 3.1, 7.7)),
				OreNoise3D(P_pom * 1.7 + float3(5.9, ore_seed * 0.61, 2.3))
			);
			const float2 ore_uv = (uvsets.xy + ore_par_uv) * uv_scale + float2(ore_seed * 0.37, ore_seed * 0.71) + (is_coal ? 0.06 : 0.14) * uv_warp;
			const float4 ore_uvsets = float4(ore_uv, ore_uv);

			const half3 ore_col_raw = material.textures[SHEENCOLORMAP].Sample(sampler_objectshader, ore_uvsets).rgb;
#ifdef OBJECTSHADER_USE_COLOR
			half3 ore_col = ore_col_raw * lerp(1.0h.xxx, input.color.rgb, 0.70h) * (0.90h + 0.20h * (half)uv_warp.x);
#else
			half3 ore_col = ore_col_raw * (0.90h + 0.20h * (half)uv_warp.x);
#endif
			const half2 ore_nrm_map = material.textures[CLEARCOATNORMALMAP].IsValid()
				? material.textures[CLEARCOATNORMALMAP].Sample(sampler_objectshader, ore_uvsets).rg
				: half2(0.5, 0.5);
			half2 ore_nrm_rg = ore_nrm_map * 2.0h - 1.0h;
			ore_nrm_rg.g = -ore_nrm_rg.g;
			half4 ore_surf = material.textures[CLEARCOATMAP].IsValid()
				? material.textures[CLEARCOATMAP].Sample(sampler_objectshader, ore_uvsets)
				: half4(1.0h, 0.4h, 0.0h, 0.06h);

			if (is_coal)
			{
				// Visible dry-charcoal crag highlights vs deep soot cleat crevices + coarse matte-satin roughness:
				ore_col *= (half)(0.74 + 0.62 * facets);
				ore_surf.g = clamp(ore_surf.g + (half)(0.08 * (1.0 - facets)), 0.56h, 0.95h);
				ore_surf.a = clamp(ore_surf.a, 0.052h, 0.090h);
			}

			half2 ore_macro_bump = 0;
			const float nrm_str = (float)material.GetNormalMapStrength();
			if (nrm_str > 0 && rim_strength > 0 && (crown > 0.001 || abs(crown_dx) + abs(crown_dy) > 1e-5))
			{
				const float3 r1 = cross(P_dy, N_geom);
				const float3 r2 = cross(N_geom, P_dx);
				const float det = dot(P_dx, r1);
				float3 grad_crown = 0;
				if (abs(det) > 1e-12)
				{
					grad_crown = (crown_dx * r1 + crown_dy * r2) / det;
				}
				const float3 grad_h = grad_crown * facets + crown * grad_facets;
				const float relief_gain = (is_coal ? 0.056 : 0.038) * rim_strength * lerp(0.95, 1.25, style_blend);
				float2 slope = float2(-dot(grad_h, T_unit), -dot(grad_h, B_unit)) * relief_gain;
				const float slope_len = length(slope);
				const float max_slope = is_coal ? 2.10 : 1.65;
				if (slope_len > max_slope)
				{
					slope *= max_slope / slope_len;
				}
				const float dist_fade = saturate(1.0 - max(dist - 18.0, 0.0) * 0.04);
				ore_macro_bump = half2((half)(slope.x * dist_fade), (half)(slope.y * dist_fade));
			}

			const float edge_t = smoothstep(-0.024, 0.0, signed_ore);
			const float outer_ao = 1.0 - (is_coal ? 0.72 : 0.58) * rim_strength * (edge_t > 0.0 ? pow(edge_t, 1.55) : 0.0) * (1.0 - mask);
			const float inner_ao = is_coal ? lerp(0.48, 1.05, saturate(facets * 1.12)) : lerp(0.76, 1.04, saturate(h_ore * 1.15));
			const float depth_ao = lerp(outer_ao, inner_ao, mask);

			if ((GetFrame().options & OPTION_BIT_DISABLE_ALBEDO_MAPS) == 0)
			{
				if (is_coal && edge_t > 0.001 && mask < 0.999)
				{
					// Subtle carbonaceous shale staining in the recessed rock bedding slot right at the coal seam contact:
					const half stain = (half)(0.34 * edge_t * edge_t * (1.0 - mask));
					surface.baseColor.rgb *= (1.0h - stain);
				}
				surface.baseColor.rgb = lerp(surface.baseColor.rgb, ore_col, (half)mask);
			}
			if (nrm_str > 0)
			{
				const half rock_carry = is_coal ? 0.04h : (half)lerp(0.16, 0.08, style_blend);
				const half ore_nrm_scale = is_coal ? min((half)(nrm_str * 1.45), 2.35h) : min((half)(nrm_str * 1.05), 1.95h);
				const half2 rock_nrm = surface.bumpColor.rg;
				const half2 mineral_nrm = rock_nrm * rock_carry + ore_nrm_rg * ore_nrm_scale;
				surface.bumpColor.rg = lerp(rock_nrm, mineral_nrm, (half)mask) + ore_macro_bump;
				surface.bumpColor.b = 1.0h;
			}
			surfaceMap = lerp(surfaceMap, ore_surf, (half)mask);
			surface.occlusion *= (half)saturate(depth_ao);

#ifdef OBJECTSHADER_USE_EMISSIVE
			if (sparkle_strength > 0 && mask > 0.15)
			{
				const half sp = OreSparkle(P_pom + shift_w, surface.V, ore_seed);
				surface.emissiveColor += ore_col * ((half)(sparkle_strength * mask) * sp);
			}
#endif // OBJECTSHADER_USE_EMISSIVE
		}
	}
#endif // !PREPASS && !WATER && !TRANSPARENT && !ENVMAPRENDERING && !SHEEN && !CLEARCOAT && !ANISOTROPIC && !CARTOON && !TERRAINBLENDED && !PLANARREFLECTION && !INTERIORMAPPING && !UNLIT && OBJECTSHADER_USE_UVSETS && OBJECTSHADER_USE_TANGENT

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
		[branch]
		if (material.IsVertexFlow() && IsFlowing(edge_encoded))
		{
			// Flowing water: the swells run along the flow, the ripples follow faster and grow with the speed
			const LiquidFlow swell = GetLiquidFlow(UV_normalMap, edge_encoded);
			const LiquidFlow ripple = GetLiquidFlow(UV_normalMap * 2.13, edge_encoded * 2.6);
			const half speed = (half)saturate(length(edge_encoded) * 4);
			bumpColor0 = (2 * (texture_normalmap.Sample(sampler_objectshader, swell.uv0).rg * swell.weight0 +
				texture_normalmap.Sample(sampler_objectshader, swell.uv1).rg * (1 - swell.weight0)) - 1) * half2(1, -1);
			bumpColor1 = (2 * (texture_normalmap.Sample(sampler_objectshader, ripple.uv0).rg * ripple.weight0 +
				texture_normalmap.Sample(sampler_objectshader, ripple.uv1).rg * (1 - ripple.weight0)) - 1) * half2(1, -1) * (0.65h + 0.6h * speed);
		}
		else
		{
			bumpColor0 = (2 * texture_normalmap.Sample(sampler_objectshader, uv0).rg - 1) * half2(1, -1);
			bumpColor1 = (2 * texture_normalmap.Sample(sampler_objectshader, uv1).rg - 1) * half2(1, -1) * 0.65h;
		}
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
			float mip = (material.IsOreOverlay() ? 0.04 : lerp(surface.roughness, 0.1, material.GetCloak())) * mipLevels;
			float chromatic = (material.IsOreOverlay() ? (material.GetChromaticAberration() * 0.38) : material.GetChromaticAberration()) / size;
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

#if !defined(PREPASS) && !defined(WATER) && !defined(TRANSPARENT) && !defined(ENVMAPRENDERING) && !defined(SHEEN) && !defined(CLEARCOAT) && !defined(ANISOTROPIC) && !defined(CARTOON) && !defined(TERRAINBLENDED) && !defined(PLANARREFLECTION) && !defined(INTERIORMAPPING) && !defined(UNLIT) && defined(OBJECTSHADER_USE_UVSETS) && defined(OBJECTSHADER_USE_TANGENT)
	[branch]
	if (any(ore_gem_fire_unit))
	{
		const half3 sky_raw = (GetZenithColor() * 0.55h + GetHorizonColor() * 0.35h + lighting.indirect.diffuse * GetGIBoost() * 1.5h) * surface.occlusion;
		const half sky_lum = dot(sky_raw, half3(0.299h, 0.587h, 0.114h));
		const half3 sky_rad = lerp(sky_raw, sky_lum.xxx, 0.65h);
		const half3 direct_rad = lighting.direct.diffuse * (1.0h / PI);
		const half3 gem_incident = direct_rad + sky_rad + half3(0.010h, 0.013h, 0.018h);
		lighting.direct.specular += ore_gem_fire_unit * gem_incident * (1.0h - surface.F * 0.50h);
	}
#endif // !PREPASS && !WATER && ...

#if defined(TRANSPARENT) && defined(CLEARCOAT) && !defined(PREPASS) && !defined(ENVMAPRENDERING)
	[branch]
	if (material.IsOreOverlay())
	{
		// Transparent clearcoat crystal item (Diamant_Geschliffen.vitem): keeps full clear transmission and visible
		//	internal carbon imperfections while adding crisp object-space pavilion TIR and RGB Cauchy prism fire on facets
		float3 P_obj = surface.P * 3.0;
		float3x3 R_w2obj = float3x3(1, 0, 0, 0, 1, 0, 0, 0, 1);
#ifdef OBJECTSHADER_USE_INSTANCEINDEX
		const float4x4 M_inst = meshinstance.transformRaw.GetMatrix();
		const float3 c0 = float3(M_inst[0].x, M_inst[1].x, M_inst[2].x);
		const float3 c1 = float3(M_inst[0].y, M_inst[1].y, M_inst[2].y);
		const float3 c2 = float3(M_inst[0].z, M_inst[1].z, M_inst[2].z);
		const float l0_sq = dot(c0, c0);
		const float l1_sq = dot(c1, c1);
		const float l2_sq = dot(c2, c2);
		if (l0_sq > 1e-8 && l1_sq > 1e-8 && l2_sq > 1e-8)
		{
			const float3 dp = surface.P - float3(M_inst[0].w, M_inst[1].w, M_inst[2].w);
			const float inv_s0 = rsqrt(l0_sq);
			const float inv_s1 = rsqrt(l1_sq);
			const float inv_s2 = rsqrt(l2_sq);
			R_w2obj = float3x3(c0 * inv_s0, c1 * inv_s1, c2 * inv_s2);
			P_obj = float3(dot(dp, c0) * (inv_s0 * inv_s0), dot(dp, c1) * (inv_s1 * inv_s1), dot(dp, c2) * (inv_s2 * inv_s2));
		}
#endif // OBJECTSHADER_USE_INSTANCEINDEX
		const uint seed_u = OreWangHash(4370u ^ 0x517cc1b7u);
		const float3x3 R_w2c = mul(OreGemRotMatrix(seed_u), R_w2obj);
		const float3 q_loc = P_obj * 2.85;
		const float3 Vin_G = normalize(refract(-surface.V, surface.clearcoat.N, 1.0 / 2.42));
		const float3 q_rear = q_loc * 0.85 + mul(R_w2c, Vin_G) * 1.15;
		const float3 sg_rear = float3(q_rear.x >= 0.0 ? 1.0 : -1.0, q_rear.y >= 0.0 ? 1.0 : -1.0, q_rear.z >= 0.0 ? 1.0 : -1.0);
		const float3 Npav_world = normalize(mul(transpose(R_w2c), sg_rear * 0.57735027));

		const half4 fire = EvalOreGemInternalFire(
			surface.V, surface.clearcoat.N, Npav_world, q_loc, 0.70, R_w2c, (float3)GetSunDirection()
		);
		const half3 prism_flashes = max(fire.rgb - 0.25h, 0.0h);
		const half3 sky_raw = (GetZenithColor() * 0.50h + GetHorizonColor() * 0.35h + lighting.indirect.diffuse * GetGIBoost()) * surface.occlusion;
		const half sky_lum = dot(sky_raw, half3(0.299h, 0.587h, 0.114h));
		const half3 incident = lighting.direct.diffuse * (1.0h / PI) + lerp(sky_raw, sky_lum.xxx, 0.65h);
		lighting.direct.specular += prism_flashes * incident * 0.32h;
	}
#endif // TRANSPARENT && CLEARCOAT

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

