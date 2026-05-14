#include "AppleContourDetection.h"

#if defined( __APPLE__ )
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <simd/simd.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>

using namespace ffglex;

enum ParamType : FFUInt32
{
	PT_CONTRAST,
	PT_LINE_WIDTH,
	PT_HUE,
	PT_SATURATION,
	PT_BRIGHTNESS,
	PT_ALPHA,
	PT_OPACITY,
	PT_COMP_OVER_INPUT
};

static CFFGLPluginInfo PluginInfo(
	PluginFactory< AppleContourDetection >,
	"APCT",
	"Apple Contour Detection",
	2,
	1,
	1,
	0,
	FF_EFFECT,
	"Apple Vision contour lines for live video",
	"Apple Vision FFGL"
);

static const char vertexShaderCode[] = R"(#version 410 core
uniform vec2 MaxUV;

layout( location = 0 ) in vec4 vPosition;
layout( location = 1 ) in vec2 vUV;

out vec2 uv;
out vec2 contourUV;

void main()
{
	gl_Position = vPosition;
	uv = vUV * MaxUV;
	contourUV = vec2( vUV.x, 1.0 - vUV.y );
}
)";

static const char fragmentShaderCode[] = R"(#version 410 core
uniform sampler2D InputTexture;
uniform sampler2D ContourTexture;
uniform vec4 LightColor;
uniform float Opacity;
uniform float CompOverInput;
uniform int HasContours;

in vec2 uv;
in vec2 contourUV;

out vec4 fragColor;

vec3 hsbToRgb( vec3 c )
{
	vec3 rgb = clamp( abs( mod( c.x * 6.0 + vec3( 0.0, 4.0, 2.0 ), 6.0 ) - 3.0 ) - 1.0, 0.0, 1.0 );
	rgb = rgb * rgb * ( 3.0 - 2.0 * rgb );
	return c.z * mix( vec3( 1.0 ), rgb, c.y );
}

void main()
{
	vec4 color = texture( InputTexture, uv );

	if( HasContours == 0 )
	{
		fragColor = CompOverInput >= 0.5 ? color : vec4( 0.0 );
		return;
	}

	float contour = texture( ContourTexture, contourUV ).r;
	contour = clamp( contour * LightColor.a * Opacity, 0.0, 1.0 );
	vec3 lightColor = hsbToRgb( LightColor.rgb );

	if( CompOverInput >= 0.5 )
	{
		fragColor = vec4( min( color.rgb + lightColor * contour, vec3( 1.0 ) ), max( color.a, contour ) );
		return;
	}

	fragColor = vec4( lightColor * contour, contour );
}
)";

AppleContourDetection::AppleContourDetection() :
	contourTexture( 0 ),
	contourWidth( 0 ),
	contourHeight( 0 ),
	hasContours( false ),
	loggedVisionSuccess( false ),
	loggedVisionFailure( false ),
	loggedVisionUnavailable( false ),
	contrast( 0.604701f ),
	lineWidth( 0.297084f ),
	hue( 0.0f ),
	saturation( 0.0f ),
	brightness( 1.0f ),
	alpha( 1.0f ),
	opacity( 1.0f ),
	compOverInput( 0.0f )
{
	SetMinInputs( 1 );
	SetMaxInputs( 1 );

	SetParamInfof( PT_CONTRAST, "Contrast", FF_TYPE_STANDARD );
	SetParamInfof( PT_LINE_WIDTH, "Line Width", FF_TYPE_STANDARD );
	SetParamInfof( PT_HUE, "Hue 1", FF_TYPE_HUE );
	SetParamInfof( PT_SATURATION, "Saturation 1", FF_TYPE_SATURATION );
	SetParamInfof( PT_BRIGHTNESS, "Brightness 1", FF_TYPE_BRIGHTNESS );
	SetParamInfof( PT_ALPHA, "Alpha 1", FF_TYPE_ALPHA );
	SetParamInfof( PT_OPACITY, "Opacity", FF_TYPE_STANDARD );
	SetParamInfo( PT_COMP_OVER_INPUT, "Comp Over Input", FF_TYPE_BOOLEAN, false );

	FFGLLog::LogToHost( "Created Apple Contour Detection effect" );
}

AppleContourDetection::~AppleContourDetection()
{
	DeInitGL();
}

FFResult AppleContourDetection::InitGL( const FFGLViewportStruct* vp )
{
	if( !shader.Compile( vertexShaderCode, fragmentShaderCode ) )
	{
		DeInitGL();
		return FF_FAIL;
	}

	if( !quad.Initialise() )
	{
		DeInitGL();
		return FF_FAIL;
	}

	glGenTextures( 1, &contourTexture );
	glBindTexture( GL_TEXTURE_2D, contourTexture );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	glBindTexture( GL_TEXTURE_2D, 0 );

	return CFFGLPlugin::InitGL( vp );
}

FFResult AppleContourDetection::ProcessOpenGL( ProcessOpenGLStruct* pGL )
{
	if( pGL->numInputTextures < 1 )
		return FF_FAIL;

	if( pGL->inputTextures[ 0 ] == NULL )
		return FF_FAIL;

	const FFGLTextureStruct& inputTexture = *pGL->inputTextures[ 0 ];
	UpdateContourTexture( inputTexture );

	ScopedShaderBinding shaderBinding( shader.GetGLID() );
	ScopedSamplerActivation activateInputSampler( 0 );
	Scoped2DTextureBinding textureBinding( inputTexture.Handle );

	shader.Set( "InputTexture", 0 );

	FFGLTexCoords maxCoords = GetMaxGLTexCoords( inputTexture );
	shader.Set( "MaxUV", maxCoords.s, maxCoords.t );

	ScopedSamplerActivation activateContourSampler( 1 );
	Scoped2DTextureBinding contourBinding( contourTexture );
	shader.Set( "ContourTexture", 1 );

	shader.Set( "LightColor", hue, saturation, brightness, alpha );
	shader.Set( "Opacity", opacity );
	shader.Set( "CompOverInput", compOverInput );
	shader.Set( "HasContours", hasContours ? 1 : 0 );

	quad.Draw();

	return FF_SUCCESS;
}

FFResult AppleContourDetection::DeInitGL()
{
	shader.FreeGLResources();
	quad.Release();
	ReleaseContourTexture();
	return FF_SUCCESS;
}

FFResult AppleContourDetection::SetFloatParameter( unsigned int dwIndex, float value )
{
	switch( dwIndex )
	{
	case PT_CONTRAST:
		contrast = value;
		break;
	case PT_LINE_WIDTH:
		lineWidth = value;
		break;
	case PT_HUE:
		hue = value;
		break;
	case PT_SATURATION:
		saturation = value;
		break;
	case PT_BRIGHTNESS:
		brightness = value;
		break;
	case PT_ALPHA:
		alpha = value;
		break;
	case PT_OPACITY:
		opacity = value;
		break;
	case PT_COMP_OVER_INPUT:
		compOverInput = value >= 0.5f ? 1.0f : 0.0f;
		break;
	default:
		return FF_FAIL;
	}

	return FF_SUCCESS;
}

float AppleContourDetection::GetFloatParameter( unsigned int index )
{
	switch( index )
	{
	case PT_CONTRAST:
		return contrast;
	case PT_LINE_WIDTH:
		return lineWidth;
	case PT_HUE:
		return hue;
	case PT_SATURATION:
		return saturation;
	case PT_BRIGHTNESS:
		return brightness;
	case PT_ALPHA:
		return alpha;
	case PT_OPACITY:
		return opacity;
	case PT_COMP_OVER_INPUT:
		return compOverInput;
	}

	return 0.0f;
}

bool AppleContourDetection::UpdateContourTexture( const FFGLTextureStruct& inputTexture )
{
	if( !GenerateContourMask( inputTexture ) )
	{
		hasContours = false;
		return false;
	}

	GLint previousUnpackAlignment = 0;
	glGetIntegerv( GL_UNPACK_ALIGNMENT, &previousUnpackAlignment );
	glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );

	glBindTexture( GL_TEXTURE_2D, contourTexture );
	glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, contourWidth, contourHeight, 0, GL_RED, GL_UNSIGNED_BYTE, contourPixels.data() );
	glBindTexture( GL_TEXTURE_2D, 0 );

	glPixelStorei( GL_UNPACK_ALIGNMENT, previousUnpackAlignment );
	hasContours = true;
	return true;
}

bool AppleContourDetection::GenerateContourMask( const FFGLTextureStruct& inputTexture )
{
#if defined( __APPLE__ )
	if( inputTexture.Width == 0 || inputTexture.Height == 0 || inputTexture.HardwareWidth == 0 || inputTexture.HardwareHeight == 0 )
		return false;

	if( @available( macOS 11.0, * ) )
	{
		const size_t hardwareWidth = inputTexture.HardwareWidth;
		const size_t hardwareHeight = inputTexture.HardwareHeight;
		const size_t width = inputTexture.Width;
		const size_t height = inputTexture.Height;

		rgbaPixels.resize( hardwareWidth * hardwareHeight * 4 );
		bgraPixels.resize( width * height * 4 );

		GLint previousPackAlignment = 0;
		glGetIntegerv( GL_PACK_ALIGNMENT, &previousPackAlignment );
		glPixelStorei( GL_PACK_ALIGNMENT, 1 );
		glBindTexture( GL_TEXTURE_2D, inputTexture.Handle );
		glGetTexImage( GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgbaPixels.data() );
		glBindTexture( GL_TEXTURE_2D, 0 );
		glPixelStorei( GL_PACK_ALIGNMENT, previousPackAlignment );

		for( size_t y = 0; y < height; ++y )
		{
			const size_t sourceY = height - 1 - y;
			const unsigned char* sourceRow = rgbaPixels.data() + ( sourceY * hardwareWidth * 4 );
			unsigned char* destRow = bgraPixels.data() + ( y * width * 4 );

			for( size_t x = 0; x < width; ++x )
			{
				const unsigned char* sourcePixel = sourceRow + ( x * 4 );
				unsigned char* destPixel = destRow + ( x * 4 );
				destPixel[ 0 ] = sourcePixel[ 2 ];
				destPixel[ 1 ] = sourcePixel[ 1 ];
				destPixel[ 2 ] = sourcePixel[ 0 ];
				destPixel[ 3 ] = sourcePixel[ 3 ];
			}
		}

		CVPixelBufferRef sourceBuffer = nullptr;
		CVReturn cvResult = CVPixelBufferCreate( kCFAllocatorDefault,
												 width,
												 height,
												 kCVPixelFormatType_32BGRA,
												 nullptr,
												 &sourceBuffer );
		if( cvResult != kCVReturnSuccess || sourceBuffer == nullptr )
		{
			if( !loggedVisionFailure )
			{
				FFGLLog::LogToHost( "Apple Contour Detection: failed to create CVPixelBuffer for Vision input" );
				loggedVisionFailure = true;
			}
			return false;
		}

		CVPixelBufferLockBaseAddress( sourceBuffer, 0 );
		unsigned char* baseAddress = static_cast< unsigned char* >( CVPixelBufferGetBaseAddress( sourceBuffer ) );
		const size_t bytesPerRow = CVPixelBufferGetBytesPerRow( sourceBuffer );
		for( size_t y = 0; y < height; ++y )
		{
			std::memcpy( baseAddress + y * bytesPerRow, bgraPixels.data() + y * width * 4, width * 4 );
		}
		CVPixelBufferUnlockBaseAddress( sourceBuffer, 0 );

		contourWidth = static_cast< unsigned int >( width );
		contourHeight = static_cast< unsigned int >( height );
		ClearMask( width, height );

		bool success = false;

		@autoreleasepool
		{
			VNDetectContoursRequest* request = [[VNDetectContoursRequest alloc] init];
			request.contrastAdjustment = contrast;
			request.detectsDarkOnLight = false;
			request.maximumImageDimension = 1152;

			NSError* error = nil;
			VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:sourceBuffer options:@{}];
			BOOL performed = [handler performRequests:@[ request ] error:&error];

			if( performed && request.results.count > 0 )
			{
				VNContoursObservation* observation = static_cast< VNContoursObservation* >( request.results.firstObject );
				const NSInteger contourCount = observation.contourCount;
				const int radius = std::max( 0, static_cast< int >( std::floor( lineWidth * 12.0f ) ) );

				for( NSInteger contourIndex = 0; contourIndex < contourCount; ++contourIndex )
				{
					NSError* contourError = nil;
					VNContour* contour = [observation contourAtIndex:contourIndex error:&contourError];
					if( contour == nil || contour.pointCount < 2 )
						continue;

					const simd_float2* points = contour.normalizedPoints;
					const NSInteger pointCount = contour.pointCount;
					for( NSInteger pointIndex = 1; pointIndex < pointCount; ++pointIndex )
					{
						const simd_float2 previousPoint = points[ pointIndex - 1 ];
						const simd_float2 currentPoint = points[ pointIndex ];

						const int x0 = static_cast< int >( std::round( previousPoint.x * static_cast< float >( width - 1 ) ) );
						const int y0 = static_cast< int >( std::round( ( 1.0f - previousPoint.y ) * static_cast< float >( height - 1 ) ) );
						const int x1 = static_cast< int >( std::round( currentPoint.x * static_cast< float >( width - 1 ) ) );
						const int y1 = static_cast< int >( std::round( ( 1.0f - currentPoint.y ) * static_cast< float >( height - 1 ) ) );

						DrawLine( x0, y0, x1, y1, radius );
					}
				}

				if( !loggedVisionSuccess )
				{
					const std::string message = "Apple Contour Detection: Vision contours active, input " +
						std::to_string( width ) + "x" + std::to_string( height ) +
						", contours " + std::to_string( contourCount );
					FFGLLog::LogToHost( message.c_str() );
					loggedVisionSuccess = true;
				}

				success = true;
			}
			else if( !loggedVisionFailure )
			{
				std::string message = "Apple Contour Detection: Vision request failed or returned no contours";
				if( error != nil && error.localizedDescription != nil )
					message += std::string( ": " ) + [error.localizedDescription UTF8String];
				FFGLLog::LogToHost( message.c_str() );
				loggedVisionFailure = true;
			}

			[handler release];
			[request release];
		}

		CVPixelBufferRelease( sourceBuffer );
		return success;
	}

	if( !loggedVisionUnavailable )
	{
		FFGLLog::LogToHost( "Apple Contour Detection: Vision contour detection requires macOS 11 or newer" );
		loggedVisionUnavailable = true;
	}
#endif

	return false;
}

void AppleContourDetection::ClearMask( size_t width, size_t height )
{
	contourPixels.assign( width * height, 0 );
}

void AppleContourDetection::DrawLine( int x0, int y0, int x1, int y1, int radius )
{
	const int dx = std::abs( x1 - x0 );
	const int sx = x0 < x1 ? 1 : -1;
	const int dy = -std::abs( y1 - y0 );
	const int sy = y0 < y1 ? 1 : -1;
	int error = dx + dy;

	for( ;; )
	{
		StampPoint( x0, y0, radius );
		if( x0 == x1 && y0 == y1 )
			break;

		const int e2 = 2 * error;
		if( e2 >= dy )
		{
			error += dy;
			x0 += sx;
		}
		if( e2 <= dx )
		{
			error += dx;
			y0 += sy;
		}
	}
}

void AppleContourDetection::StampPoint( int centerX, int centerY, int radius )
{
	const int width = static_cast< int >( contourWidth );
	const int height = static_cast< int >( contourHeight );
	const int radiusSquared = radius * radius;

	for( int y = centerY - radius; y <= centerY + radius; ++y )
	{
		if( y < 0 || y >= height )
			continue;

		for( int x = centerX - radius; x <= centerX + radius; ++x )
		{
			if( x < 0 || x >= width )
				continue;

			const int offsetX = x - centerX;
			const int offsetY = y - centerY;
			if( offsetX * offsetX + offsetY * offsetY > radiusSquared )
				continue;

			contourPixels[ static_cast< size_t >( y ) * contourWidth + static_cast< size_t >( x ) ] = 255;
		}
	}
}

void AppleContourDetection::ReleaseContourTexture()
{
	if( contourTexture != 0 )
	{
		glDeleteTextures( 1, &contourTexture );
		contourTexture = 0;
	}

	contourWidth = 0;
	contourHeight = 0;
	hasContours = false;
}
