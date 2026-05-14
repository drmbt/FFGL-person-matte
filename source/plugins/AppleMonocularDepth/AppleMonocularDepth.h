#pragma once

#include <FFGLSDK.h>
#include <vector>

class AppleMonocularDepth : public CFFGLPlugin
{
public:
	AppleMonocularDepth();
	~AppleMonocularDepth() override;

	FFResult InitGL( const FFGLViewportStruct* vp ) override;
	FFResult ProcessOpenGL( ProcessOpenGLStruct* pGL ) override;
	FFResult DeInitGL() override;

	FFResult SetFloatParameter( unsigned int dwIndex, float value ) override;
	float GetFloatParameter( unsigned int index ) override;

private:
	bool UpdateDepthTexture( const FFGLTextureStruct& inputTexture );
	bool GenerateDepthMap( const FFGLTextureStruct& inputTexture );
	bool EnsureDepthModelLoaded( unsigned int modelIndex );
	void ReleaseDepthTexture();
	void ReleaseDepthModels();

	ffglex::FFGLShader shader;
	ffglex::FFGLScreenQuad quad;

	GLuint depthTexture;
	unsigned int depthWidth;
	unsigned int depthHeight;
	bool hasDepth;
	bool loggedModelSuccess[ 2 ];
	bool loggedModelFailure[ 2 ];
	bool loggedModelUnavailable[ 2 ];
	bool loggedVisionFailure[ 2 ];

	void* coreMLModels[ 2 ];

	std::vector< unsigned char > rgbaPixels;
	std::vector< unsigned char > bgraPixels;
	std::vector< unsigned char > depthPixels;

	float opacity;
	float modelMode;
	float lowThreshold;
	float highThreshold;
	float maskMode;
	float outputMask;
};
