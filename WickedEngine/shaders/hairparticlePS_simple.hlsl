#include "globals.hlsli"
#include "hairparticleHF.hlsli"

float4 main(VertexToPixel input STEREO_VIEWID_PARAM) : SV_TARGET
{
	STEREO_VIEWID_APPLY(stereo_view_id);
	ShaderMaterial material = HairGetMaterial();

	return material.GetBaseColor();
}
