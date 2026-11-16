#include "skyHF.hlsli"

struct PushData
{
	uint clouds_enabled;
};
PUSHCONSTANT(push, PushData);

float4 main(float4 pos : SV_Position STEREO_VIEWID_PARAM) : SV_Target
{
	STEREO_VIEWID_APPLY(stereo_view_id);
	const float3 V = normalize(-GetCamera().screen_to_view(pos));

	float4 color = float4(GetStaticSkyColor(V, push.clouds_enabled), 1);

	color = saturateMediump(color);
	return color;
}

