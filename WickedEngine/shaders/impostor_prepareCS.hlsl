#include "globals.hlsli"

static const uint THREADCOUNT = 64;

static const float3 BILLBOARD[] =
{
	float3(-1, -1, 0),
	float3(1, -1, 0),
	float3(-1, 1, 0),
	float3(1, 1, 0),
};

RWBuffer<uint> output_indices : register(u0);
RWBuffer<float4> output_vertices_pos : register(u1);
RWBuffer<float4> output_vertices_nor : register(u2);
RWByteAddressBuffer output_impostor_data : register(u3);
RWStructuredBuffer<IndirectDrawArgsIndexedInstanced> output_indirect : register(u4);

PUSHCONSTANT(push, ImpostorPreparePush);

[numthreads(THREADCOUNT, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
	[branch]
	if (DTid.x >= push.count)
		return;

	float3 center;
	float radius;
	float rotationY;
	int sliceOffset;
	float fadeDistance;
	uint color;

	[branch]
	if (push.static_impostors >= 0)
	{
		// Static impostor: placed like an object of the impostor mesh would be (position, rotation around Y, uniform scale)
		const uint4 data = bindless_buffers[descriptor_index(push.static_impostors)].Load4(DTid.x * 16);
		const float3 position = asfloat(data.xyz);
		rotationY = f16tof32(data.w);
		const float scale = f16tof32(data.w >> 16u);
		float s, c;
		sincos(rotationY, s, c);
		const float3 offset = push.center * scale;
		center = position + float3(offset.x * c + offset.z * s, offset.y, -offset.x * s + offset.z * c);
		radius = push.radius * scale;
		sliceOffset = push.slice_offset;
		fadeDistance = 0; // never swapped in by distance, its creator removes it when it is replaced with a real object
		color = ~0u;
	}
	else
	{
		const uint instanceIndex = DTid.x;
		ShaderMeshInstance instance = load_instance(instanceIndex);
		ShaderGeometry geometry = load_geometry(instance.geometryOffset);
		center = instance.center;
		radius = instance.radius;
		rotationY = atan2(-instance.transformRaw.mat2.x, instance.transformRaw.mat0.x); // local X axis in world space -> rotation around Y
		sliceOffset = geometry.impostorSliceOffset;
		fadeDistance = instance.fadeDistance;
		color = pack_rgba(instance.GetColor());
	}

	float dist = distance(GetCamera().position, center);
	const bool distance_culled = dist < (fadeDistance - radius);

	// Frustum culling:
	ShaderSphere sphere;
	sphere.center = center;
	sphere.radius = radius;

	const bool visible = sliceOffset >= 0 && !distance_culled && GetCamera().frustum.intersects(sphere);

	// Optimization: reduce to 1 atomic operation per wave
	const uint waveAppendCount = WaveActiveCountBits(visible);
	uint waveOffset;
	if (WaveIsFirstLane() && waveAppendCount > 0)
	{
		InterlockedAdd(output_indirect[0].IndexCountPerInstance, waveAppendCount * 6u, waveOffset);
	}
	waveOffset = WaveReadLaneFirst(waveOffset);

	[branch]
	if (visible)
	{
		const uint indexOffset = waveOffset + WavePrefixSum(6u);
		const uint impostorOffset = indexOffset / 6u;
		const uint vertexOffset = impostorOffset * 4u;

		// Write out indices:
		output_indices[indexOffset + 0] = vertexOffset + 0; // provoking vertex prim0
		output_indices[indexOffset + 1] = vertexOffset + 1;
		output_indices[indexOffset + 2] = vertexOffset + 2;
		output_indices[indexOffset + 3] = vertexOffset + 3; // provoking vertex prim1
		output_indices[indexOffset + 4] = vertexOffset + 2;
		output_indices[indexOffset + 5] = vertexOffset + 1;

		// We rotate the billboard to face camera, but unlike emitted particles,
		//	they don't rotate according to camera rotation, but the camera position relative
		//	to the impostor. The card faces the camera completely (also from above), its up is the world up as far as
		//	it is perpendicular to the view, like the up of the capture camera of the ring (see impostorRingCount):
		float3 origin = center;
		const float3 to_camera = GetCamera().position - origin;
		float3 face = normalize(to_camera);
		const float elevation = asin(clamp(face.y, -1, 1));
		const int ring = GetImpostorRing(max(0, elevation));
		float3 up = float3(0, 1, 0) - face * face.y;
		up = dot(up, up) > 0.000001 ? normalize(up) : float3(0, 0, 1); // straight above
		float3 right = normalize(cross(face, up));

		// Decide which slice to show according to the horizontal direction in the impostor's local space:
		float3 face_level = float3(to_camera.x, 0, to_camera.z);
		face_level = dot(face_level, face_level) > 0.000001 ? normalize(face_level) : float3(0, 0, 1);
		float s, c;
		sincos(rotationY, s, c);
		const float3 face_local = float3(face_level.x * c - face_level.z * s, 0, face_level.x * s + face_level.z * c);
		uint slice = uint(sliceOffset);
		float angle = acos(clamp(dot(face_local.xz, float2(0, 1)), -1, 1)) / PI;
		if (cross(face_local, float3(0, 0, 1)).y < 0)
		{
			angle = 2 - angle;
		}
		angle *= 0.5f;
		angle = saturate(angle - 0.0001);
		const int views = GetImpostorRingViews(ring);
		slice += uint(GetImpostorRingOffset(ring) + min(views - 1, int(angle * views))) * 3;

		const float dither = max(0, fadeDistance - dist) / radius;

		// Write out per impostor data:
		uint2 data = 0;
		data.x |= slice & 0xFFFFFF;
		data.x |= (uint(dither * 255) & 0xFF) << 24u;
		data.y = color;
		output_impostor_data.Store2(impostorOffset * sizeof(uint2), data);

		// Write out vertices:
		for (uint vertexID = 0; vertexID < 4; ++vertexID)
		{
			float3 pos = BILLBOARD[vertexID];
			pos = mul(pos, float3x3(right, up, face));
			pos *= radius;
			pos += center;
			output_vertices_pos[vertexOffset + vertexID] = float4(pos, 0);
			output_vertices_nor[vertexOffset + vertexID] = float4(face, 0);
		}
	}
}
