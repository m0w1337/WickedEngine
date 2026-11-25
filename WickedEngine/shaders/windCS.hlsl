#include "globals.hlsli"

RWTexture3D<float2> output : register(u0);

float gust_value(uint2 cell)
{
	uint seed = cell.x + cell.y * 57u;
	seed = (seed ^ 61u) ^ (seed >> 16u);
	seed *= 0x27d4eb2du;
	return float((seed ^ (seed >> 15u)) & 65535u) / 65535.f;
}

float gust_noise(float2 uv, uint cells)
{
	float2 p = frac(uv) * cells;
	uint2 cell = uint2(p);
	float2 t = frac(p);
	t = t * t * (3.f - 2.f * t);
	uint mask = cells - 1u;
	float bottom = lerp(gust_value(cell), gust_value((cell + uint2(1, 0)) & mask), t.x);
	float top = lerp(gust_value((cell + uint2(0, 1)) & mask), gust_value((cell + 1u) & mask), t.x);
	return lerp(bottom, top, t.y);
}

float wind_bend(float2 uv, float time, float turbulence)
{
	const float regional = gust_noise(uv, 4);
	const float gust = lerp(regional, gust_noise(uv + .41f, 8), .24f);
	// The travelling field sets the load and delays the sway across the terrain.
	// The quicker response lets stems give way and spring back within a gust.
	const float delay = (regional - .5f) * 2.8f;
	const float phase = time * 2.85f + delay;
	const float sway = .78f * sin(phase) + .22f * sin(time * 4.57f + delay * 1.45f + 1.4f);
	const float envelope = .77f + .23f * sin(time * 1.04f + delay);
	const float response = (.44f + .43f * gust) * lerp(.86f, 1.22f, saturate(.25f * turbulence));
	const float bend = .13f + .30f * gust + sway * envelope * response;
	// Allow a little elastic overshoot after release, with the strongest movement downwind.
	return bend >= 0 ? min(bend, 1.f) : (.18f * bend) / (.18f - bend);
}

float local_sway(float2 uv, float time)
{
	// Smaller eddies rock neighboring branch tips at slightly different times.
	float delay = 6.f * gust_noise(uv, 4);
	return .14f * sin(time * 4.2f + delay) + .055f * sin(time * 6.3f + delay * 1.6f);
}

[numthreads(8, 8, 8)]
void main(uint3 DTid : SV_DispatchThreadID)
{
	uint width, height, depth;
	output.GetDimensions(width, height, depth);
	const ShaderWind wind = GetWeather().wind;
	float2 uv = (float2(DTid.xz) + .5f) / float2(width, depth) - wind.gust_offset;
	float2 direction = wind.direction.xz / max(.00001f, length(wind.direction.xz));
	float2 step = direction * (GetDeltaTime() * WIND_TRAVEL_SPEED * wind.speed * WIND_FIELD_SCALE * max(.01f, wind.wavesize));
	if (DTid.y < height / 2)
		output[DTid] = float2(wind_bend(uv, GetTime(), wind.randomness), wind_bend(uv + step, GetTimePrev(), wind.randomness));
	else
	{
		float2 local_uv = (float2(DTid.xz) + .5f) / float2(width, depth) - 2.f * wind.gust_offset;
		output[DTid] = float2(local_sway(local_uv, GetTime()), local_sway(local_uv + 2.f * step, GetTimePrev()));
	}
}
