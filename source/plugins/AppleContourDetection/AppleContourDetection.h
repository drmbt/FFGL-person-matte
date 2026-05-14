#pragma once

#include <FFGLSDK.h>
#include <vector>

class AppleContourDetection : public CFFGLPlugin
{
public:
	AppleContourDetection();
	~AppleContourDetection() override;

	FFResult InitGL( const FFGLViewportStruct* vp ) override;
	FFResult ProcessOpenGL( ProcessOpenGLStruct* pGL ) override;
	FFResult DeInitGL() override;

	FFResult SetFloatParameter( unsigned int dwIndex, float value ) override;
	float GetFloatParameter( unsigned int index ) override;

private:
	bool UpdateContourTexture( const FFGLTextureStruct& inputTexture );
	bool GenerateContourMask( const FFGLTextureStruct& inputTexture );
	void ReleaseContourTexture();
	void ClearMask( size_t width, size_t height );
	void DrawLine( int x0, int y0, int x1, int y1, int radius );
	void StampPoint( int centerX, int centerY, int radius );

	ffglex::FFGLShader shader;
	ffglex::FFGLScreenQuad quad;

	GLuint contourTexture;
	unsigned int contourWidth;
	unsigned int contourHeight;
	bool hasContours;
	bool loggedVisionSuccess;
	bool loggedVisionFailure;
	bool loggedVisionUnavailable;

	std::vector< unsigned char > rgbaPixels;
	std::vector< unsigned char > bgraPixels;
	std::vector< unsigned char > contourPixels;

	float contrast;
	float lineWidth;
	float opacity;
	float darkOnLight;
	float invertMask;
	float showMask;
	float blendMode;
	float maxDimension;
};
