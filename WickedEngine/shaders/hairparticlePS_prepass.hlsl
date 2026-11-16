#include "globals.hlsli"
#include "objectHF.hlsli"
#include "hairparticleHF.hlsli"
#include "ShaderInterop_HairParticle.h"

#ifdef __PSSL__
#pragma PSSL_target_output_format (target 0 FMT_32_R)
#endif // __PSSL__

uint main(VertexToPixel input, out uint coverage : SV_Coverage STEREO_VIEWID_PARAM) : SV_Target
{
	STEREO_VIEWID_APPLY(stereo_view_id);
	ShaderMaterial material = HairGetMaterial();

	half alpha = 1;

	[branch]
	if (material.textures[BASECOLORMAP].IsValid())
	{
		alpha = material.textures[BASECOLORMAP].Sample(sampler_linear_clamp, input.tex.xyxy).a;
	}
	
	coverage = AlphaToCoverage(alpha, material.GetAlphaTest(), input.GetDither(), input.pos);

	return input.primitiveID;
}
