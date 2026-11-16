#include "globals.hlsli"
#include "impostorHF.hlsli"

float4 main(VSOut input STEREO_VIEWID_PARAM) : SV_TARGET
{
	STEREO_VIEWID_APPLY(stereo_view_id);
	float4 color = unpack_rgba(input.instanceColor);
	return color;
}
