#pragma once

#include <FFGLSDK.h>
#include <vector>

class ApplePersonSegmentation : public CFFGLPlugin
{
public:
	ApplePersonSegmentation();
	~ApplePersonSegmentation() override;

	FFResult InitGL( const FFGLViewportStruct* vp ) override;
	FFResult ProcessOpenGL( ProcessOpenGLStruct* pGL ) override;
	FFResult DeInitGL() override;

	FFResult SetFloatParameter( unsigned int dwIndex, float value ) override;
	float GetFloatParameter( unsigned int index ) override;

private:
	bool UpdateMaskTexture( const FFGLTextureStruct& inputTexture );
	bool GeneratePersonMask( const FFGLTextureStruct& inputTexture );
	void ReleaseMaskTexture();

	ffglex::FFGLShader shader;
	ffglex::FFGLScreenQuad quad;

	GLuint maskTexture;
	unsigned int maskWidth;
	unsigned int maskHeight;
	bool hasMask;
	bool loggedVisionSuccess;
	bool loggedVisionFailure;
	bool loggedVisionUnavailable;

	std::vector< unsigned char > rgbaPixels;
	std::vector< unsigned char > bgraPixels;
	std::vector< unsigned char > maskPixels;

	float threshold;
	float softness;
	float shrinkGrow;
	float feather;
	float opacity;
	float invertMask;
	float showMask;
	float quality;
	float outputMode;
};
